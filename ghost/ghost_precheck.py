#!/usr/bin/env python3
"""ghost PreToolUse hook: hard-block LLM-slop in prose file writes.

Reads hook JSON on stdin. Exit 2 + stderr blocks the tool call (Claude must
rewrite). Exit 0 allows. Fails OPEN on any error (never blocks a write because
the hook itself broke).
"""
import json
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
try:
    import ghost_scan as gs
except Exception:
    sys.exit(0)  # fail open


def _text_for_tool(tool, ti):
    if tool == "Write":
        return ti.get("content", "") or ""
    if tool == "Edit":
        return ti.get("new_string", "") or ""
    if tool == "MultiEdit":
        edits = ti.get("edits", []) or []
        return "\n".join((e or {}).get("new_string", "") or "" for e in edits)
    return None


def main():
    try:
        data = json.load(sys.stdin)
    except Exception:
        return 0
    tool = data.get("tool_name", "")
    ti = data.get("tool_input", {}) or {}
    path = ti.get("file_path", "")
    text = _text_for_tool(tool, ti)
    if text is None:
        return 0
    try:
        cfg = gs.load_patterns()
    except Exception:
        return 0
    if not gs.applies_to_file(path, cfg):
        return 0
    try:
        viols = gs.scan_text(text, cfg)
    except Exception:
        return 0
    block_cats = set(cfg.get("file_block_categories", []))
    blocking = [v for v in viols if v["category"] in block_cats]
    if not blocking:
        return 0
    msg = gs.format_violations(blocking, path)
    msg += (
        "\n\nBLOCKED by ghost. Rewrite to remove every item above before writing:\n"
        "  - em/en-dash (— –) -> comma, period, parentheses, or colon; restructure if needed\n"
        "  - cliche phrase -> plain direct wording, or delete\n"
        "  - buzzword -> simpler word, or cut\n"
        "Escape hatches if a term is genuinely required (FDA/domain):\n"
        "  - add the exact phrase to \"allowlist\" in "
        + (os.environ.get("CLAUDE_CONFIG_DIR") or os.path.expanduser("~/.claude"))
        + "/ghost/patterns.json, or\n"
        "  - append the token 'ghost:allow' on that line to keep it as-is."
    )
    msg += (
        "\n\nghost fired because this file's extension is in \"scan_extensions\", "
        "the list of client-facing document formats. Internal notes belong in .md, "
        "which ghost does not check."
    )
    print(msg, file=sys.stderr)
    return 2


if __name__ == "__main__":
    sys.exit(main())
