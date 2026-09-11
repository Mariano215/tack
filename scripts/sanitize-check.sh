#!/usr/bin/env bash
# sanitize-check.sh
# Pre-commit sweep: fail if personal data or engagement references are about
# to ship. The public GitHub handle in clone URLs is allowed; personal email,
# home paths, the maintainer's external volume, and client paths are not.
set -uo pipefail

# Sweep the repo we were invoked from, so a profile repo can run core's copy
# (bash core/scripts/sanitize-check.sh) instead of keeping a stale duplicate.
# Falls back to this script's own repo when cwd is not inside a checkout.
REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null)"
[ -n "$REPO_ROOT" ] || REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

# Note: generic "~/Clients/" detection patterns in hooks/skills are functional
# (client-context checks), so "Clients/" is deliberately NOT in this sweep.
#
# A fork must be able to sweep for its own names, not the original maintainer's,
# so the list lives in .sanitize-patterns when present: one extended-regex
# alternative per line, blank lines and # comments ignored. The built-in default
# below is what this repo ships with.
# The built-in list is deliberately generic. Client and employer names are the
# most valuable thing this sweep can catch and the worst thing to hardcode: a
# deny list naming them publishes them to anyone who reads the script. Put those
# in .sanitize-patterns, which is yours and need not be public.
PATTERNS='/Users/[a-z]|/home/[a-z]|@gmail\.|@outlook\.|@yahoo\.'
PATTERNS="$PATTERNS|BEGIN [A-Z ]*PRIVATE KEY|sk-[A-Za-z0-9_-]{20}|ghp_[A-Za-z0-9]{20}|AKIA[0-9A-Z]{16}"
if [ -f .sanitize-patterns ]; then
    PATTERNS=''
    while IFS= read -r line; do
        line="${line%$'\r'}"  # a CRLF checkout (core.autocrlf) would end every entry in CR and match nothing
        case "$line" in ''|'#'*) continue ;; esac
        PATTERNS="${PATTERNS:+$PATTERNS|}$line"
    done < .sanitize-patterns
fi
if [ -z "$PATTERNS" ]; then
    echo "sanitize-check: .sanitize-patterns is present but has no patterns."
    echo "  Fix: add at least one regex line, or delete the file to use the built-in default. An empty list would sweep for nothing and report clean."
    exit 2
fi

# Commit author identity ships in the repo just like file content does, and no
# amount of scrubbing the tree removes it. A machine with a stale git user.email
# writes a former employer's domain into every commit it makes. Check what is
# about to be pushed, not all of history: this repo already carries identities
# that predate the check and cannot be edited without a rewrite.
# .local and .invalid are the generic tells: a git identity nobody configured,
# built from the machine hostname. Add your own former-employer domains in
# .sanitize-authors-deny rather than here, for the same reason as PATTERNS.
DENY_AUTHORS='\.local$|\.invalid$|\.localdomain$'
if [ -f .sanitize-authors-deny ]; then
    while IFS= read -r line; do
        line="${line%$'\r'}"  # a CRLF checkout (core.autocrlf) would end every entry in CR and match nothing
        case "$line" in ''|'#'*) continue ;; esac
        DENY_AUTHORS="$DENY_AUTHORS|$line"
    done < .sanitize-authors-deny
fi
upstream="$(git rev-parse --abbrev-ref --symbolic-full-name '@{upstream}' 2>/dev/null | tr -d '\r')"
if [ -n "$upstream" ]; then
    authors=$(git log --format='%ae' "$upstream..HEAD" 2>/dev/null)
else
    authors=$(git log -1 --format='%ae' 2>/dev/null)
fi
bad_authors=$(printf '%s\n' "$authors" | sort -u | grep -iE "$DENY_AUTHORS" || true)
if [ -n "$bad_authors" ]; then
    echo "$bad_authors"
    echo ""
    echo "FAIL: commit author identity matches a denied domain (patterns: $DENY_AUTHORS)"
    echo "  Fix: set the right identity with 'git config user.email you@example.com', then rewrite the offending commits with 'git rebase -i --exec \"git commit --amend --no-edit --reset-author\"' before pushing."
    exit 1
fi

# Optional per-repo exemptions: one git pathspec per line in .sanitize-allow,
# blank lines and # comments ignored. For files whose whole point is a local
# machine (a skill documenting one box, one account). Keep each one commented
# in that file so an exemption is reviewable rather than silent.
# Both files are excluded from their own sweep: each has to name the patterns or
# the paths it exists to describe, and an exemption comment saying why a client
# name is present would otherwise trip on that client name.
excludes=(':!scripts/sanitize-check.sh' ':!.sanitize-allow' ':!.sanitize-patterns' ':!.sanitize-authors-deny')
if [ -f .sanitize-allow ]; then
    while IFS= read -r line; do
        line="${line%$'\r'}"  # a CRLF checkout (core.autocrlf) would end every entry in CR and match nothing
        case "$line" in ''|'#'*) continue ;; esac
        excludes+=(":!$line")
    done < .sanitize-allow
fi

hits=$(git grep -nIiE "$PATTERNS" -- . "${excludes[@]}" 2>/dev/null)
status=$?

# git grep reads the index, so a brand new file is invisible to it right up to
# the commit that adds it, and nobody re-runs the sweep at that moment. Sweep
# untracked files too. This is how eleven skills reached the point of being
# pushed with personal paths in them. --exclude-standard honours .gitignore, so
# build output and secrets stay out.
untracked=$(git ls-files --others --exclude-standard -z 2>/dev/null \
  | xargs -0 grep -nIiE "$PATTERNS" /dev/null 2>/dev/null || true)
# The self-exclusions above are git pathspecs, which only apply to the tracked
# sweep. An as-yet-uncommitted .sanitize-allow would otherwise trip on the very
# names its comments exist to explain.
untracked=$(printf '%s\n' "$untracked" \
  | grep -v '^\(\.sanitize-\(allow\|patterns\|authors-deny\)\|scripts/sanitize-check\.sh\):' || true)
# .sanitize-allow is a git pathspec list, which the plain grep above does not
# understand, so apply it here as a prefix match on the reported path.
if [ -n "$untracked" ] && [ -f .sanitize-allow ]; then
    while IFS= read -r line; do
        line="${line%$'\r'}"  # a CRLF checkout (core.autocrlf) would end every entry in CR and match nothing
        case "$line" in ''|'#'*) continue ;; esac
        untracked=$(printf '%s\n' "$untracked" | grep -v "^${line%%\**}" || true)
    done < .sanitize-allow
fi
if [ -n "$untracked" ]; then
    hits="$(printf '%s\n%s' "${hits}" "${untracked}" | sed '/^$/d')"
fi

# git grep: 0 found, 1 nothing found, >1 real error. Without this a bad
# pathspec exits 128, the old '|| true' swallowed it, and the sweep reported
# clean while having searched nothing.
if [ "$status" -gt 1 ]; then
    echo "sanitize-check: git grep failed (exit $status) in $REPO_ROOT."
    echo "  Fix: run the git grep by hand to see the error. A stale pathspec in .sanitize-allow is the usual cause. Do not treat this as a pass."
    exit 2
fi

if [ -n "$hits" ]; then
    echo "$hits"
    echo ""
    echo "FAIL: personal or engagement data found (patterns: $PATTERNS)"
    echo "  Fix: genericize the path or value. If the file documents one specific machine or account on purpose, add its path to .sanitize-allow with a comment saying why."
    exit 1
fi

echo "Sanitize check passed: no personal data in tracked or untracked files."
exit 0
