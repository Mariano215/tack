---
name: "graphify"
description: "Use when a repo has graphify output, the user asks about a knowledge graph, or codebase navigation would benefit from graph relationships."
---

# Graphify

```bash
[ -f graphify-out/graph.json ] && echo "graph exists"
[ -f graphify-out/.needs_update ] && echo "needs update"
[ -f graphify-out/wiki/index.md ] && echo "wiki exists"
```

- If `.needs_update` exists, run `graphify . --update` before graph queries.
- Use `graphify-out/wiki/index.md` as navigation when present.
- Read raw files after graph navigation identifies likely files.
- Do not edit graph output by hand.
