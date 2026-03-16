---
name: push
description: "Push current branch to origin and create PR if needed."
---

# Push

Push the current branch and ensure a PR exists.

## Steps

1. Push: `git push -u origin HEAD`
2. If no PR exists, create one: `gh pr create --fill`
3. Link the PR to the Linear issue via issue attachment
4. Add the `concerto` label to the PR
