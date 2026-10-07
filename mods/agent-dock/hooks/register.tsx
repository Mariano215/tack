import { atom, read, update } from 'claude-code'
import type { Register } from 'claude-code'

const PANE = 'agent-dock'
const size = atom({ plugin: 'agent-dock', key: 'size' } as const, 0)
const cheap = atom({ plugin: 'agent-dock', key: 'cheap' } as const, false)
const tick = atom({ plugin: 'agent-dock', key: 'tick' } as const, 0)

const BIG = 10

export const register: Register = on => {
  on('session.start', async ($, e, next) => {
    await $.command.register({
      name: 'dock',
      description: 'Agent dock: /dock <n> [cheap|same] sets the team for the next prompt, /dock alone opens the cards',
    })
    $.clock.every(1000, () => void update($, tick, n => n + 1))
    return next(e)
  })

  on('command.run', { command: 'dock' }, async ($, e) => {
    const words = e.args.trim().split(/\s+/).filter(Boolean)
    const n = Number(words.find(w => /^\d+$/.test(w)))
    if (words.includes('cheap')) await update($, cheap, () => true)
    if (words.includes('same')) await update($, cheap, () => false)
    if (n > 0) await update($, size, () => Math.min(n, 50))
    await $.ui.open({ id: PANE, title: 'Agent dock' })
    if (n >= BIG) $.ui.toast(`${n} agents will use your plan fast. Confirm by sending the prompt.`)
    return { text: `Next prompt: ${n > 0 ? Math.min(n, 50) : await read($, size)} agents, ${(await read($, cheap)) ? 'cheap and fast helpers' : 'same model'}.` }
  })

  // The team size covers one prompt, then clears. The helper type stays.
  on('prompt.submit', async ($, e, next) => {
    const n = await read($, size)
    if (n === 0 || e.origin.kind === 'plugin') return next(e)
    await update($, size, () => 0)
    const note = `Dock: split this job across up to ${n} parallel subagents and combine their results.`
    return next({ ...e, context: [...(e.context ?? []), note] })
  })

  on('agent.spawn', async ($, e, next) => {
    return (await read($, cheap)) ? next({ ...e, model: 'haiku' }) : next(e)
  })

  on('ui.render', { component: 'Pane', requestId: PANE }, async ($, e) => {
    const { Box, Text } = $.ui.resolve(e)
    await read($, tick)
    const agents = await $.agent.list()
    const room = Math.max(1, (e.viewport?.rows ?? 24) - 5)
    const active = agents.filter(a => a.status === 'running' || a.status === 'pending' || a.status === 'waiting')
    const planned = await read($, size)

    return (
      <Box flexDirection="column">
        <Text dimColor>
          {planned > 0 ? `next prompt: ${planned} agents. ` : ''}
          {active.length} active, {agents.length - active.length} done or idle
        </Text>
        {agents.slice(-room).map(a => (
          <Text dimColor={a.status === 'completed'}>
            [{a.status}] {a.type}: {a.description}
          </Text>
        ))}
        {agents.length === 0 && <Text dimColor>No agents yet. Try /dock 5 cheap, then send a big job.</Text>}
      </Box>
    )
  })
}
