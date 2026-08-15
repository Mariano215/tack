#!/usr/bin/env python3
"""Idempotently register ghost and auditor hooks in the active settings.json.

Adds:
  PreToolUse  Write|Edit|MultiEdit -> ghost_precheck.py      (hard-block prose slop)
  PostToolUse Write|Edit           -> citation-validator.py  (citation mode logging)

It also prunes the retired Stop ghost_stopcheck hook from machines that still
carry it. Safe to re-run. Backs up settings.json first.
"""
import json
import os
import shutil

# Honor CLAUDE_CONFIG_DIR so this writes to the config dir the caller is
# actually running under. The commands themselves expand it at hook time, since
# a hook command is run through sh and inherits the variable.
CFG = os.environ.get("CLAUDE_CONFIG_DIR") or os.path.expanduser("~/.claude")
SETTINGS = os.path.join(CFG, "settings.json")
_C = '"${CLAUDE_CONFIG_DIR:-$HOME/.claude}"'
PRECHECK_CMD = "python3 %s/ghost/ghost_precheck.py" % _C
CITATION_CMD = "python3 %s/auditor/hooks/citation-validator.py" % _C


def has_cmd(entries, needle):
    for entry in entries or []:
        for h in entry.get("hooks", []) or []:
            if needle in (h.get("command", "") or ""):
                return True
    return False


def drop_cmd(entries, needle):
    """Remove hook entries whose command mentions `needle`. Returns True if the
    list changed. Used to retire ghost_stopcheck, which warned on every chat
    reply and made the model rewrite prose that was never client-facing."""
    keep = []
    for entry in entries or []:
        hooks = [h for h in (entry.get("hooks", []) or [])
                 if needle not in (h.get("command", "") or "")]
        if not hooks:
            continue
        entry["hooks"] = hooks
        keep.append(entry)
    if len(keep) == len(entries or []):
        return False
    entries[:] = keep
    return True


def main():
    with open(SETTINGS, "r", encoding="utf-8") as f:
        cfg = json.load(f)
    shutil.copy2(SETTINGS, SETTINGS + ".ghost-bak")

    hooks = cfg.setdefault("hooks", {})
    pre = hooks.setdefault("PreToolUse", [])
    post = hooks.setdefault("PostToolUse", [])
    stop = hooks.setdefault("Stop", [])

    changed = []
    if not has_cmd(pre, "ghost_precheck"):
        pre.append({
            "matcher": "Write|Edit|MultiEdit",
            "hooks": [{"type": "command", "command": PRECHECK_CMD, "timeout": 10,
                       "statusMessage": "ghost slop check..."}],
        })
        changed.append("PreToolUse:ghost_precheck")
    if not has_cmd(post, "citation-validator"):
        post.append({
            "matcher": "Write|Edit",
            "hooks": [{"type": "command", "command": CITATION_CMD, "timeout": 10,
                       "statusMessage": "Citation verification..."}],
        })
        changed.append("PostToolUse:citation-validator")
    if drop_cmd(stop, "ghost_stopcheck"):
        changed.append("Stop:ghost_stopcheck removed")

    if changed:
        with open(SETTINGS, "w", encoding="utf-8") as f:
            json.dump(cfg, f, indent=2)
            f.write("\n")
        print("hooks added:", ", ".join(changed))
    else:
        print("all hooks already present; no change.")


if __name__ == "__main__":
    main()
