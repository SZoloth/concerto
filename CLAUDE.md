# Concerto

Fork of [OpenAI Symphony](https://github.com/openai/symphony) adapted to use Claude Code (`claude -p`) as the agent runtime instead of Codex.

## Architecture

- **Orchestrator**: Elixir/OTP (based on Symphony) — polls Linear, manages workspaces, controls concurrency
- **Agent runtime**: `claude -p` with `--output-format stream-json --verbose` (replaces Codex JSON-RPC app-server)
- **Tool injection**: MCP server for `linear_graphql` via `--mcp-config` (replaces Codex `dynamicTools`)
- **Permissions**: `--permission-mode bypassPermissions` (replaces Codex approval policy/sandbox)
- **Multi-turn**: `--session-id` + `--continue` flags (replaces Codex thread/turn lifecycle)

## Key files

- `elixir/lib/symphony_elixir/claude/app_server.ex` — Claude Code client (stream-json protocol)
- `elixir/lib/symphony_elixir/claude/mcp_config.ex` — MCP config generation for tool injection
- `elixir/priv/mcp/linear_graphql_server.py` — Standalone MCP server for Linear GraphQL
- `elixir/WORKFLOW.md` — Workflow policy (prompt + YAML config)
- `elixir/lib/symphony_elixir/orchestrator.ex` — Polling state machine
- `elixir/lib/symphony_elixir/agent_runner.ex` — Per-issue turn loop

## Running

```bash
cd elixir
mix setup
export LINEAR_API_KEY=lin_api_...
make start
```

## Config (WORKFLOW.md)

```yaml
claude:
  command: claude -p          # Base command
  model: sonnet               # Claude model
  permission_mode: bypassPermissions  # Permission handling
```

## Development

```bash
cd elixir
make all  # format check, lint, coverage, dialyzer
```
