export type Size = number

declare module 'claude-code' {
  interface PluginState {
    'agent-dock': { size: Size; cheap: boolean; tick: number }
  }
}
