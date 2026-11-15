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
PUBLISH='(^|[^a-z0-9_.-])(gh[[:space:]]+pr[[:space:]]+merge|gh[[:space:]]+release[[:space:]]+(create|edit|delete|upload)|gh[[:space:]]+repo[[:space:]]+create[[:space:]].*--push|(tack|tack)[[:space:]]+sync[[:space:]]+--push)([[:space:];&|()<>`'"'"'"]|$)'
# push or send-pack as a whole token (ends at space, end, or ;&|()<> or backtick) anywhere after a git token, or any git alias definition (-c alias.x=..., GIT_CONFIG_KEY_n).
GITPUSH='(^|[^a-z0-9_.-])git([[:space:]].*)?[[:space:]'"'"'"](push|send-pack)([[:space:];&|()<>`'"'"'"]|$)'
GITALIAS='(^|[^a-z0-9_.-])git[[:space:]].*alias\.|git_config_key_|git_config_parameters'
# gh api writes: a non-GET method, or any field/input flag (those make it a POST).
GHAPI='(^|[^a-z0-9_.-])gh[[:space:]]+api.*([[:space:]](-x|--method)[[:space:]=]*(post|put|patch|delete)|[[:space:]](-f|--field|--raw-field|--input))'
# Secret-dir mentions combined with a form the regexes cannot read reliably.
SPFX='(\.aws|\.ssh|\.config/gh|\.claude-mem|\.claude-profiles|\.fal-key|credentials)'
OBF="${SPFX}.*(eval|base64|\`|\\\$\()|(eval|base64|\`|\\\$\().*${SPFX}|[^[:space:]]*${SPFX}[^[:space:]]*[*?[]|[*?[][^[:space:]]*${SPFX}"

decide() {
  jq -cn --arg d "$1" --arg r "$2" \
    '{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:$d,permissionDecisionReason:$r}}'
}

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
