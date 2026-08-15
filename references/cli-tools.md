# CLI tools that replace MCP servers

These MCP servers were dropped to cut per-session context. Their capability is
still available via CLI, called through Bash. Reach for these instead of the
removed MCP tools.

## tokensave (replaces the tokensave MCP, ~83 tools)
Code-graph queries and edits via the `tokensave` binary on PATH.
```
tokensave context "<task>"        # AI-ready context for a task
tokensave search <symbol>          # find symbols by name
tokensave callers <symbol>         # who calls X
tokensave status                   # graph stats
tokensave --help                   # full command list
```
For cross-file semantic relationships or community detection (not just "who calls X"), use the `graphify` skill instead, it builds a persistent knowledge graph rather than a mechanical call-graph index.

## gh (replaces the github MCP)
```
gh pr list / gh pr view <n> / gh pr create
gh issue list / gh issue view <n>
gh api <endpoint>                  # raw GitHub API
```

## Kept as MCP (all profiles unless noted)
- `context7`: library/framework docs (dev, web). Rides the context7 plugin.
- `atlassian`: Jira/Confluence (audit, proposal). Added explicitly by apply-profile.
- `chrome-devtools` / `playwright`: live browser (web). Ride their plugins.

## Dropped entirely
`sequential-thinking` (native reasoning covers it) and the unauthenticated
claude.ai stubs (Notion, Figma, Microsoft 365, Atlassian Rovo).
