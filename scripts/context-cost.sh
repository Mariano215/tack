#!/usr/bin/env bash
# context-cost.sh
# Prints what the harness costs in every request, per layer.
#
# Instructions written to prop up a weaker model become dead weight on a
# stronger one, and the only way to decide what to cut is to know what each
# layer costs. Memory files are cheap and visible; the skill catalog is
# expensive and invisible, because every enabled skill advertises its
# description on every single turn whether or not it is ever invoked.
#
# Counts are characters. Tokens are approximated as chars/4, which is close
# enough to rank layers. For the real number, run /context in a live session.
#
# --run-hooks also runs the SessionStart hooks and measures their stdout.
# Off by default: plugin-auto-update.sh reaches the network and installs.
set -uo pipefail

CONFIG_ROOT="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
# harness:shared - the plugins tree is machine-wide, one per machine, never
# per profile. hx shell moves CONFIG_ROOT but both profiles read this tree.
PLUGINS_ROOT="$HOME/.claude/plugins"

RUN_HOOKS=0
for a in "$@"; do
  case "$a" in
    --run-hooks) RUN_HOOKS=1 ;;
    -h|--help) sed -n '2,15p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "context-cost: unknown option $a" >&2; exit 2 ;;
  esac
done

[ -d "$CONFIG_ROOT" ] || { echo "context-cost: no config dir at $CONFIG_ROOT" >&2; exit 1; }

# SessionStart stdout is injected verbatim into every session, and for the
# big instruction layers (ponytail, claude-mem, superpowers) it is the whole
# cost: their hooks live in the plugin's own hooks.json, not in settings.json,
# so counting only settings.json misses them entirely.
if [ "$RUN_HOOKS" = 1 ]; then
  HOOK_OUT="$(mktemp)"
  HOOK_CMDS="$(mktemp)"
  trap 'rm -f "$HOOK_OUT" "$HOOK_CMDS"' EXIT
  jq -r '.hooks.SessionStart[]?.hooks[]?.command // empty' \
    "$CONFIG_ROOT/settings.json" 2>/dev/null | tr -d '\r' \
    | sed 's#^#settings.json\t#' > "$HOOK_CMDS"
  while IFS= read -r key; do
    [ -n "$key" ] || continue
    while IFS= read -r dir; do
      # The hooks file is wherever plugin.json says, not always hooks/hooks.json.
      # ponytail points at hooks/claude-codex-hooks.json, and assuming the
      # default silently reports the loudest instruction layer as costing zero.
      hf="$(jq -r '.hooks // "hooks/hooks.json"' "$dir/.claude-plugin/plugin.json" 2>/dev/null | tr -d '\r')"
      case "$hf" in ./*) hf="${hf#./}" ;; esac
      [ -f "$dir/$hf" ] || continue
      jq -r '.hooks.SessionStart[]?.hooks[]?.command // empty' \
        "$dir/$hf" 2>/dev/null | tr -d '\r' \
        | sed "s#\${CLAUDE_PLUGIN_ROOT}#$dir#g; s#\$CLAUDE_PLUGIN_ROOT#$dir#g" \
        | sed "s#^#plugin $key\t#" >> "$HOOK_CMDS"
    done < <(jq -r --arg k "$key" '.plugins[$k][]?.installPath // empty' \
      "$PLUGINS_ROOT/installed_plugins.json" 2>/dev/null | tr -d '\r')
  done < <(jq -r '.enabledPlugins | to_entries[] | select(.value) | .key' \
    "$CONFIG_ROOT/settings.json" 2>/dev/null | tr -d '\r')
  while IFS=$'\t' read -r label cmd; do
    [ -n "$cmd" ] || continue
    n=$(printf '%s' "$(echo '{"hook_event_name":"SessionStart","source":"startup"}' | bash -c "$cmd" 2>/dev/null)" | wc -c | tr -d ' ')
    printf '%s\t%s\n' "$n" "$label" >> "$HOOK_OUT"
  done < "$HOOK_CMDS"
fi

CONFIG_ROOT="$CONFIG_ROOT" PLUGINS_ROOT="$PLUGINS_ROOT" \
HOOK_OUT="${HOOK_OUT:-}" RUN_HOOKS="$RUN_HOOKS" REPO="$(pwd)" python3 - <<'PY'
import json, os, re, glob

cfg = os.environ["CONFIG_ROOT"]
plug = os.environ["PLUGINS_ROOT"]
repo = os.environ["REPO"]
rows = []

def size(path):
    try:
        return len(open(path, encoding="utf-8", errors="replace").read())
    except OSError:
        return 0

def load(path):
    try:
        return json.load(open(path, encoding="utf-8"))
    except (OSError, ValueError):
        return {}

def describe(skill_md):
    """Chars this skill adds to every turn: its name plus its description."""
    try:
        t = open(skill_md, encoding="utf-8", errors="replace").read()
    except OSError:
        return 0
    m = re.match(r"^---\n(.*?)\n---", t, re.S)
    if not m:
        return 0
    d = re.search(r"^description:\s*(.*?)(?=\n\w+:|\Z)", m.group(1), re.S | re.M)
    if not d:
        return 0
    # The listing is "- name: description", so the name and punctuation count.
    return len(d.group(1).strip()) + len(os.path.basename(os.path.dirname(skill_md))) + 4

# 1. Memory files and the active output style. Loaded verbatim, every turn.
settings = load(os.path.join(cfg, "settings.json"))
mem = [os.path.join(cfg, "CLAUDE.md")]
d = repo
while True:
    mem.append(os.path.join(d, "CLAUDE.md"))
    parent = os.path.dirname(d)
    if parent == d:
        break
    d = parent
style = settings.get("outputStyle")
if style:
    mem.append(os.path.join(cfg, "output-styles", "%s.md" % style))
for p in mem:
    n = size(p)
    if n:
        rows.append(("memory", p.replace(os.path.expanduser("~"), "~"), n))

# 2. Subagent descriptions. Same deal as skills: advertised, not loaded.
agents = sum(describe(p) for p in glob.glob(os.path.join(cfg, "agents", "*.md")))
if agents:
    rows.append(("agents", "~/.claude/agents/", agents))

# 3. Skills. The expensive layer, and the one nobody sees.
local = sum(describe(p) for p in glob.glob(os.path.join(cfg, "skills", "*", "SKILL.md")))
if local:
    rows.append(("skills", "~/.claude/skills/", local))

# Only the installed version of an enabled plugin counts. The cache keeps
# every version ever pulled, so globbing it overcounts several times over.
enabled = [k for k, v in settings.get("enabledPlugins", {}).items() if v]
installed = load(os.path.join(plug, "installed_plugins.json")).get("plugins", {})
for key in sorted(enabled):
    for entry in installed.get(key, []):
        path = entry.get("installPath", "")
        n = sum(describe(p) for p in glob.glob(os.path.join(path, "skills", "*", "SKILL.md")))
        if n:
            rows.append(("skills", "plugin %s" % key, n))

if os.environ["RUN_HOOKS"] == "1":
    tally = {}
    for line in open(os.environ["HOOK_OUT"], encoding="utf-8", errors="replace"):
        n, _, label = line.rstrip("\n").partition("\t")
        if n.isdigit() and int(n):
            tally[label] = tally.get(label, 0) + int(n)
    for label in tally:
        rows.append(("hooks", "SessionStart %s" % label, tally[label]))

print("%-8s %-46s %9s %8s" % ("layer", "source", "chars", "~tokens"))
print("-" * 74)
total = 0
for layer, src, n in sorted(rows, key=lambda r: -r[2]):
    total += n
    print("%-8s %-46s %9d %8d" % (layer, src[:46], n, n // 4))
print("-" * 74)
print("%-8s %-46s %9d %8d" % ("TOTAL", "", total, total // 4))
by = {}
for layer, _, n in rows:
    by[layer] = by.get(layer, 0) + n
print("")
for layer in sorted(by, key=lambda k: -by[k]):
    print("  %-8s ~%d tokens (%d%%)" % (layer, by[layer] // 4, round(100 * by[layer] / total) if total else 0))
if os.environ["RUN_HOOKS"] != "1":
    print("")
    print("  SessionStart hook output not counted. Re-run with --run-hooks.")
print("")
print("  Tokens are chars/4, good enough to rank layers. Run /context for the real number.")
PY
