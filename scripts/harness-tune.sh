#!/usr/bin/env bash
# harness-tune.sh: the weekly self-tuning job behind `tack tune`.
#
# Modeled on google-research/harness2 (propose, gate, compose, reflect). It
# mines the last week of session transcripts, has two proposers (INV: how the
# agent works, DOM: what it knows) draft cited edits, drops the uncited ones,
# composes the rest, and opens a DRAFT PR on core. Nothing reaches main, and so
# nothing reaches another machine through tack sync, until a human merges it.
# Merged and closed tune PRs feed the next run through the ledger.
#
# Usage (normally through tack):
#   harness-tune.sh [--profile P] [--days N]   run once
#   harness-tune.sh --notify                    send the latest report to Telegram
#   harness-tune.sh --install-schedule          Sunday 02:00 run, 08:00 notify (macOS launchd)
#   harness-tune.sh --uninstall-schedule
#
# Env: TACK_TUNE_REPO (core checkout), TACK_TUNE_STATE, TACK_TUNE_CLAUDE (claude binary),
#      TACK_TUNE_ENV_FILE (Telegram secrets, default ~/.config/tack/tune.env),
#      TACK_TUNE_CHECK and TACK_TUNE_STAMP (test seams).
set -uo pipefail

CFG="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
STATE="${TACK_TUNE_STATE:-$CFG/harness-tune}"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="${TACK_TUNE_REPO:-$(cd "$HERE/.." && pwd)}"
PY="$HERE/harness-tune.py"
PROMPTS="$REPO/templates/tune"
CLAUDE_BIN="${TACK_TUNE_CLAUDE:-claude}"
ENV_FILE="${TACK_TUNE_ENV_FILE:-$HOME/.config/tack/tune.env}"
AGENTS_DIR="$HOME/Library/LaunchAgents"

profile="" days=7 mode=run
while [ $# -gt 0 ]; do
  case "$1" in
    --profile) profile="${2:-}"; shift ;;
    --days) days="${2:-7}"; shift ;;
    --notify) mode=notify ;;
    --install-schedule) mode=install ;;
    --uninstall-schedule) mode=uninstall ;;
    *) echo "harness-tune: unknown option '$1'. Fix: see the usage at the top of $0" >&2; exit 2 ;;
  esac
  shift
done
mkdir -p "$STATE"

if [ "$mode" = notify ]; then
  python3 "$PY" notify "$STATE" "$ENV_FILE"
  exit 0  # fail-open: a missed message must not look like a failed job
fi

plist() {  # label, then the tack arguments; hour comes from the label
  local label="$1"; shift
  local hour=2; [ "$label" = com.tack.tune.notify ] && hour=8
  local args="" a
  for a in "$@"; do args="$args<string>$a</string>"; done
  cat <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>Label</key><string>$label</string>
<key>ProgramArguments</key><array>$args</array>
<key>EnvironmentVariables</key><dict><key>PATH</key><string>$PATH</string><key>HOME</key><string>$HOME</string></dict>
<key>StartCalendarInterval</key><dict><key>Weekday</key><integer>0</integer><key>Hour</key><integer>$hour</integer><key>Minute</key><integer>0</integer></dict>
<key>StandardOutPath</key><string>$STATE/$label.log</string>
<key>StandardErrorPath</key><string>$STATE/$label.log</string>
</dict></plist>
EOF
}

if [ "$mode" = install ] || [ "$mode" = uninstall ]; then
  [ "$(uname)" = Darwin ] || { echo "harness-tune: the schedule uses launchd (macOS). Fix: on Linux add a crontab line: 0 2 * * 0 tack tune; 0 8 * * 0 tack tune --notify"; exit 2; }
  for label in com.tack.tune.run com.tack.tune.notify; do
    launchctl bootout "gui/$(id -u)/$label" 2>/dev/null
    rm -f "$AGENTS_DIR/$label.plist"
  done
  if [ "$mode" = uninstall ]; then echo "harness-tune: schedule removed."; exit 0; fi
  hx_bin="$(command -v tack)" || { echo "harness-tune: tack is not on PATH. Fix: run setup-core.sh, then retry."; exit 2; }
  mkdir -p "$AGENTS_DIR"
  plist com.tack.tune.run "$hx_bin" tune ${profile:+--profile "$profile"} > "$AGENTS_DIR/com.tack.tune.run.plist"
  plist com.tack.tune.notify "$hx_bin" tune --notify ${profile:+--profile "$profile"} > "$AGENTS_DIR/com.tack.tune.notify.plist"
  for label in com.tack.tune.run com.tack.tune.notify; do
    launchctl bootstrap "gui/$(id -u)" "$AGENTS_DIR/$label.plist" || { echo "harness-tune: launchctl bootstrap failed for $label. Fix: check the plist with plutil -lint $AGENTS_DIR/$label.plist"; exit 1; }
  done
  echo "harness-tune: scheduled. Run Sunday 02:00, notify Sunday 08:00 (a sleeping Mac runs on wake)."
  echo "  Undo: tack tune --uninstall-schedule"
  [ -f "$ENV_FILE" ] || python3 "$PY" notify "$STATE" "$ENV_FILE" | sed -n '/Fix/,$p'
  exit 0
fi

# ---- run ----
[ -n "$profile" ] || profile="$(tr -d '\r\n' < "$CFG/.harness-active" 2>/dev/null)"
[ -n "$profile" ] || profile=none
date="$(date +%Y-%m-%d)"
stamp="${TACK_TUNE_STAMP:-$(date +%Y-%m-%d-%H%M)}"  # a rerun the same day gets its own run dir and branch
RUN="$STATE/runs/$stamp-$profile"
# The worktree lives outside HOME and /Volumes, so the proposers can be denied
# both whole trees (where transcripts, secrets and client files live).
WT="$(cd -P "$(mktemp -d "${TMPDIR:-/var/tmp}/tack-tune.XXXXXX")" && pwd)/wt"
branch="tune/$profile-$stamp"
mkdir -p "$RUN"
LOG="$RUN/run.log"

latest() {  # status [error]: the record --notify reads
  jq -n --arg s "$1" --arg e "${2:-}" --arg p "$profile" --arg d "$date" --arg run "$RUN" \
     --arg pr "${pr_number:-}" --arg url "${pr_url:-}" --arg rep "${report_url:-}" --arg nwo "${nwo:-}" --arg chk "${check:-not run}" \
     --slurpfile f <(cat "$RUN/final.json" 2>/dev/null || echo '{}') \
     --slurpfile sm <(cat "$RUN/summary.json" 2>/dev/null || echo '{"signals":[]}') \
     '{status:$s, error:$e, profile:$p, date:$d, run:$run, check:$chk,
       verdict:($f[0].verdict // "NONE"), edits:(($f[0].edits // [])|length), dropped:(($f[0].dropped // [])|length),
       top:[$sm[0].signals[:3][] | "\(.signal): \(.count) in \(.sessions) sessions"],
       pr_number:$pr, pr_url:$url, report_url:$rep, repo:$nwo}' > "$STATE/latest.json"
}
fail() {  # the message quotes the last log line, so the 08:00 report says what broke
  local last; last="$(grep -v '^[[:space:]]*$' "$LOG" 2>/dev/null | tail -1 | cut -c1-200)"
  echo "harness-tune: $1" | tee -a "$LOG" >&2; latest failed "$1${last:+: $last}"; exit 1; }
cleanup() { [ -d "$WT" ] && git -C "$REPO" worktree remove --force "$WT" >/dev/null 2>&1; rmdir "${WT%/wt}" 2>/dev/null; }
trap cleanup EXIT
jq -n --arg p "$profile" --arg d "$date" '{profile:$p, date:$d, check:"not run"}' > "$RUN/meta.json"
latest running  # replaced at every exit; left as is, notify reports an unfinished run

# 1. Collect, then reflect on earlier tune PRs (your merge or close is the signal).
python3 "$PY" collect "$CFG" "$days" "$RUN/evidence" >> "$LOG" 2>&1 || fail "collect failed, see $LOG"
cp "$RUN/evidence/summary.json" "$RUN/summary.json"
(cd "$REPO" && gh pr list --label tack-tune --state all --limit 50 --json number,state,mergedAt,comments) > "$RUN/prs.json" 2>>"$LOG" || echo '[]' > "$RUN/prs.json"
python3 "$PY" reflect "$STATE" "$RUN/summary.json" "$RUN/prs.json" >> "$LOG" 2>&1 || fail "reflect failed, see $LOG"

keep_base() {
  jq -n --arg n "$1" '{verdict:"KEEP_BASE", edits:[], dropped:[], notes:$n}' > "$RUN/final.json"
  python3 "$PY" report "$RUN" "$RUN/report.md"
  latest ok; echo "harness-tune: KEEP_BASE ($1). Report: $RUN/report.md"; exit 0
}
sessions="$(jq -r '.sessions_scanned' "$RUN/summary.json" | tr -d '\r')"
[ "${sessions:-0}" -gt 0 ] || keep_base "no sessions in the last $days days"

# 2. A worktree off origin/main, so the job never touches your checkout.
git -C "$REPO" fetch -q origin main >> "$LOG" 2>&1 || fail "git fetch origin main failed, see $LOG"
git -C "$REPO" worktree add -q -B "$branch" "$WT" origin/main >> "$LOG" 2>&1 || fail "git worktree add failed, see $LOG"
CLAUDE_CONFIG_DIR="$CFG" bash "$REPO/scripts/context-cost.sh" > "$RUN/context-cost.txt" 2>&1 || true

ask() {  # role file, output file; extra stdin sections appended by the caller
  { cat "$PROMPTS/propose.md" "$PROMPTS/$1"
    echo; echo "<harness profile=\"$profile\">"; cat "$HARNESS_MANIFEST" 2>/dev/null; echo "</harness>"
    echo "<context-cost>"; cat "$RUN/context-cost.txt"; echo "</context-cost>"
    # No snippets: transcript text is untrusted and could steer the model into the PR.
    echo "<evidence>"; jq 'del(.signals[].snippets)' "$RUN/summary.json"; echo "</evidence>"
    echo "<ledger>"; cat "$STATE/ledger.jsonl" 2>/dev/null; echo "</ledger>"
    cat
  } > "$RUN/$2.prompt"
  # Path rules use Read(...) only: the CLI applies Read rules to every file-reading
  # tool (Grep, Glob) and ignores Grep(...)/Glob(...) path rules with a warning.
  # An allow rule does not confine reads (tested: ~/.zshrc stayed readable), so
  # deny whole trees instead. Deny wins over allow; the worktree is outside them.
  # shortcut: permission rules, not an OS sandbox.
  local allow="Read(/$WT/**)" deny
  deny="Read(/$HOME/**),Read(//Volumes/**),Read(//private/tmp/**),Read(//tmp/**),Read(**/.env),Read(**/.env.*)"
  # env -u: a stale ANTHROPIC_API_KEY in the shell beats the claude.ai login in -p
  # and fails with "Invalid API key". The job runs on the login, like the schedule.
  (cd "$WT" && env -u ANTHROPIC_API_KEY "$CLAUDE_BIN" -p --tools Read,Grep,Glob --allowedTools "$allow" \
      --disallowedTools "$deny" --no-session-persistence --output-format text < "$RUN/$2.prompt") > "$RUN/$2.out" 2>>"$LOG"
}
HARNESS_MANIFEST="$WT/profiles/$profile/manifest.json"

# 3. Propose (INV and DOM in parallel), then gate each.
ask inv.md inv < /dev/null & p1=$!
ask dom.md dom < /dev/null & p2=$!
wait $p1 || fail "INV proposer failed: $(head -c 200 "$RUN/inv.out")"
wait $p2 || fail "DOM proposer failed: $(head -c 200 "$RUN/dom.out")"
for d in inv dom; do
  python3 "$PY" gate "$RUN/$d.out" "$RUN/evidence/signals.jsonl" "$STATE/ledger.jsonl" "$RUN/$d.gated.json" >> "$LOG" 2>&1 \
    || fail "gate failed on $d, see $LOG"
done
n="$(jq -s '[.[].edits[]]|length' "$RUN/inv.gated.json" "$RUN/dom.gated.json" | tr -d '\r')"
[ "$n" -gt 0 ] || keep_base "both proposers returned no edit that passed the gate"

# 4. Compose, gate again (the composer must not invent citations), apply.
{ echo "<proposals>"; jq -s '{inv:.[0], dom:.[1]}' "$RUN/inv.gated.json" "$RUN/dom.gated.json"; echo "</proposals>"; } \
  | ask compose.md compose || fail "composer failed: $(head -c 200 "$RUN/compose.out")"
python3 "$PY" gate "$RUN/compose.out" "$RUN/evidence/signals.jsonl" "$STATE/ledger.jsonl" "$RUN/compose.gated.json" >> "$LOG" 2>&1 \
  || fail "gate failed on compose, see $LOG"
python3 "$PY" apply "$RUN/compose.gated.json" "$WT" "$RUN/final.json" >> "$LOG" 2>&1 || fail "apply failed, see $LOG"
[ "$(jq -r '.verdict' "$RUN/final.json" | tr -d '\r')" = EDITS ] || keep_base "no composed edit applied cleanly"

# 5. Report into the tree, then the full gate (it includes the sanitize sweep).
rel="tune/reports/$stamp-$profile.md"
mkdir -p "$WT/tune/reports"
python3 "$PY" report "$RUN" "$WT/$rel"
# TACK_TUNE_CHECK exists for the test: check.sh runs that test, so it cannot run check.sh.
if (cd "$WT" && ${TACK_TUNE_CHECK:-bash scripts/check.sh}) > "$RUN/check.log" 2>&1; then check=pass; else check=fail; fi
jq --arg c "$check" '.check=$c' "$RUN/meta.json" > "$RUN/meta.tmp" && mv "$RUN/meta.tmp" "$RUN/meta.json"
python3 "$PY" report "$RUN" "$WT/$rel"
cp "$WT/$rel" "$RUN/report.md"
if [ "$check" = fail ]; then
  latest ok; git -C "$REPO" worktree remove --force "$WT"; git -C "$REPO" branch -D "$branch" >/dev/null 2>&1
  echo "harness-tune: edits failed scripts/check.sh, no PR. See $RUN/check.log"; exit 0
fi

# 6. Commit, push the branch (never main), open a draft PR.
git -C "$WT" add -A && git -C "$WT" commit -q -m "chore(tune): $profile $date, $(jq '.edits|length' "$RUN/final.json") cited edits" >> "$LOG" 2>&1 \
  || fail "commit failed, see $LOG"
git -C "$WT" push -q -u origin "$branch" >> "$LOG" 2>&1 || fail "push of $branch failed, see $LOG"
(cd "$WT" && gh label create tack-tune --color BFD4F2 --description "weekly tack tune proposals" --force) >> "$LOG" 2>&1
pr_url="$(cd "$WT" && gh pr create --draft --label tack-tune --base main --head "$branch" \
  --title "tack tune: $profile $date" --body-file "$RUN/report.md" 2>>"$LOG" | tail -1 | tr -d '\r')"
case "$pr_url" in https://*) ;; *) fail "gh pr create failed, see $LOG" ;; esac
pr_number="${pr_url##*/}"
nwo="$(cd "$WT" && gh repo view --json nameWithOwner -q .nameWithOwner 2>>"$LOG" | tr -d '\r')"
report_url="https://github.com/$nwo/blob/$branch/$rel"
jq --argjson n "$pr_number" '.pr=$n' "$RUN/final.json" > "$RUN/final.tmp" && mv "$RUN/final.tmp" "$RUN/final.json"
latest ok
echo "harness-tune: draft PR $pr_url"
