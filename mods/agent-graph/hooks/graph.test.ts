import { test, expect, mock } from 'claude-code/testing'

const BAND = {
  component: 'AbovePrompt',
  props: { hasSurvey: false, isWorking: true, maxRows: 10, bodyColumns: 120, scroll: null },
} as const

const spawn = (description: string, parentAgentId?: string) => ({
  tool_use_id: `tu-${description}`,
  prompt: 'p',
  description,
  subagentType: 'Explore',
  provider: { plugin: 'engine', tier: 'core' },
  parentModel: 'opus',
  background: false,
  fork: false,
  ...(parentAgentId ? { parentAgentId } : {}),
}) as never

const done = (agentId: string) =>
  ({ agentId, answer: 'ok', durationMs: 3000, isAborted: false, turnId: `t-${agentId}`, reason: 'answer' }) as never

test('nested agents show as a tree with model and progress, then fade out', async ($, on) => {
  const clock = mock.clock(on)
  mock.store(on)
  on('agent.spawn', (_$, e) => ({ model: 'haiku', agentId: (e as { description: string }).description }))
  on('turn.complete', () => ({ text: '' }))
  on('ui.render', ($, e) => h($.ui.resolve(e).Text, {}, 'engine') as never)

  await $.agent.spawn(spawn('orchestrator'))
  await $.agent.spawn(spawn('worker', 'orchestrator'))

  for (const surface of ['terminal', 'desktop'] as const) {
    const ui = await $.ui.mount({ plugin: 'agent-graph', surface, ...BAND } as never)
    expect(await ui.find({ type: 'Text', text: /0\/2 done/ })).toBeDefined()
    expect(await ui.find({ type: 'Text', text: /^   └─ $/ })).toBeDefined()
    expect(await ui.find({ type: 'Text', text: /haiku/ })).toBeDefined()
    expect(await ui.findAll({ type: 'Text', text: /^░{10} $/ })).toHaveLength(2)
  }

  await $.turn.complete(done('worker'))
  await $.turn.complete(done('orchestrator'))
  let ui = await $.ui.mount({ plugin: 'agent-graph', surface: 'terminal', ...BAND } as never)
  expect(await ui.find({ type: 'Text', text: /2\/2 done/ })).toBeDefined()
  expect(await ui.findAll({ type: 'Text', text: /^█{10}$/ })).toHaveLength(2)

  await clock.advance(5000)
  ui = await $.ui.mount({ plugin: 'agent-graph', surface: 'terminal', ...BAND } as never)
  expect(await ui.find({ type: 'Text', text: /done/ })).toBeUndefined()
})
