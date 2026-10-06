---
name: animate-chatterbox
description: Voice-overs for the animate skill from the self-hosted Chatterbox server instead of ElevenLabs. Use whenever an animate piece has a narrated voice-over and CHATTERBOX_URL is set.
---

# Chatterbox voice for animate

This replaces step 3 ("The takes") of the Voice-over section in animate's SKILL.md.
Everything else in that section stays as written.

## Rules

- At intake, when the user picks a voice-over, the voice is Chatterbox with the voice
  in `CHATTERBOX_VOICE`. Do not offer or search for ElevenLabs narrators.
- If `CHATTERBOX_URL` or `CHATTERBOX_VOICE` is unset, say so and offer the user's own
  recording or the scratch voice. Do not fall back to ElevenLabs silently.
- The script is written for the voice: plain sentences, numbers spelled the way they
  should be spoken, one line per beat.

## Steps

1. Write `pieces/<name>/voice/script.json` (animate's format, no `file` fields needed).
2. Build against a timing voice first, as animate says:
   `node <animate>/tools/voice.mjs pieces/<name> --scratch`
3. Real takes, one WAV per line:
   `node <this skill>/chatterbox-voice.mjs pieces/<name>`
   It skips lines that already have a take, so a rerun only fills gaps.
4. Time the words and build the track:
   `node <animate>/tools/voice.mjs pieces/<name>`
5. Rebuild and review the piece.

## Re-takes

A line that sounds wrong: `chatterbox-voice.mjs pieces/<name> --only <id> --force`,
then steps 4 and 5. Scenes cued from `VOICE` move with the new timing.
For a flat or overcooked read, adjust `CHATTERBOX_EXAGGERATION` (higher is more
expressive) or `CHATTERBOX_CFG_WEIGHT` (lower is slower, more deliberate) for that one
run. Set `CHATTERBOX_SEED` to keep re-takes consistent with each other.

## Server

`CHATTERBOX_API=tts` (default) posts `{ text, voice }` to `/v1/tts`, the self-hosted wrapper.
It takes no tuning, so the `CHATTERBOX_*` tuning knobs above apply only to `openai`
(`/v1/audio/speech`) and `native` (`/tts` with a predefined voice).
Check the server first: `curl $CHATTERBOX_URL/health`, and `curl $CHATTERBOX_URL/v1/voices`
to confirm `CHATTERBOX_VOICE` is listed. The first take after idle is slow while the
model loads. A non-WAV reply or an HTTP error stops the run and names the fix.
