#!/usr/bin/env python3
"""harness-tune.py: the no-model steps of `tack tune`.

Modeled on google-research/harness2 (propose, gate, compose, reflect), minus
the probe step: we mine real session transcripts instead of replaying tasks.
harness-tune.sh owns git, the model calls and the schedule. This file owns
everything that must be deterministic and testable without a model.

Subcommands:
  collect  CFG_DIR DAYS OUT_DIR          transcripts -> signals.jsonl, summary.json
  gate     PROPOSAL SIGNALS LEDGER OUT   drop uncited, single-session, off-limits edits
  apply    GATED WORKTREE OUT            apply replace/create edits, drop the ones that miss
  reflect  STATE_DIR SUMMARY PRS_JSON    merged/closed tune PRs -> ledger.jsonl
  report   RUN_DIR OUT_MD                render the report the PR body and message use
  notify   STATE_DIR ENV_FILE            send the latest report to Telegram

Privacy: snippets from transcripts stay in the local evidence dir. Nothing a
transcript said reaches the report except signal names, counts and citations.
"""
import json
import os
import re
import sys
import time
import urllib.request
from pathlib import Path

# Paths an unattended job may edit. No code (hooks, scripts, bin, lib) and no
# settings: base-settings.json owns plugins and marketplaces, and a bad hook
# reaches every machine through tack sync.
# Markdown only under these dirs: a skill can ship scripts, and check.sh runs
# tests that execute them, so a model-written .sh would run unattended.
ALLOWED_MD_DIRS = ("skills/", "agents/", "commands/", "output-styles/")
ALLOWED_FILES = ("templates/CLAUDE.md", "templates/AGENTS.md", "hooks/skill-routes.json")
ALLOWED_PREFIXES = ALLOWED_MD_DIRS + ALLOWED_FILES  # for messages
TRUSTED_COMMENTERS = ("OWNER", "MEMBER", "COLLABORATOR")
MIN_SESSIONS = 2   # harness2: a single-run defect is noise, a repeat is real
LEDGER_CAP = 50    # harness2 has no cap and no dedup; we keep the newest per cue
REFLECT_AFTER_DAYS = 7
ROUTE_RE = re.compile(r'Invoke the Skill tool with skill \\?"([\w:.-]+)')
CORRECTION_RE = re.compile(r"^\s*(no\b|nope|don'?t|do not|stop|wrong|that'?s not|not what|undo|revert)", re.I)
REJECT_PREFIX = "The user doesn't want to proceed"
# Telegram bot token, GitHub, Anthropic/OpenAI, AWS key shapes. An edit lands in a pushed PR.
TOKEN_RE = re.compile(r"\d{6,}:[A-Za-z0-9_-]{30,}|gh[pousr]_[A-Za-z0-9]{20,}|sk-[A-Za-z0-9_-]{20,}|AKIA[0-9A-Z]{16}"
                      r"|BEGIN [A-Z ]*PRIVATE KEY|xox[abpr]-[A-Za-z0-9-]{10,}")


def _text(content):
    if isinstance(content, str):
        return content
    if isinstance(content, list):
        return "\n".join(c.get("text", "") for c in content if isinstance(c, dict))
    return ""


# Detail tokens give the proposers something to point at without passing
# transcript text: each must match TOKEN_SAFE, or it is dropped.
TOKEN_SAFE = re.compile(r"^[A-Za-z0-9_.-]{1,40}$")
HOOK_RE = re.compile(r"([A-Za-z0-9_-]+\.(?:sh|py|js|cjs|mjs))")


def _token(t):
    return t if t and TOKEN_SAFE.match(t) else ""


def _detail(name, inp):
    """Bash: the program run. File tools: the file extension. Skill: its name."""
    inp = inp if isinstance(inp, dict) else {}
    if name == "Bash":
        for seg in re.split(r"&&|\|\||;|\|", str(inp.get("command", ""))):
            words = [w for w in seg.split() if not re.match(r"^[A-Za-z_][A-Za-z0-9_]*=", w)]
            if words and words[0] not in ("cd", "sudo", "time", "timeout", "env"):
                return _token(os.path.basename(words[0]))
        return ""
    if name in ("Read", "Edit", "Write", "MultiEdit", "NotebookEdit"):
        ext = os.path.splitext(str(inp.get("file_path", "")))[1]
        return _token(ext)
    if name == "Skill":
        return _token(str(inp.get("skill", "")))
    return ""


def _snip(s):
    return (s.strip().splitlines() or [""])[0][:160]


def collect(cfg_dir, days, out_dir):
    out = Path(out_dir)
    out.mkdir(parents=True, exist_ok=True)
    cutoff = time.time() - float(days) * 86400
    files = [p for p in Path(cfg_dir, "projects").glob("*/*.jsonl") if p.stat().st_mtime >= cutoff]
    rows = []
    for f in sorted(files):
        sid = f.stem
        tool_names, used, routed = {}, set(), {}
        prev_type = None
        with open(f, encoding="utf-8", errors="replace") as fh:
            for n, raw in enumerate(fh, 1):
                for m in ROUTE_RE.finditer(raw):
                    routed.setdefault(m.group(1), n)
                try:
                    rec = json.loads(raw)
                except ValueError:
                    continue
                if not isinstance(rec, dict):
                    continue
                typ = rec.get("type")
                content = (rec.get("message") or {}).get("content")
                if typ == "assistant" and isinstance(content, list):
                    for c in content:
                        if isinstance(c, dict) and c.get("type") == "tool_use":
                            tool_names[c.get("id")] = (c.get("name", "?"), _detail(c.get("name"), c.get("input")))
                            if c.get("name") == "Skill":
                                used.add(str((c.get("input") or {}).get("skill", "")))
                elif typ == "user" and isinstance(content, list):
                    for c in content:
                        if not (isinstance(c, dict) and c.get("type") == "tool_result" and c.get("is_error")):
                            continue
                        text = _text(c.get("content"))
                        name, detail = tool_names.get(c.get("tool_use_id"), ("?", ""))
                        if text.startswith(REJECT_PREFIX):
                            kind = "rejected"
                        elif re.search(r"hook", text[:300], re.I):
                            kind = "hook_block"
                            m = HOOK_RE.search(text[:300])
                            detail = _token(m.group(1)) if m else ""
                        else:
                            kind = "tool_error"
                        key = f"{name}:{detail}" if detail else name
                        rows.append({"session": sid, "line": n, "kind": kind, "key": key, "snippet": _snip(text)})
                elif typ == "user" and isinstance(content, str) and prev_type == "assistant":
                    if CORRECTION_RE.match(content):
                        rows.append({"session": sid, "line": n, "kind": "correction", "key": "-", "snippet": _snip(content)})
                elif typ == "system" and rec.get("subtype") == "compact_boundary":
                    rows.append({"session": sid, "line": n, "kind": "compaction", "key": "-", "snippet": ""})
                if typ in ("user", "assistant"):
                    prev_type = typ
        for skill, n in routed.items():
            if skill not in used:
                rows.append({"session": sid, "line": n, "kind": "route_ignored", "key": skill, "snippet": ""})

    with open(out / "signals.jsonl", "w", encoding="utf-8") as fh:
        for r in rows:
            fh.write(json.dumps(r) + "\n")
    agg = {}
    for r in rows:
        a = agg.setdefault(f"{r['kind']}:{r['key']}", {"count": 0, "sessions": set(), "cites": [], "snippets": []})
        a["count"] += 1
        a["sessions"].add(r["session"])
        if len(a["cites"]) < 5:
            a["cites"].append(f"{r['session']}:{r['line']}")
        if r["snippet"] and len(a["snippets"]) < 3:
            a["snippets"].append(r["snippet"])
    signals = sorted(
        ({"signal": k, "count": v["count"], "sessions": len(v["sessions"]), "cites": v["cites"], "snippets": v["snippets"]}
         for k, v in agg.items()),
        key=lambda s: (-s["sessions"], -s["count"], s["signal"]))
    summary = {"sessions_scanned": len(files), "days": float(days), "signals": signals}
    (out / "summary.json").write_text(json.dumps(summary, indent=1), encoding="utf-8")
    print(f"collect: {len(files)} sessions, {len(rows)} signal rows, {len(signals)} distinct signals")


def parse_model_json(text):
    """The model is asked for a fenced json block. Take the last one, else the whole text."""
    blocks = re.findall(r"```(?:json)?\s*\n(.*?)\n```", text, re.S)
    for cand in reversed(blocks or [text]):
        try:
            return json.loads(cand)
        except ValueError:
            continue
    raise ValueError("no parseable JSON in model output")


def load_ledger(path):
    rows = []
    if Path(path).is_file():
        for line in Path(path).read_text(encoding="utf-8").splitlines():
            try:
                rows.append(json.loads(line))
            except ValueError:
                pass
    return rows


def gate(proposal_path, signals_path, ledger_path, out_path):
    try:
        prop = parse_model_json(Path(proposal_path).read_text(encoding="utf-8"))
    except (OSError, ValueError) as e:
        prop = {"verdict": "KEEP_BASE", "edits": [], "notes": f"unparseable proposal: {e}"}
    known = {}  # "session:line" -> "kind:key"
    with open(signals_path, encoding="utf-8") as fh:
        for line in fh:
            r = json.loads(line)
            known[f"{r['session']}:{r['line']}"] = f"{r['kind']}:{r['key']}"
    refused = {str(r.get("cue", "")).strip().lower() for r in load_ledger(ledger_path)
               if r.get("verdict") in ("rejected", "hurt")}
    kept, dropped = [], []
    edits = prop.get("edits") if isinstance(prop, dict) and prop.get("verdict") != "KEEP_BASE" else []
    for e in edits or []:
        why = _reject_reason(e, known, refused)
        (dropped if why else kept).append({**e, "drop_reason": why} if why else e)
    notes = str(prop.get("notes", "")) if isinstance(prop, dict) else ""
    if TOKEN_RE.search(notes):
        notes = "(notes withheld: they contained a token-like string)"
    res = {"verdict": "EDITS" if kept else "KEEP_BASE", "edits": kept, "dropped": dropped, "notes": notes}
    Path(out_path).write_text(json.dumps(res, indent=1), encoding="utf-8")
    print(f"gate: kept {len(kept)}, dropped {len(dropped)}")


def _reject_reason(e, known, refused):
    if not isinstance(e, dict):
        return "not an object"
    if TOKEN_RE.search(json.dumps(e)):  # first: a later reason would echo the path into the report
        return "contains a token-like string"
    path = str(e.get("path", ""))
    if not path or path.startswith("/") or ".." in Path(path).parts:
        return "bad path"
    if not (path in ALLOWED_FILES or (path.startswith(ALLOWED_MD_DIRS) and path.endswith(".md"))):
        return f"path outside {', '.join(ALLOWED_PREFIXES)} (.md only under dirs)"
    if e.get("action") not in ("replace", "create"):
        return "action must be replace or create"
    if not str(e.get("cue", "")).strip():
        return "no cue"
    if not str(e.get("why", "")).strip():
        return "no why (the ledger needs it as the lesson)"
    if str(e.get("cue", "")).strip().lower() in refused:
        return "cue was rejected or hurt before (ledger)"
    cites = [c for c in (e.get("citations") or []) if isinstance(c, str)]
    if not cites:
        return "no citation"
    unknown = [c for c in cites if c not in known]
    if unknown:
        return f"citation not in evidence: {unknown[0]}"
    # Count sessions only over citations of this edit's own signal, or one
    # real row plus an unrelated row from another session would pass as two.
    own = [c for c in cites if known[c] == e.get("signal")]
    if not own:
        return "signal does not match any cited evidence row"
    if len({c.rsplit(':', 1)[0] for c in own}) < MIN_SESSIONS:
        return f"cited in fewer than {MIN_SESSIONS} sessions (noise)"
    return ""


def apply(gated_path, worktree, out_path):
    g = json.loads(Path(gated_path).read_text(encoding="utf-8"))
    applied, failed = [], []
    root = Path(worktree).resolve()
    for e in g.get("edits", []):
        target = (root / e["path"]).resolve()
        if root not in target.parents:
            failed.append({**e, "drop_reason": "escapes worktree"})
            continue
        if e["action"] == "create":
            if target.exists():
                failed.append({**e, "drop_reason": "create on an existing file"})
                continue
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_text(str(e.get("new", "")), encoding="utf-8")
        else:
            old = str(e.get("old", ""))
            text = target.read_text(encoding="utf-8") if target.is_file() else ""
            if not old or text.count(old) != 1:
                failed.append({**e, "drop_reason": "old text not found exactly once"})
                continue
            target.write_text(text.replace(old, str(e.get("new", "")), 1), encoding="utf-8")
        applied.append(e)
    g["edits"], g["dropped"] = applied, g.get("dropped", []) + failed
    g["verdict"] = "EDITS" if applied else "KEEP_BASE"
    Path(out_path).write_text(json.dumps(g, indent=1), encoding="utf-8")
    print(f"apply: applied {len(applied)}, failed {len(failed)}")


def _rate(summary, signal):
    n = max(int(summary.get("sessions_scanned", 0)), 1)
    hit = next((s for s in summary.get("signals", []) if s["signal"] == signal), None)
    return (hit["count"] if hit else 0) / n


def reflect(state_dir, summary_path, prs_path):
    """harness2's second recursion level. Your merge or close is the ground truth."""
    state = Path(state_dir)
    now_sum = json.loads(Path(summary_path).read_text(encoding="utf-8"))
    try:
        prs = {p["number"]: p for p in json.loads(Path(prs_path).read_text(encoding="utf-8"))}
    except (OSError, ValueError, KeyError, TypeError):
        prs = {}
    ledger = load_ledger(state / "ledger.jsonl")
    today = time.strftime("%Y-%m-%d")
    for final in sorted(state.glob("runs/*/final.json")):
        run = json.loads(final.read_text(encoding="utf-8"))
        pr = prs.get(run.get("pr"))
        if not pr or run.get("reflected"):
            continue
        rows = []
        if pr.get("state") == "CLOSED":
            # Only a comment from someone with write access is a reason; anyone can comment on a public repo.
            trusted = [c for c in (pr.get("comments") or []) if isinstance(c, dict)
                       and c.get("authorAssociation") in TRUSTED_COMMENTERS]
            note = (_snip(str(trusted[-1].get("body", ""))) if trusted else "") or "no comment"
            rows = [{"cue": e.get("cue"), "lesson": e.get("why"), "verdict": "rejected",
                     "evidence": f"PR #{pr['number']} closed: {note}"} for e in run.get("edits", [])]
        elif pr.get("state") == "MERGED":
            merged = time.mktime(time.strptime(str(pr.get("mergedAt", ""))[:10], "%Y-%m-%d")) if pr.get("mergedAt") else time.time()
            if time.time() - merged < REFLECT_AFTER_DAYS * 86400:
                continue
            before = json.loads(Path(final.parent, "summary.json").read_text(encoding="utf-8"))
            for e in run.get("edits", []):
                b, a = _rate(before, e.get("signal", "")), _rate(now_sum, e.get("signal", ""))
                if now_sum.get("sessions_scanned", 0) < 3 or (b == 0 and a == 0):
                    verdict = "confounded"
                elif a <= b * 0.5:
                    verdict = "helped"
                elif a >= b * 1.5 and a > 0:
                    verdict = "hurt"
                else:
                    verdict = "no_effect"
                rows.append({"cue": e.get("cue"), "lesson": e.get("why"), "verdict": verdict,
                             "evidence": f"PR #{pr['number']} {e.get('signal')}: {b:.2f} -> {a:.2f} per session"})
        else:
            continue
        # harness2 rule: no cue, lesson and evidence, no entry.
        ledger += [dict(r, date=today) for r in rows if all(str(r.get(k) or "").strip() for k in ("cue", "lesson", "evidence"))]
        run["reflected"] = today
        final.write_text(json.dumps(run, indent=1), encoding="utf-8")
    newest = {}
    for r in ledger:
        newest[str(r.get("cue", "")).strip().lower()] = r
    kept = sorted(newest.values(), key=lambda r: r.get("date", ""))[-LEDGER_CAP:]
    with open(state / "ledger.jsonl", "w", encoding="utf-8") as fh:
        for r in kept:
            fh.write(json.dumps(r) + "\n")
    print(f"reflect: ledger has {len(kept)} rows")


def report(run_dir, out_md):
    run = Path(run_dir)
    meta = json.loads((run / "meta.json").read_text(encoding="utf-8"))
    summary = json.loads((run / "summary.json").read_text(encoding="utf-8"))
    final = json.loads((run / "final.json").read_text(encoding="utf-8")) if (run / "final.json").is_file() else {}
    ledger = load_ledger(run.parent.parent / "ledger.jsonl")
    out = [f"# tack tune: {meta['profile']}, {meta['date']}", "",
           f"Sessions scanned: {summary['sessions_scanned']} (last {summary['days']:g} days).",
           f"Verdict: **{final.get('verdict', 'NONE')}**. Edits kept: {len(final.get('edits', []))}. "
           f"Dropped: {len(final.get('dropped', []))}. Check: {meta.get('check', 'not run')}.", ""]
    if final.get("notes"):
        out += [str(final["notes"]), ""]
    out += ["## Top signals", "", "| signal | count | sessions |", "|---|---|---|"]
    out += [f"| `{s['signal']}` | {s['count']} | {s['sessions']} |" for s in summary["signals"][:10]]
    out += ["", "## Edits", ""]
    for e in final.get("edits", []):
        out += [f"- `{e['path']}` ({e['action']}, {e.get('dimension', '?')}): {e.get('why', '')}",
                f"  cue: {e.get('cue')}; signal `{e.get('signal')}`; cites {', '.join(e.get('citations', []))}"]
    if not final.get("edits"):
        out += ["None. Keeping the current harness is a valid result."]
    if final.get("dropped"):
        out += ["", "## Dropped", ""]
        out += [f"- `{'(withheld)' if TOKEN_RE.search(json.dumps(e)) else e.get('path')}`: {e.get('drop_reason')}"
                for e in final["dropped"]]
    if ledger:
        out += ["", "## Ledger (what earlier edits did)", "", "| verdict | cue | evidence |", "|---|---|---|"]
        out += [f"| {r['verdict']} | {r['cue']} | {r['evidence']} |" for r in ledger[-10:]]
    Path(out_md).write_text("\n".join(out) + "\n", encoding="utf-8")


def _read_env(path):
    env = {}
    for line in Path(path).read_text(encoding="utf-8").splitlines():
        line = line.strip()
        if line and not line.startswith("#") and "=" in line:
            k, v = line.split("=", 1)
            env[k.strip()] = v.strip().strip('"').strip("'")
    return env


def notify(state_dir, env_file):
    latest = Path(state_dir, "latest.json")
    if not latest.is_file():
        print("notify: no run recorded yet. Fix: run `tack tune` first.")
        return
    meta = json.loads(latest.read_text(encoding="utf-8"))
    if not Path(env_file).is_file():
        print(f"notify: {env_file} not found, nothing sent.\n"
              "  Fix: in Telegram, message @BotFather, send /newbot, copy the token. Send your bot any message,\n"
              "  then open https://api.telegram.org/bot<TOKEN>/getUpdates and copy message.chat.id. Then:\n"
              f"  mkdir -p {Path(env_file).parent} && printf 'TELEGRAM_BOT_TOKEN=...\\nTELEGRAM_CHAT_ID=...\\n' > {env_file} && chmod 600 {env_file}")
        return
    if os.stat(env_file).st_mode & 0o077:
        print(f"notify: warning, {env_file} is readable by others. Fix: chmod 600 {env_file}")
    env = _read_env(env_file)
    lines = [f"tack tune, {meta.get('profile')}, {meta.get('date')}"]
    if meta.get("status") == "running":
        lines += [f"Run did not finish (crashed or the Mac went off). Log: {meta.get('run')}/run.log"]
    elif meta.get("status") != "ok":
        lines += [f"Run FAILED: {meta.get('error') or 'see run.log'}"]
    else:
        lines += [f"Verdict: {meta.get('verdict')}. Edits: {meta.get('edits', 0)}. Dropped: {meta.get('dropped', 0)}.",
                  f"Check: {meta.get('check')}."]
        lines += [f"- {s}" for s in meta.get("top", [])[:3]]
    if meta.get("pr_number"):
        lines += ["", "Next step, paste into claude:",
                  f'review PR #{meta["pr_number"]} in {meta.get("repo") or "the harness repo"}, then merge it or close it with a one-line reason']
    buttons = [b for b in ([{"text": "Review PR", "url": meta.get("pr_url")}] if meta.get("pr_url") else []) +
               ([{"text": "Open report", "url": meta.get("report_url")}] if meta.get("report_url") else [])]
    payload = {"chat_id": env.get("TELEGRAM_CHAT_ID", ""), "text": "\n".join(lines),
               "disable_web_page_preview": True}
    if buttons:
        payload["reply_markup"] = {"inline_keyboard": [buttons]}  # URL buttons need no listener
    dry = os.environ.get("TACK_TUNE_NOTIFY_DRYRUN_FILE")
    if dry:
        Path(dry).write_text(json.dumps(payload), encoding="utf-8")
        print(f"notify: dry run, payload written to {dry}")
        return
    if not env.get("TELEGRAM_BOT_TOKEN") or not payload["chat_id"]:
        print(f"notify: TELEGRAM_BOT_TOKEN or TELEGRAM_CHAT_ID missing in {env_file}. Fix: add both lines.")
        return
    req = urllib.request.Request(f"https://api.telegram.org/bot{env['TELEGRAM_BOT_TOKEN']}/sendMessage",
                                 data=json.dumps(payload).encode(), headers={"Content-Type": "application/json"})
    try:
        with urllib.request.urlopen(req, timeout=20) as r:
            print(f"notify: sent (HTTP {r.status})")
    except Exception as e:  # fail-open: a missed message must not fail the job
        print(f"notify: send failed: {type(e).__name__}. Fix: check the token and chat id in {env_file}.")


if __name__ == "__main__":
    cmds = {"collect": collect, "gate": gate, "apply": apply, "reflect": reflect, "report": report, "notify": notify}
    if len(sys.argv) < 2 or sys.argv[1] not in cmds:
        sys.exit(f"usage: harness-tune.py {{{','.join(cmds)}}} ARGS")
    cmds[sys.argv[1]](*sys.argv[2:])
