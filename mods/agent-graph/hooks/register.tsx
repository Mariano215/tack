import { atom, read, update } from 'claude-code'
import type { Register } from 'claude-code'

import type { Node, Status } from '../types'

const nodes = atom({ plugin: 'agent-graph', key: 'nodes' } as const, {} as Record<string, Node>)
const isFading = atom({ plugin: 'agent-graph', key: 'isFading' } as const, false)

const FADE_MS = 4000
const MARK: Record<Status, string> = { running: '●', done: '✓', error: '✗', aborted: '■' }
const COLOR: Record<Status, string> = { running: 'yellow', done: 'green', error: 'red', aborted: 'gray' }
const BAR = 10
// No agent says how much work it has left, so a running bar is tools used
// against the average tool count of past finished runs of the same type.
// ponytail: tool count is a rough proxy for work, swap in a better signal if one appears
const DEFAULT_EXPECTED = 10
const avgKey = (type: string) => `avg-tools:${type}`

function share(n: Node) {
  if (n.status === 'running') return Math.min(0.95, n.tools / n.expected)
  return n.status === 'aborted' ? Math.min(1, n.tools / n.expected) : 1
}

// Depth-first order so children sit under their parent. Parents not in the
// map (the main loop, or a parent already cleared) count as roots.
function ordered(all: Record<string, Node>) {
  const kids: Record<string, Node[]> = {}
  for (const n of Object.values(all)) {
    const p = n.parent !== null && all[n.parent] ? n.parent : ''
    ;(kids[p] ??= []).push(n)
  }
  const out: { node: Node; prefix: string }[] = []
  const walk = (p: string, indent: string) => {
    const list = (kids[p] ?? []).sort((a, b) => a.startedAt - b.startedAt)
    list.forEach((node, i) => {
      const last = i === list.length - 1
      out.push({ node, prefix: indent + (last ? '└─ ' : '├─ ') })
      walk(node.id, indent + (last ? '   ' : '│  '))
    })
  }
  walk('', '')
  return out
}

export const register: Register = on => {
  // ponytail: module-level timer handle, a hot reload mid-fade drops it and the tree stays until the next spawn finishes
  let fade: { cancel: () => void } | undefined

  on('agent.spawn', async ($, e, next) => {
    const result = await next(e)
    if (result.agentId === undefined) return result
    const id = result.agentId
    fade?.cancel()
    fade = undefined
    const node: Node = {
      id,
      parent: e.parentAgentId ?? null,
      label: e.name ?? e.description,
      type: e.subagentType,
      model: result.model,
      effort: null,
      status: 'running',
      tools: 0,
      expected: Number(await $.store.get(avgKey(e.subagentType))) || DEFAULT_EXPECTED,
      lastTool: null,
      startedAt: await $.clock.now(),
      ms: null,
    }
    await update($, isFading, () => false)
    await update($, nodes, all => ({ ...all, [id]: node }))
    return result
  })

  on('tool.call', async ($, e, next) => {
    const id = e.agentId
    if (id !== undefined && (await read($, nodes))[id]) {
      await update($, nodes, all =>
        all[id] ? { ...all, [id]: { ...all[id], tools: all[id].tools + 1, lastTool: e.tool } } : all,
      )
    }
    return next(e)
  })

  // turn.step names the model and effort each request is really sent with.
  on('turn.step', async function* ($, e, next) {
    const id = e.agentId
    const effort = e.effort === undefined ? null : String(e.effort)
    const n = id === undefined ? undefined : (await read($, nodes))[id]
    if (id !== undefined && n && (n.model !== e.model || n.effort !== effort)) {
      await update($, nodes, all =>
        all[id] ? { ...all, [id]: { ...all[id], model: e.model, effort } } : all,
      )
    }
    return yield* next(e)
  })

  on('turn.complete', async ($, e, next) => {
    const id = e.agentId
    if (id === undefined || !(await read($, nodes))[id]) return next(e)
    const status: Status = e.reason === 'answer' ? 'done' : e.reason === 'aborted' ? 'aborted' : 'error'
    const all = await update($, nodes, all =>
      all[id] ? { ...all, [id]: { ...all[id], status, ms: e.durationMs } } : all,
    )
    const n = all[id]
    if (status === 'done' && n) {
      const old = Number(await $.store.get(avgKey(n.type)))
      await $.store.set(avgKey(n.type), old ? Math.max(1, old * 0.7 + n.tools * 0.3) : Math.max(1, n.tools))
    }
    if (!Object.values(all).some(n => n.status === 'running')) {
      await update($, isFading, () => true)
      fade?.cancel()
      fade = $.clock.after(FADE_MS, async () => {
        await update($, nodes, () => ({}))
        await update($, isFading, () => false)
      })
    }
    return next(e)
  })

  on('ui.render', { component: 'AbovePrompt' }, async ($, e, next) => {
    const all = await read($, nodes)
    const rows = ordered(all)
    if (e.props.hasSurvey || rows.length === 0) return next(e)

    const dim = await read($, isFading)
    const { Box, Text } = $.ui.resolve(e)
    const finished = rows.filter(r => r.node.status !== 'running').length
    const width = 20
    const filled = Math.round((finished / rows.length) * width)
    const shown = rows.slice(0, Math.max(1, e.props.maxRows - 1))

    return (
      <Box flexDirection="column">
        <Text dimColor={dim}>
          <Text bold>Agents </Text>
          <Text color="green">{'█'.repeat(filled)}</Text>
          <Text dimColor>{'░'.repeat(width - filled)}</Text>
          {` ${finished}/${rows.length} done`}
        </Text>
        {shown.map(({ node, prefix }) => (
          <Text key={node.id} dimColor={dim} wrap="truncate-end">
            <Text dimColor>{prefix}</Text>
            <Text color={COLOR[node.status]}>{MARK[node.status]} </Text>
            <Text color={COLOR[node.status]}>{'█'.repeat(Math.round(share(node) * BAR))}</Text>
            <Text dimColor>{'░'.repeat(BAR - Math.round(share(node) * BAR))} </Text>
            <Text bold>{node.label}</Text>
            <Text dimColor>
              {` ${node.type} · ${node.model}${node.effort ? `/${node.effort}` : ''} · ${node.tools} tools`}
              {node.status === 'running' && node.lastTool ? ` · ${node.lastTool}` : ''}
              {node.ms !== null ? ` · ${Math.round(node.ms / 1000)}s` : ''}
            </Text>
          </Text>
        ))}
      </Box>
    )
  })
}
