---
name: pull
description: "Sync current branch with latest origin/main."
---

# Pull

Keep the branch up to date with main.

## Steps

1. Fetch: `git fetch origin main`
2. Merge or rebase: `git merge origin/main` (prefer merge for cleaner history)
3. If conflicts, resolve them
4. Run tests to verify
5. Record the result: merge source, clean/conflicts, resulting HEAD SHA
