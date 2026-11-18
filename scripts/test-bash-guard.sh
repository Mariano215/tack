#!/usr/bin/env bash
# Covers hooks/bash-guard.sh: secret reads are denied in every mode, obfuscated
# secret paths ask, everything else (publishing included) passes silently, junk
# input exits 0.
set -uo pipefail
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
HOOK="$REPO_ROOT/hooks/bash-guard.sh"
failed=0
fail() { echo "test-bash-guard: $1"; failed=1; }
decision() {
  jq -cn --arg c "$1" '{tool_name:"Bash",tool_input:{command:$c}}' | bash "$HOOK" \
    | jq -r '.hookSpecificOutput.permissionDecision // "none"' 2>/dev/null | tr -d '\r'
}
check() { local got; got="$(decision "$2")"; [ "${got:-none}" = "$1" ] || fail "want $1, got ${got:-none}: $2"; }

check deny 'cat ~/.aws/credentials'
check deny 'cat ~/.ssh/id_ed25519'
check deny 'source .env'
check deny 'cat app/.env.production'
check deny 'jq . ~/.claude.json'
check deny 'cat ~/.claude-profiles/audit@x/.credentials.json'
check deny 'cat ~/.claude-mem/settings.json'
check deny 'cat ~/.claude/.fal-key'
check deny 'security find-generic-password -s x -w'
check deny 'cat ~/.config/gh/hosts.yml'
check none 'cp .env.example .env.sample'
check none 'direnv allow .envrc'
check none 'ls -la'
check none 'git status'
check none 'git push origin main'
check none 'git add . && git commit -m x && git push'
check none 'git -C ../tack push -q origin main'
check none 'gh pr merge 12 --squash'
check none 'gh release create v1.0.0'
check none 'tack sync --push'
check none "bash -c 'git push'"
check none 'git "push"'
check none 'bash -c "git push"'
check none 'sh -c "gh pr merge 1"'
check none "GIT_CONFIG_PARAMETERS=\"'alias.p=push'\" git p"
check none 'gh repo create o/r --private --source=. --push'
check none 'gh repo view o/r'
check none 'git commit -m "fix"'
check none 'gh pr view 12'
check none 'git pushd'
check deny 'cat .env.production.local'
check deny 'cat .env.qa'
check none 'cp .env.template .env.sample'
check none 'git -c user.name=x push'
check none '/usr/bin/git push'
check none 'command git push origin main'
check none 'env FOO=1 git push'
check none '\git push'
check none 'git --git-dir=x --work-tree=y push'
check none 'git send-pack origin'
check none 'gh api -X POST repos/o/r/releases'
check none 'gh api repos/o/r --method DELETE'
check none 'gh api repos/o/r'
check ask  "cat ~/.a''ws/credentials"
check ask  'cat ~/.aw?/credentials'
check ask  'cat ~/.claude.j*'
check ask  'cat ~/.cred*/x'
check ask  'cat app/.en[v]'
check ask  'eval "$(echo Y2F0 | base64 -d)" ~/.ssh'
check none 'grep -r credentials src/*.js'
check deny 'cat ~/.AWS/credentials'
check deny 'cat ~/.SSH/id_rsa'
check deny 'cat .ENV'
check none 'cat .ENV.EXAMPLE'
check deny 'cat .env.example.local'
check none 'gh api repos/o/r/issues -f title=x'
check none 'gh api graphql -F query=@q.graphql'
check none 'gh api repos/o/r --input body.json'
check none 'gh api -X GET repos/o/r'
check none 'git --git-dir x push'
check none 'git -c alias.p=push p'
check none 'git log --oneline'
check none 'git -C "a;b" push'
check none '$(git push)'
check none '(git push)'
check none 'echo `git push`'
check none "git -c alias.x='!git push' x"
check none 'GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0=alias.p GIT_CONFIG_VALUE_0=push git p'
check deny 'cat .env && git push'
# Heredoc bodies are text unless a shell or interpreter reads them.
check none "$(printf "cat >> .agent/log.md <<'EOF'\n- next: git push the branch, rotate .env\nEOF")"
check deny "$(printf 'cat >> .agent/log.md <<EOF\n- next: git push the branch, rotate .env\nEOF')"
check deny "$(printf 'cat > a <<EOF\nx \\\n$(cat .env)\nEOF')"
check none "$(printf "git commit -q -F - <<'EOF'\nfix: guard push and .env reads\nEOF")"
check deny "$(printf 'cat >> log.md <<EOF\ntext\nEOF\ncat .env origin main')"
check deny "$(printf 'bash <<EOF\ncat ~/.aws/credentials\nEOF')"
check deny "$(printf "python3 - <<'PY'\nopen('.env').read()\nPY")"
check deny "$(printf 'cat <<EOF | sh\ncat .env\nEOF')"
check deny "$(printf 'cat <<-EOF\n\tx\n\tEOF\ncat .env')"
check deny 'cat <<< "$(cat .env)"'
check none "$(printf "cd /x && cat >> log.md <<'EOF'\nnote: git push later\nEOF")"
# The exact log-append shape hooks/session-summary.sh asks for must pass.
check none "$(printf "date '+%%n## %%Y-%%m-%%d %%H:%%M' >> .agent/log.md && cat >> .agent/log.md <<'EOF'\n- next: git push, rotate the .env key\nEOF")"
# cat or tee count as text only into .md, .txt or .log outside .git/.
check deny "$(printf "cat > x <<'EOF'\ncat .env\nEOF\nchmod +x x; ./x")"
check deny "$(printf "cat > .git/hooks/notes.md <<'EOF'\ncat .env\nEOF")"
check deny "$(printf "cat >> ~/.zshrc <<'EOF'\ncat .env\nEOF")"
check deny "$(printf "cat > run <<'EOF'\ncat .env\nEOF")"
check none "$(printf "tee -a notes.txt <<'EOF'\nthen git push\nEOF")"
check none "$(printf "cat <<'EOF' > docs/plan.md\nstep: git push\nEOF")"
# Target parsing: one plain redirect, case-insensitive .git, no $ on the line.
check deny "$(printf "cat > notes.md 2> run.sh <<'EOF'\ncat .env\nEOF")"
check deny "$(printf "cat > .GIT/hooks/x.md <<'EOF'\ncat .env\nEOF")"
check deny "$(printf "tee a.md run.sh <<'EOF'\ncat .env\nEOF")"
check deny "$(printf "cat > \"\$(echo a)\".md <<'EOF'\ncat .env\nEOF")"
# Anything outside the body that is not on the allowlist keeps it checked.
check deny "$(printf "cat > a.md <<'EOF'\ncat .env\nEOF\ngawk -f a.md")"
check deny "$(printf "cat > a.md <<'EOF'\ncat .env\nEOF\nnpx tsx a.md")"
check none "$(printf "git add x.md && git commit -q -F - <<'EOF'\nnote: git push next\nEOF\ngit log --oneline -1")"
# A quoted body is still checked when something outside it can run it.
check deny "$(printf "x=1; eval \"\$(\ncat <<'EOF'\ncat ~/.aws/credentials\nEOF\n)\"")"
check deny "$(printf "cat <<'EOF' \\\\\n| sh\ncat .env\nEOF")"
check deny "$(printf "cat > s <<'EOF'\ncat .env\nEOF\nbash s")"
check deny "$(printf "bash -c \"\$(true; cat <<'EOF'\ncat .env\nEOF\n)\"")"
check none "$(printf "git commit -q -F - <<'EOF'\nfix: guard push and .env reads\nEOF\ngit log --oneline -1")"
# git log or diff with a file-writing option can drop the body into a file.
check deny "$(printf "git commit -F - <<'EOF'\ncat .env\nEOF\ngit log -1 --output=.git/hooks/pre-push")"
check deny "$(printf "cat <<'EOF' | git diff --no-index --outp=run.sh /dev/null /dev/stdin\ncat .env\nEOF")"
# A single & or a process substitution on the header line can run the body.
check deny "$(printf "cat > s <<'EOF' & sh s\ncat .env\nEOF")"
check deny "$(printf "cat <<'EOF' > >(sh)\ncat .env\nEOF")"
check deny "$(printf "tee >(sh) <<'EOF'\ncat .env\nEOF")"
check none "$(printf "cat > a.md <<'EOF'\ngit push\nEOF")"
check deny "$(printf '/bin/bash <<EOF\ncat .env\nEOF')"
check deny "$(printf 'xargs -I{} sh -c {} <<EOF\ncat .env\nEOF')"
check deny "$(printf 'cat > a <<EOF\nnever closed .env')"
check deny "$(printf 'cat <<\"E\"OF\nx\nEOF\ncat .env')"
check deny "$(printf 'echo \"<<EOF\"\ncat .env\nEOF')"
check deny "$(printf 'cat > a <<EOF\n$(cat .env)\nEOF')"
check deny "$(printf 'cat > a <<EOF\n`cat .env`\nEOF')"
check none "$(printf "cat > a.md <<'EOF'\n\$(git push) is only text here\nEOF")"

printf '' | bash "$HOOK" >/dev/null 2>&1 || fail "empty stdin should exit 0"
printf 'not json' | bash "$HOOK" >/dev/null 2>&1 || fail "malformed stdin should exit 0"
[ -z "$(printf 'not json' | bash "$HOOK")" ] || fail "malformed stdin printed output"

# Strict engine: every pattern must compile under GNU grep or ugrep (exit 2 = invalid).
strict=""; for g in ggrep ugrep; do command -v "$g" >/dev/null 2>&1 && { strict="$g"; break; }; done
# Plain grep is GNU grep on Linux CI, so exit 2 there is caught even with no strict engine.
engines="grep"; [ -n "$strict" ] && engines="grep $strict"
if true; then
  for v in SECRET OBF; do
    pat="$(bash -c ". <(sed -n '/^ENV_OK=/,/^OBF=/p' \"$HOOK\"); printf '%s' \"\${$v}\"")"
    for e in $engines; do
      printf x | "$e" -E "$pat" >/dev/null 2>&1; [ $? -ne 2 ] || fail "$v does not compile under $e"
    done
  done
fi

[ "$failed" = 0 ] && echo "test-bash-guard: ok"
exit "$failed"
