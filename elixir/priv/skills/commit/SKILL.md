---
name: commit
description: "Create clean, logical commits. Use conventional commit format."
---

# Commit

Create a well-structured commit for the current changes.

## Rules

- Use conventional commit format: `feat:`, `fix:`, `refactor:`, `test:`, `docs:`, `chore:`
- Scope to the ticket identifier when possible: `feat(SAM-123): add multiply function`
- One logical change per commit
- Run tests before committing
- Stage specific files, not `git add -A`
