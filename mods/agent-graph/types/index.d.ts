export type Status = 'running' | 'done' | 'error' | 'aborted'

export type Node = {
  id: string
  parent: string | null
  label: string
  type: string
  model: string
  effort: string | null
  status: Status
  tools: number
  expected: number
  lastTool: string | null
  startedAt: number
  ms: number | null
}

declare module 'claude-code' {
  interface PluginState {
    'agent-graph': { nodes: Record<string, Node>; isFading: boolean }
  }
}
