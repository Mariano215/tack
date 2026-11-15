#!/usr/bin/env bash
# bash-guard.sh (PreToolUse, matcher Bash)
# Deny: commands that touch secret files. Read() deny rules stop the Read tool
# only, so `cat ~/.aws/credentials` went straight through Bash. A hook deny
# holds in every permission mode, bypass included.
# Ask: commands that publish under the user's account (push, merge, release).
# A speed bump against accidental and casual secret reads, not a sandbox:
# quoting or encoding can get past it.
# FAIL-OPEN: any parse problem or missing jq exits 0 with no output.
set -uo pipefail
command -v jq >/dev/null 2>&1 || exit 0
input=$(cat 2>/dev/null) || exit 0
cmd=$(printf '%s' "$input" | jq -r '.tool_input.command // empty' 2>/dev/null | tr -d '\r') || exit 0
[ -n "$cmd" ] || exit 0

# macOS paths are case-insensitive, so everything is matched on a lowercased copy.
# .env and any .env.<suffix> are secrets; .env.example, .env.sample and
# .env.template (exactly) and .envrc are not. Those are stripped before matching.
ENV_OK='\.env\.(example|sample|template)($|[^a-z0-9_.-])'
SECRET='(\.aws/|\.ssh/|(^|[^a-z0-9_.-])\.env($|[^a-z0-9_-])|\.pem($|[^a-z0-9])|id_rsa|id_ed25519|\.credentials\.json|\.claude\.json|\.claude-mem/settings\.json|\.fal-key|\.config/gh/hosts\.yml|security[[:space:]]+(find|dump)-(generic|internet)-password|security[[:space:]]+dump-keychain)'
PUBLISH='(^|[^a-z0-9_.-])(gh[[:space:]]+pr[[:space:]]+merge|gh[[:space:]]+release[[:space:]]+(create|edit|delete|upload)|gh[[:space:]]+repo[[:space:]]+create[[:space:]].*--push|tack[[:space:]]+sync[[:space:]]+--push)([[:space:];&|()<>`'"'"'"]|$)'
# push or send-pack as a whole token (ends at space, end, or ;&|()<> or backtick) anywhere after a git token, or any git alias definition (-c alias.x=..., GIT_CONFIG_KEY_n).
GITPUSH='(^|[^a-z0-9_.-])git([[:space:]].*)?[[:space:]'"'"'"](push|send-pack)([[:space:];&|()<>`'"'"'"]|$)'
GITALIAS='(^|[^a-z0-9_.-])git[[:space:]].*alias\.|git_config_key_|git_config_parameters'
# gh api writes: a non-GET method, or any field/input flag (those make it a POST).
GHAPI='(^|[^a-z0-9_.-])gh[[:space:]]+api.*([[:space:]](-x|--method)[[:space:]=]*(post|put|patch|delete)|[[:space:]](-f|--field|--raw-field|--input))'
# Secret-dir mentions combined with a form the regexes cannot read reliably.
SPFX='(\.aws|\.ssh|\.config/gh|\.claude-mem|\.claude-profiles|\.fal-key|credentials|\.claude\.j|\.cred|\.en|id_rsa|id_ed|\.pem|hosts\.yml)'
OBF="${SPFX}.*(eval|base64|\`|\\\$\()|(eval|base64|\`|\\\$\().*${SPFX}|[^[:space:]]*${SPFX}[^[:space:]]*[*?[]|[*?[][^[:space:]]*${SPFX}"

decide() {
  jq -cn --arg d "$1" --arg r "$2" \
    '{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:$d,permissionDecisionReason:$r}}'
}

# Heredoc bodies written as text (a log entry, a commit message) made the guard
# ask or deny on a body that only mentions "git push" or ".env". A body is
# dropped only when all of these hold, otherwise the whole command is checked:
#   - the line is a plain write: git commit or git tag, or cat or tee into a
#     .md, .txt or .log file outside .git/ (a path prefix on the command is
#     allowed), and nothing is piped onward (no "|" after <<);
#   - the delimiter is a quoted bare word ('EOF' or "EOF"), so nothing expands;
#   - the exact terminator line is found before the input ends.
#   - nothing outside the body can run it: no $(, backtick, <(, eval, line
#     continuation, or shell or interpreter word anywhere else in the command
#     (that catches eval "$( on the line before, "\ | sh" and "bash written.sh").
# Everything else (bash <<, python - <<, cat <<EOF | sh, odd quoting) keeps its
# body, so this can only remove false asks, never hide a command that runs.
orig_cmd="$cmd"
cmd=$(printf '%s\n' "$cmd" | awk '
  BEGIN { inhd = 0; out = ""; orig = "" }
  { orig = orig $0 "\n" }
  inhd {
    t = $0; if (strip_tabs) sub(/^\t+/, "", t)
    if (t == delim) inhd = 0
    next
  }
  {
    out = out $0 "\n"
    i = index($0, "<<")
    if (i == 0 || substr($0, i + 2, 1) == "<" || (i > 1 && substr($0, i - 1, 1) == "<")) next
    # The segment that holds <<: text after the last ; && or || before it.
    head = substr($0, 1, i - 1); sub(/.*(;|&&|\|\|)/, "", head); sub(/^[ \t]*/, "", head)
    if (index(head, "|") > 0) next
    rest = substr($0, i + 2)
    if (head ~ /^([^ \t;&|]*\/)?git[ \t]+(commit|tag)([ \t]|$)/) {
      ok = 1
    } else if (head ~ /^([^ \t;&|]*\/)?(cat|tee)([ \t]|$)/) {
      # cat or tee only when the target is a notes file: .md, .txt or .log,
      # never under .git/ (hooks run from there) and never a shell rc file.
      w = head " " rest; ok = 0
      if (match(w, />>?[ \t]*[^ \t;&|<>]+/)) { tgt = substr(w, RSTART, RLENGTH); sub(/^>>?[ \t]*/, "", tgt) }
      else if (match(head, /tee([ \t]+-[a-z]+)*[ \t]+[^ \t;&|<>]+/)) { tgt = substr(head, RSTART, RLENGTH); sub(/.*[ \t]/, "", tgt) }
      else tgt = ""
      gsub(/["\047]/, "", tgt)
      if (tgt ~ /\.(md|markdown|txt|log)$/ && tgt !~ /(^|\/)\.git\// && tgt !~ /(^|\/)\.[a-z]*(rc|profile)$/) ok = 1
    } else ok = 0
    if (!ok) next
    if (index(rest, "|") > 0) next
    strip_tabs = (substr(rest, 1, 1) == "-"); if (strip_tabs) rest = substr(rest, 2)
    sub(/^[ \t]*/, "", rest)
    # Only a quoted delimiter makes the body literal text. An unquoted body
    # expands $(...), backticks and backslash continuations, so it stays checked.
    q = substr(rest, 1, 1)
    if (q != "\"" && q != "\047") next
    rest = substr(rest, 2)
    if (!match(rest, /^[A-Za-z_][A-Za-z0-9_]*/)) next
    d = substr(rest, RSTART, RLENGTH)
    if (substr(rest, RLENGTH + 1, 1) != q) next
    after = substr(rest, RLENGTH + 2, 1)
    if (after != "" && after !~ /[ \t;&>)]/) next
    delim = d; inhd = 1
  }
  END { if (inhd) printf "%s", orig; else printf "%s", out }') || exit 0
if [ "$cmd" != "$orig_cmd" ]; then
  RUNNER='\$\(|`|<\(|\\$|(^|[^a-z0-9_.-])(bash|sh|zsh|dash|ksh|fish|eval|source|exec|env|sudo|doas|xargs|nohup|time|watch|ssh|python[0-9.]*|node|deno|bun|perl|ruby|php|osascript|awk|sed|chmod|make|install)([^a-z0-9_.-]|$)|(^|[;&|[:space:]])\.[[:space:]]|(^|[;&|[:space:]])\./'
  # A grep error (exit 2) also keeps the original: fail toward checking more.
  printf '%s\n' "$cmd" | tr '[:upper:]' '[:lower:]' | grep -Eq "$RUNNER"; rr=$?
  [ "$rr" -eq 1 ] || cmd="$orig_cmd"
fi
[ -n "$cmd" ] || exit 0

lc=$(printf '%s' "$cmd" | tr '[:upper:]' '[:lower:]')
stripped=$(printf '%s' "$lc" | sed -E "s/$ENV_OK/ /g")
# Quotes and backslashes removed: .a''ws/credentials reads as .aws/credentials.
unquoted=$(printf '%s' "$stripped" | tr -d "'\"\\\\")
# Also one segment per line (split on ; && || | and newline). The guard checks
# the full line and the segments, so a split never hides a match; it can only
# add asks, failing toward ask.
segs=$(printf '%s' "$lc" | sed -E 's/&&|\|\||;|\|/\
/g')

# grep exits 2 on a bad pattern (GNU grep rejects ranges BSD accepts). That must
# not read as "no match": it fails toward ask or deny.
m() { printf '%s' "$2" | grep -Eq "$1"; }
m "$SECRET" "$stripped"; r1=$?
m "$SECRET" "$unquoted"; r2=$?
m "$OBF" "$lc"; r3=$?
m "$PUBLISH|$GITPUSH|$GITALIAS|$GHAPI" "$(printf '%s\n%s' "$lc" "$segs")"; r4=$?
if [ "$r1" -eq 0 ]; then
  decide deny "bash-guard: this command touches a secret file (credentials, keys, .env, tokens). The agent may not read these. If you need it, run it yourself in the prompt: ! <command>"
elif [ "$r1" -eq 2 ] || [ "$r2" -eq 2 ]; then
  decide deny "bash-guard: pattern error, denying to be safe"
elif [ "$r2" -eq 0 ] || [ "$r3" -eq 0 ]; then
  decide ask "bash-guard: this command reaches toward a secret path in a form the guard cannot read reliably. Approve only if you meant it."
elif [ "$r3" -eq 2 ] || [ "$r4" -eq 2 ]; then
  decide ask "bash-guard: pattern error, asking to be safe"
elif [ "$r4" -eq 0 ]; then
  decide ask "bash-guard: this publishes under your account (push, merge or release). Approve only if you asked for it."
fi
exit 0
