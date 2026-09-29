# Vendored superpowers skills

Copied from superpowers 6.4.1 (github.com/obra/superpowers, MIT) by
scripts/vendor-superpowers.sh. Do not edit these skills by hand: re-run the
script on a newer plugin dir, and put any local change in its rewrite list.

Left out on purpose: the SessionStart bootstrap (using-superpowers), which
orders a skill on a "1% chance" and over-triggers on Claude 5 models,
writing-skills, which is for skill authors, and upstream test fixtures.

Local patches (listed in the script): the brainstorming description drops
"You MUST use", and subagent-driven-development defers model tier and its
retry cap to smart-agent-spawner (3 rounds, not 5). The spec, plan and
implementer self-review checklists stay: they check a written artifact
against named items, and templates/CLAUDE.md says so.

Skills: brainstorming writing-plans executing-plans subagent-driven-development systematic-debugging test-driven-development requesting-code-review verification-before-completion finishing-a-development-branch using-git-worktrees

MIT License

Copyright (c) 2025 Jesse Vincent

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
