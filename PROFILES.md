# Community profiles

A curated list of published tack profiles.

**Discovery:** anything tagged with the [`tack-profile`](https://github.com/topics/tack-profile)
GitHub topic. This file is the curated subset.

## Read this before installing someone else's profile

Installing a profile is not like installing a library. `tack use <name>` runs
that repo's `install.sh` as shell, and the profile it applies can:

- set `permissions.defaultMode`, which changes how often the agent asks you
  before writing files or running commands
- install `hooks/`, which execute on every session afterwards
- enable MCP servers pointing at any host
- install `skills/`, which are markdown that becomes instructions the agent
  follows

Treat a profile repo exactly like a shell script you found online, because that
is what it is. Read `manifest.json` and `install.sh` before you run them. A
canonical `install.sh` is three lines and nothing else:

```bash
#!/usr/bin/env bash
set -euo pipefail
git submodule update --init --recursive
exec bash ./core/lib/apply-profile.sh ./manifest.json
```

Anything beyond that is doing something the manifest does not describe.

Apply an unfamiliar profile to an isolated config dir first, never your main one:

```bash
tack shell <name>    # writes to ~/.claude-profiles/<name>, not ~/.claude
```

Delete it with `rm -rf ~/.claude-profiles/<name>` if you do not like what you see.

## The list

| Profile | By | What it is for |
|---|---|---|
| [tack-profile-example](https://github.com/Mariano215/tack-profile-example) | Mariano215 | Starter template. Fork this to begin. |

## Publishing yours

1. Name the repo `tack-<something>` and make it public.
2. Add the `tack-profile` topic: repo page, gear icon next to About, or
   `gh repo edit --add-topic tack-profile`.
3. Keep `install.sh` to the canonical three lines above. A profile that needs
   custom install logic is not reproducible from its manifest, which is the
   whole point of the format.
4. Write a README saying what the profile is for, which plugins and MCP servers
   it enables, and whether it sets `permissions.defaultMode`.
5. Open a PR adding one row to the table here.

## What gets listed

This is a curated list, not a registry. A row gets merged when the repo:

- has the `tack-profile` topic and a public README explaining its purpose
- has a canonical `install.sh`
- declares in its README if it changes `permissions.defaultMode`, adds hooks,
  or enables MCP servers, since those are the three that change your security
  posture
- applies cleanly with `tack shell <name>`

Listing is not an endorsement or an audit. Nobody reviews these for malicious
content. The bar is "documented and honest about what it changes," and you are
still responsible for reading a profile before running it.
