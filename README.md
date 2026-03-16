# Concerto

Turn Linear tickets into pull requests with Claude Code. Autonomously.

Concerto is an Elixir/OTP orchestrator that polls Linear for work, creates isolated workspaces, and dispatches `claude -p` sessions that implement changes and open PRs. Fork of [OpenAI Symphony](https://github.com/openai/symphony), adapted to use Claude Code natively instead of Codex.

> [!WARNING]
> Concerto runs Claude Code autonomously with full permissions. Only use in trusted environments with repos where autonomous changes are acceptable.

## Quick start

```bash
cd elixir
brew install mise && mise trust && mise install
mix setup
export LINEAR_API_KEY=lin_api_...
# Edit WORKFLOW.md with your project slug and repo URL
make start
```

See [elixir/README.md](elixir/README.md) for full setup instructions.

## How it works

1. Polls Linear for issues in active states (Todo, In Progress)
2. Creates an isolated workspace per issue
3. Clones your repo via the `after_create` hook
4. Dispatches `claude -p` with your workflow prompt
5. Claude implements the change, writes tests, opens a PR
6. Moves the issue through your Linear workflow

No API key needed — uses your Claude subscription via `claude -p`.

## Why fork Symphony?

Symphony dispatches OpenAI Codex via JSON-RPC. Concerto replaces the entire agent runtime with Claude Code's native `claude -p` protocol — streaming JSON output, MCP tool injection, session continuity via `--session-id`, and permission handling via `--permission-mode`. The Elixir/OTP orchestration layer (polling, concurrency, retries, supervision) stays intact.

## License

Apache License 2.0 — see [LICENSE](LICENSE).
