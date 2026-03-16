# Concerto

An autonomous coding orchestrator that turns Linear tickets into pull requests using Claude Code.

Fork of [OpenAI Symphony](https://github.com/openai/symphony), adapted to use `claude -p` natively instead of Codex. Built on Elixir/OTP for fault-tolerant, concurrent agent management.

> [!WARNING]
> Concerto runs Claude Code with `--permission-mode bypassPermissions`. Only point it at repos where autonomous code changes are acceptable.

## How it works

```
Linear (Todo) → Concerto polls → creates workspace → clones repo
→ dispatches claude -p → Claude works the ticket → pushes branch → opens PR
→ moves issue to In Progress / Done
```

Concerto watches a Linear project for active issues, creates isolated workspaces for each, and dispatches Claude Code sessions that autonomously implement changes, run tests, and open pull requests.

## Quick start

```bash
# 1. Install runtime
brew install mise
cd elixir && mise trust && mise install

# 2. Set up
mix setup
export LINEAR_API_KEY=lin_api_...   # Linear Settings → API → Personal API keys

# 3. Configure WORKFLOW.md (see below)

# 4. Run
make start
```

## WORKFLOW.md

The `WORKFLOW.md` file is your orchestration config + agent prompt. YAML front matter configures the runtime; the Markdown body becomes Claude's system prompt.

Minimal example:

```markdown
---
tracker:
  kind: linear
  project_slug: "your-project-slug"    # from Linear project URL
workspace:
  root: ~/code/concerto-workspaces
hooks:
  after_create: |
    git clone --depth 1 https://github.com/your-org/your-repo.git .
claude:
  command: claude -p
  model: sonnet
  permission_mode: bypassPermissions
---

You are working on Linear ticket {{ issue.identifier }}.

Title: {{ issue.title }}
Description: {{ issue.description }}

Implement the requested changes, write tests, and open a PR.
```

### Target repo setup

Your target repo needs Claude Code skills for the full lifecycle. Copy the template skills:

```bash
cp -r path/to/concerto/elixir/priv/skills/ your-repo/.claude/skills/
```

This adds `land`, `commit`, `push`, `pull`, and `linear` skills that the WORKFLOW.md prompt references.

### Linear workflow states

Concerto's default workflow uses these Linear states. Add them in Team Settings → Workflow:

| State | Type | Purpose |
|-------|------|---------|
| Backlog | Backlog | Not picked up by Concerto |
| Todo | Unstarted | Concerto dispatches agent |
| In Progress | Started | Agent working |
| Human Review | Started | PR open, waiting for human review |
| Rework | Unstarted | Reviewer requested changes, agent re-implements |
| Merging | Started | Human approved, agent lands the PR |
| Done | Completed | Terminal |

### Configuration reference

| Key | Default | Description |
|-----|---------|-------------|
| `tracker.kind` | — | `linear` (required) |
| `tracker.project_slug` | — | Linear project slug from URL |
| `polling.interval_ms` | `30000` | How often to check for new issues |
| `workspace.root` | system tmp | Where to create per-issue workspaces |
| `hooks.after_create` | — | Shell script to run in new workspace (e.g., `git clone`) |
| `agent.max_concurrent_agents` | `10` | Max parallel Claude sessions |
| `agent.max_turns` | `20` | Max turns per issue before returning to orchestrator |
| `claude.command` | `claude -p` | Base Claude CLI command |
| `claude.model` | `sonnet` | Claude model to use |
| `claude.permission_mode` | `bypassPermissions` | Permission handling mode |

### Hook environment variables

All hooks (`after_create`, `before_run`, `after_run`, `before_remove`) receive issue metadata as environment variables:

| Variable | Description |
|----------|-------------|
| `CONCERTO_ISSUE_ID` | Linear issue UUID |
| `CONCERTO_ISSUE_IDENTIFIER` | Issue identifier (e.g., `MT-42`) |
| `CONCERTO_ISSUE_TITLE` | Issue title |
| `CONCERTO_ISSUE_STATE` | Current issue state |

### Finding your project slug

Right-click your Linear project → Copy link. The slug is the ID in the URL:
`https://linear.app/your-org/project/your-project-slug/issues`

## Architecture

```
┌─────────────┐     ┌──────────────┐     ┌─────────────┐
│   Linear    │────▶│  Concerto    │────▶│ Claude Code │
│  (tickets)  │◀────│ (Elixir/OTP) │◀────│ (claude -p) │
└─────────────┘     └──────────────┘     └─────────────┘
                          │                     │
                    ┌─────┴─────┐         ┌─────┴─────┐
                    │ Workspace │         │ MCP Server│
                    │ (git repo)│         │(linear_graphql)
                    └───────────┘         └───────────┘
```

- **Orchestrator** — Elixir GenServer that polls Linear, manages concurrency, handles retries with exponential backoff
- **Agent runner** — per-issue process that manages Claude turns and checks issue state between turns
- **App server** — spawns `claude -p --output-format stream-json` and parses the streaming output
- **MCP server** — Python stdio server that gives Claude a `linear_graphql` tool for reading/writing Linear data
- **Dashboard** — terminal UI showing agent status, token usage, and event stream (plus optional Phoenix web UI via `--port`)

## CLI

```bash
# Start with defaults (reads ./WORKFLOW.md)
make start

# Or directly
mix run -e 'SymphonyElixir.CLI.main(["--yolo"])'

# Custom workflow file
mix run -e 'SymphonyElixir.CLI.main(["--yolo", "/path/to/WORKFLOW.md"])'

# With web dashboard on port 4000
mix run -e 'SymphonyElixir.CLI.main(["--yolo", "--port", "4000"])'
```

## Development

```bash
make all          # format check, lint, coverage, dialyzer
mix test          # run tests
mix compile       # compile
```

## Key differences from Symphony

| Aspect | Symphony (Codex) | Concerto (Claude Code) |
|--------|-----------------|----------------------|
| Protocol | JSON-RPC 2.0 over stdio | `claude -p` streaming JSON |
| Tool injection | `dynamicTools` in thread payload | MCP server via `--mcp-config` |
| Permissions | Approval policy + sandbox | `--permission-mode bypassPermissions` |
| Session management | Persistent thread/turn lifecycle | `--session-id` + `--continue` |
| Auth | API key | Claude subscription (no API key) |

## License

Apache License 2.0 — see [LICENSE](../LICENSE).
