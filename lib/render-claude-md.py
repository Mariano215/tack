#!/usr/bin/env python3
# render-claude-md.py <template> <live CLAUDE.md>
# Writes the template between the harness markers in the live file. Text outside
# the markers is the user's and is kept. Backs up the old file as .harness-prev.
import os, shutil, sys
tpl, live = sys.argv[1], sys.argv[2]
B, E = "<!-- harness:begin", "<!-- harness:end -->"
block = (B + " managed by tack from templates/CLAUDE.md, edit it there -->\n"
         + open(tpl, encoding="utf-8", newline="").read().strip("\n") + "\n" + E + "\n")
old = open(live, encoding="utf-8", newline="").read() if os.path.exists(live) else ""
if B in old and E in old[old.index(B):]:
    i = old.index(B); j = old.index(E, i) + len(E)
    rest = old[j:].lstrip("\n")
    new = old[:i] + block + ("\n" + rest if rest.strip() else "")
    msg = "  CLAUDE.md engine block refreshed"
else:
    new = block + ("\n" + old if old.strip() else "")
    msg = "  CLAUDE.md engine block added above your existing text"
if new == old:
    sys.exit(0)
if old:
    shutil.copyfile(live, live + ".harness-prev")
with open(live, "w", encoding="utf-8", newline="") as f:
    f.write(new)
print(msg)
if old and not (B in old):
    print("    Remove sections below the block that repeat it. Undo: cp " + live + ".harness-prev " + live)
