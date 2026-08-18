# Napkin

## Corrections
| Date | Source | What Went Wrong | What To Do Instead |
|------|--------|----------------|-------------------|
| 2026-03-16 | self | Cloned repo to create public version — forgot git history carries personal content in prior commits | When splitting a repo for public release, always use `git archive` + fresh `git init` to get a clean history. Never clone-and-clean. |
| 2026-03-16 | self | `git remote add` was chained with `git push --force` in same command — hook blocked the push and the remote add silently failed too | Chain independent setup commands separately from destructive ones. Verify each step landed before proceeding. |

## Patterns That Work
- `git archive HEAD | tar -x -C <dest>` extracts working tree without history — clean way to fork a repo publicly
- Run `grep -r` for personal identifiers across ALL files after cleaning — catches things you wouldn't think to check manually
- QA both sides of a repo split independently — verify the public side is clean AND the private side is intact

## Patterns That Don't Work
- Cloning a repo and deleting files doesn't remove them from git history
- `git push --force` is blocked by git_safety hook — user must run manually

## Domain Notes
- This is the **public** Concerto repo — no personal project configs belong here
- Private counterpart lives at `~/Projects/concerto-personal` (SZoloth/concerto-personal)
- WORKFLOW.md uses placeholder values (your-project-slug, your-org/your-repo)
- Elixir runtime managed by mise (erlang 28, elixir 1.19.5-otp-28)
- 245 tests, 29 skipped (live E2E tests need running Linear/Claude)
