## What changed

<!-- one or two sentences -->

## Why

<!-- the problem, not the diff -->

## Checks

- [ ] `git add -A && bash scripts/check.sh` passes
- [ ] `bash scripts/test-apply.sh` passes
- [ ] If this touches `lib/apply-profile.sh`: the change is reversible, prints how to undo itself, and has a case in `test-apply.sh`
- [ ] No new runtime dependency beyond bash, jq, git, python3
- [ ] No em-dashes or en-dashes
