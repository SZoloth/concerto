---
name: land
description: "Safely merge the current branch's PR into main. Use when the Linear issue is in Merging state."
---

# Land

Merge the current PR into main safely.

## Steps

1. Ensure you're on the feature branch (not main)
2. Run `gh pr view --json number,state,mergeable,mergeStateStatus` to check PR status
3. If not approved or checks failing, stop and report
4. Pull latest main: `git fetch origin main`
5. Rebase on main: `git rebase origin/main`
6. If conflicts, resolve them, run tests, push
7. Force-push rebased branch: `git push --force-with-lease`
8. Wait for CI to pass: poll `gh pr checks` until all pass
9. Merge: `gh pr merge --squash --auto`
10. Verify merge completed: `gh pr view --json state`
11. Clean up: delete the remote branch if merged
