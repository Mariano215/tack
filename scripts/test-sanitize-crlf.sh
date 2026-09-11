#!/usr/bin/env bash
# A .sanitize-patterns checked out with CRLF (core.autocrlf on Windows) once
# ended every pattern in an invisible CR, so the sweep matched nothing and
# reported clean on the one machine that ran it before a push.
set -uo pipefail
CORE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="$(mktemp -d 2>/dev/null || mktemp -d -t sanitizecrlf)"
trap 'rm -rf "$TMP"' EXIT
cd "$TMP" && git init -q .
printf 'acmecorp\r\nsecondname\r\n' > .sanitize-patterns
echo 'a note about AcmeCorp' > notes.txt
git add -A 2>/dev/null
if bash "$CORE/scripts/sanitize-check.sh" >/dev/null 2>&1; then
  echo "  FAIL: a CRLF .sanitize-patterns matched nothing"
  exit 1
fi
echo "sanitize CRLF test passed"
