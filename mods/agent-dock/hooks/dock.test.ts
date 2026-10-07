import { test, expect } from 'claude-code/testing'

// A prompt another plugin sends must not eat the team size or carry the note.
test('dock size is kept for the person, not for a plugin prompt', async ($, on) => {
  const seen: string[][] = []
  on('ui.open', () => ({ value: undefined }) as never)
  on('prompt.submit', (_$, e) => {
    seen.push([...(e.context ?? [])])
    return { text: e.text }
  })
  await $.command.run({ command: 'dock', args: '5 cheap' })
  await $.prompt.submit({ text: 'from a plugin' })
  expect(seen).toEqual([[]])
})
