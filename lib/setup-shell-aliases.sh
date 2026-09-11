#!/usr/bin/env bash
# setup-shell-aliases.sh: idempotently write harness wrappers into every rc
# file present (~/.zshrc, ~/.bashrc, covering macOS and Ubuntu). Plain
# `claude`, no proxy wrap.
# Windows equivalent: setup-core.ps1.
# claude-tg (Telegram bot) is machine-local, not part of this shared setup.
#
# Alias name is deliberately different inside a container, so the prompt you
# type tells you which environment (and which login) you are in:
#   host      -> claude-code
#   container -> yolo
# Override either way with HARNESS_ALIAS_NAME.
set -euo pipefail

in_container() {
  [ -f /.dockerenv ] && return 0
  [ -n "${REMOTE_CONTAINERS:-}${CODESPACES:-}${DEVCONTAINER:-}" ] && return 0
  grep -qaE 'docker|containerd|kubepods' /proc/1/cgroup 2>/dev/null && return 0
  return 1
}

if [ -n "${HARNESS_ALIAS_NAME:-}" ]; then
  ALIAS_NAME="$HARNESS_ALIAS_NAME"
elif in_container; then
  ALIAS_NAME="yolo"
else
  ALIAS_NAME="claude-code"
fi

# Both lines below change how `claude` runs for every shell on the machine, so
# both are opt-in. Blanking ANTHROPIC_API_KEY forces subscription auth, which is
# right on a Max account and breaks anyone paying by API key. The skip-permissions
# alias turns off the confirmation prompt on file writes and shell commands.
# Enable with HARNESS_NO_API_KEY=1 and HARNESS_YOLO_ALIAS=1, or the
# --no-api-key / --yolo-alias flags to setup-core.sh.
NO_API_KEY="${HARNESS_NO_API_KEY:-0}"
YOLO_ALIAS="${HARNESS_YOLO_ALIAS:-0}"

START="# >>> tack aliases >>>"
END="# <<< tack aliases <<<"
BLOCK_FILE="$(mktemp)"
trap 'rm -f "$BLOCK_FILE"' EXIT
{
  echo "$START"
  [ "$NO_API_KEY" = 1 ] && echo 'function claude() { ANTHROPIC_API_KEY="" command claude "$@"; }'
  # codex reads the active tack profile unless the caller names one.
  cat <<'CODEXFN'
function codex() {
  local harness_arg harness_active_file harness_profile
  for harness_arg in "$@"; do
    case "$harness_arg" in
      -p|--profile|--profile=*) command codex "$@"; return ;;
    esac
  done
  harness_active_file="${CODEX_HOME:-$HOME/.codex}/.harness-active"
  if [ -f "$harness_active_file" ]; then
    harness_profile="$(cat "$harness_active_file" 2>/dev/null | tr -d '\r\n')"
    if [ -n "$harness_profile" ] && [ -f "${CODEX_HOME:-$HOME/.codex}/$harness_profile.config.toml" ]; then
      command codex -p "$harness_profile" "$@"
      return
    fi
  fi
  command codex "$@"
}
CODEXFN
  if [ "$YOLO_ALIAS" = 1 ]; then
    echo "alias $ALIAS_NAME='claude --dangerously-skip-permissions'"
  else
    echo "alias $ALIAS_NAME='claude'"
  fi
  echo "$END"
} > "$BLOCK_FILE"

# headroom is gone from the harness, but the lines it wrote sit outside our
# markers, so rewriting the block left them behind on every apply. The
# container kept its proxy exports and headroom-wrapped yolo alias through
# every `tack sync`. Strip them here: any headroom line, its own marker block,
# and the proxy exports that point Claude at the local wrap port.
purge_headroom() {
  local rc="$1"
  grep -qiE 'headroom|127\.0\.0\.1:8787|localhost:8787' "$rc" 2>/dev/null || return 0
  awk '
    tolower($0) ~ /^# *>>>.*headroom.*>>>/ {skip=1; next}
    tolower($0) ~ /^# *<<<.*headroom.*<<</ {skip=0; next}
    skip {next}
    tolower($0) ~ /headroom/ {next}
    /(ANTHROPIC_BASE_URL|ANTHROPIC_API_URL|HTTP_PROXY|HTTPS_PROXY|http_proxy|https_proxy)=.*(127\.0\.0\.1|localhost):8787/ {next}
    {print}
  ' "$rc" > "$rc.tmp" && mv "$rc.tmp" "$rc"
  echo "legacy headroom lines removed from $rc"
}

write_block() {
  local rc="$1"
  touch "$rc"
  purge_headroom "$rc"
  if grep -qF "$START" "$rc" 2>/dev/null; then
    awk -v start="$START" -v end="$END" -v blockfile="$BLOCK_FILE" '
      $0 == start {while ((getline line < blockfile) > 0) print line; skip=1; next}
      $0 == end {skip=0; next}
      !skip {print}
    ' "$rc" > "$rc.tmp" && mv "$rc.tmp" "$rc"
    echo "tack aliases ($ALIAS_NAME) updated in $rc"
  else
    { echo; cat "$BLOCK_FILE"; } >> "$rc"
    echo "tack aliases ($ALIAS_NAME) added to $rc"
  fi
}

wrote_any=0
for rc in "$HOME/.zshrc" "$HOME/.bashrc"; do
  [ -f "$rc" ] || continue
  write_block "$rc"
  wrote_any=1
done
[ "$wrote_any" = 1 ] || write_block "$HOME/.bashrc"  # neither existed: create one
