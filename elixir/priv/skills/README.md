# Concerto Skills

Copy this directory to your target repo as `.claude/skills/`:

```bash
cp -r path/to/concerto/elixir/priv/skills/ your-repo/.claude/skills/
```

These skills are used by Concerto's WORKFLOW.md to manage the full issue lifecycle:
- `land` -- safely merge PRs
- `commit` -- conventional commit creation
- `push` -- push and create PRs
- `pull` -- sync with origin/main
- `linear` -- interact with Linear via GraphQL
