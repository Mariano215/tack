#!/usr/bin/env bash
# Covers the one rule that decides whether ghost costs you a rewrite:
# applies_to_file scans only client-facing document formats. If .md ever comes
# back into scan_extensions, every internal note can block a write again, which
# is the failure this test exists to catch.
set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

python3 - "$REPO_ROOT" <<'PY'
import os
import sys

repo = sys.argv[1]
sys.path.insert(0, os.path.join(repo, "ghost"))
import ghost_scan as gs

cfg = gs.load_patterns()
cases = [
    ("/work/clients/acme/report.txt", True, "txt is a deliverable format"),
    ("/work/clients/acme/report.docx", True, "docx is a deliverable format"),
    ("/work/clients/acme/report.pdf", True, "pdf is a deliverable format"),
    ("/work/notes.md", False, "markdown is internal, never scanned"),
    ("/work/README.md", False, "markdown is internal, never scanned"),
    ("/work/clients/acme/notes.md", False, "markdown stays internal even beside a deliverable"),
    ("/work/build.py", False, "not a prose extension"),
    ("/work/skills/x.txt", False, "skip_path_substrings still wins"),
    ("", False, "empty path"),
]

failed = 0
for path, want, why in cases:
    got = gs.applies_to_file(path, cfg)
    if got != want:
        print("test-ghost-scope: %s -> %s, wanted %s (%s)" % (path or "<empty>", got, want, why))
        failed = 1

if ".md" in [e.lower() for e in cfg.get("scan_extensions", [])]:
    print("test-ghost-scope: .md is back in scan_extensions; internal docs will block writes again")
    failed = 1

sys.exit(failed)
PY
rc=$?
[ "$rc" -eq 0 ] && echo "test-ghost-scope: ok"
exit "$rc"
