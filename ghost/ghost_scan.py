#!/usr/bin/env python3
"""ghost: detect LLM-cliche / slop patterns in prose. Python stdlib only.

Used by:
  - ghost_precheck.py  (PreToolUse hook, hard-block on deliverable writes)
  - /ghost command     (manual scan + rewrite, any file)

The hook only fires on the extensions in scan_extensions, which are the
client-facing document formats. Markdown is not one of them. The CLI below
scans whatever you hand it, extension included.

CLI:
  python3 ghost_scan.py <file>     # scan a file, exit 1 if violations
  echo "text" | python3 ghost_scan.py -   # scan stdin
"""
import json
import os
import re
import sys

GHOST_DIR = os.path.dirname(os.path.abspath(__file__))
PATTERNS_PATH = os.path.join(GHOST_DIR, "patterns.json")


def load_patterns(path=PATTERNS_PATH):
    with open(path, "r", encoding="utf-8") as f:
        return json.load(f)


def _compile(cfg):
    phrases = []
    for p in cfg.get("phrases", []):
        try:
            phrases.append((p, re.compile(p, re.IGNORECASE)))
        except re.error:
            continue
    buzz = []
    for w in cfg.get("buzzwords", []):
        buzz.append((w, re.compile(r"\b" + re.escape(w) + r"\b", re.IGNORECASE)))
    dashes = cfg.get("dashes", [])
    return phrases, buzz, dashes


def _mask_allowlist(line, allow_res):
    """Blank out allowlisted spans (equal-length spaces) so their inner words
    do not trigger. Column positions stay aligned with the original line."""
    masked = line
    for rx in allow_res:
        masked = rx.sub(lambda m: " " * len(m.group(0)), masked)
    return masked


def scan_text(text, cfg=None):
    """Return list of violations: {line, col, match, category}."""
    if cfg is None:
        cfg = load_patterns()
    phrases, buzz, dashes = _compile(cfg)
    allow_res = [
        re.compile(re.escape(a), re.IGNORECASE)
        for a in cfg.get("allowlist", [])
        if a and a.strip()
    ]
    bypass = cfg.get("bypass_token", "")
    out = []
    for i, line in enumerate(text.splitlines(), 1):
        if bypass and bypass in line:
            continue
        for d in dashes:
            start = 0
            while True:
                j = line.find(d, start)
                if j < 0:
                    break
                out.append({"line": i, "col": j + 1, "match": d, "category": "dashes"})
                start = j + 1
        masked = _mask_allowlist(line, allow_res)
        for _pat, rx in phrases:
            for m in rx.finditer(masked):
                frag = m.group(0).strip() or m.group(0)
                out.append({"line": i, "col": m.start() + 1, "match": frag, "category": "phrases"})
        for _word, rx in buzz:
            for m in rx.finditer(masked):
                out.append({"line": i, "col": m.start() + 1, "match": m.group(0), "category": "buzzwords"})
    return out


def applies_to_file(path, cfg):
    """True if this file path should be auto-scanned.

    The gate is the extension, and `scan_extensions` lists only the formats a
    document leaves in: .txt, .docx, .pdf. Markdown is deliberately absent.
    Nearly every .md on this machine is internal (notes, READMEs, plans, skill
    files), and a block costs a full rewrite of the file, so scanning them
    burned tokens on prose no client ever read.
    """
    if not path:
        return False
    p = path.lower()
    for s in cfg.get("skip_path_substrings", []):
        if s and s.lower() in p:
            return False
    exts = [e.lower() for e in cfg.get("scan_extensions", [])]
    return any(p.endswith(e) for e in exts)


def format_violations(viols, path=None):
    if not viols:
        return ""
    head = "ghost: LLM-cliche / slop detected"
    if path:
        head += f" in {path}"
    lines = [head]
    for v in viols:
        lines.append(f"  line {v['line']}:{v['col']}  [{v['category']}]  \"{v['match']}\"")
    return "\n".join(lines)


def _main():
    args = sys.argv[1:]
    cfg = load_patterns()
    if not args or args[0] == "-":
        text = sys.stdin.read()
        path = None
    else:
        path = args[0]
        try:
            with open(path, "r", encoding="utf-8") as f:
                text = f.read()
        except OSError as e:
            print(f"ghost: cannot read {path}: {e}", file=sys.stderr)
            return 2
    viols = scan_text(text, cfg)
    if viols:
        print(format_violations(viols, path))
        return 1
    print("ghost: clean" + (f" - {path}" if path else ""))
    return 0


if __name__ == "__main__":
    sys.exit(_main())
