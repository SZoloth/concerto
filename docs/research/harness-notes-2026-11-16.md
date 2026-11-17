# concerto: what the harness posts mean for this repo

Repo: SZoloth/concerto (public). Written 2026-11-16 from the default branch as it stood that day. Nothing was changed on GitHub.

## Source

- Post: [Shishira (@ShishiraReddy05), Nov 16, 2026](https://x.com/ShishiraReddy05/status/2122327324632686967). She had asked the night before for beginner material on harness engineering, then posted three X articles as "must read". No thread; her only other reply says she wants "content which help build own harness".
- [Theo, "What is a 'harness'?"](https://x.com/theo/status/2113424203345265053) (Oct 23, 2026)
- [Harrison Chase, "Your harness, your memory"](https://x.com/hwchase17/status/2042978500567609738) (Apr 11, 2026), which leans on [Sarah Wooders, "Why memory isn't a plugin (it's the harness)"](https://x.com/sarahwooders/status/2040121230473457921) and LangChain's ["The Anatomy of an Agent Harness"](https://blog.langchain.com/the-anatomy-of-an-agent-harness/)
- [Mohit Goyal, "I Built an Agentic Harness From Scratch"](https://x.com/ByteMohit/status/2063493300884246598) (Jun 7, 2026), with code at [MohitGoyal09/AgentForge](https://github.com/MohitGoyal09/AgentForge)

## What the sources say

**Theo: the harness is the plumbing, not the app.** A model only emits text. The harness is five things: tools that do work, a text syntax for calling them, a parser that spots calls and runs code, a way to return results to the model, and a list of tools with descriptions. Claude Code and Codex are an interface wrapped around a harness (Agent SDK, Codex App Server). Tools run inside the harness; MCP servers run "somewhere else" and are reached over a protocol. His kitchen analogy: model is the chef, harness is the kitchen, an app like T3 Code is a restaurant that lets you bring any kitchen. T3 Code exposes its cross-harness features (Claude threads spawning Codex subagents) as one MCP server instead of writing a plugin for every harness. "An agent is a harness plus an LLM," and most "different agents" are the same harness with different tools, instructions and MCP servers.

**Chase and Wooders: whoever owns the harness owns the memory.** Memory is context, and context management is the harness's core job. Wooders lists the hidden decisions a harness makes: how AGENTS.md or CLAUDE.md is loaded, how skill metadata is shown, whether the agent can edit its own instructions, what survives compaction, whether past interactions are stored and searchable, how much of the filesystem and working directory is exposed. Chase's ladder of lock-in: stateful APIs (server-side compaction, Responses API threads) are mildly bad; closed harnesses with unknown memory artifacts are bad; a whole harness plus long-term memory behind an API (Claude Managed Agents) is worst. Codex is open source but its compaction summary is encrypted and unusable elsewhere. His own email agent got deleted and the rebuilt one was far worse because the learned preferences were gone. The prescription: keep memory in open formats you control (AGENTS.md, skills, your own store) so you can switch models and harnesses. The LangChain post adds the standard component list: filesystem and git for durable state, bash as a general tool, sandboxes, memory files, compaction, offloading big tool outputs to files (keep head and tail), skills as progressive disclosure, Ralph loops (a hook that catches the model's attempt to stop and re-injects the goal), and planning plus self-verification.

**Goyal: the model is about 20% of the engineering.** "An agent is a runtime that controls how a model sees, acts, retries, remembers, and stops." The concrete techniques from AgentForge:

- *Session first.* Build the model's world (tools, MCP tools, visible skills, mode) before the first call.
- *The loop is a control system.* Turn budgets (smaller in plan mode), ordered model fallbacks with a circuit breaker that stops calling a failing provider, context-pressure checks with compaction, and a `LoopDetector` that flags three identical tool calls in a row or a repeating cycle of 2 to 5 actions and forces a final answer.
- *Tool results are observations, not logs.* Every tool returns a `ToolResult` with `summary`, `artifacts`, `next_actions` and `recovery_hint`; failures go through an `error_result` factory that fills in a default hint ("inspect the current state ... retry only if the action is still safe").
- *One registry pipeline.* Every result, local or MCP, passes cleanup, secret redaction, untrusted-content wrapping and hooks before the model sees it.
- *File tools expose hidden state.* Line numbers, offset/limit, binary detection, a truncation flag, trailing-newline status. Edits require a unique exact match and, on a miss, show similar lines and say "re-read, your copy may be stale". Patches reject absolute paths and `..`, and dry-run with `git apply --check`.
- *Approval is policy, not a vibe.* Modes (on-request, auto, auto-edit, never, yolo) classify commands, paths and danger flags in plain code. Plan mode removes write tools from the schema list, so the model can't call them at all.
- *Tool output is evidence, not authority.* File reads, shell output, web pages and MCP responses get wrapped as `<untrusted_content source=...>` with a note to treat it as data. (Its wrapper does not escape a forged closing tag inside the content, so it is a label, not a sandbox, which the author admits.)
- *Context is not a transcript.* Track token estimates, prune old tool output, compact older turns into a continuation summary that lists completed work, and count compaction's own token cost.
- *Skills are context budgeting.* `discover()` builds a metadata index; `load_skill()` spends context only when a skill is chosen.
- *MCP tools get namespaced* (`github__create_issue`) and go through the same registry, approvals and wrapping as built-in tools.
- *Subagents are tools first.* One goal in, one result out, scoped tools, max turns, hard timeout, read-only by default. Swarms are a later, separate problem.
- *Persistence is systems work.* Atomic writes, owner-only permissions, append-only JSONL event logs, and tests that run against an isolated home directory because his session tests were silently reading his real `~/Library/Application Support` state.
- *Test the boundaries, not the prose.* 278 tests, none needing a model call: blocked commands, secret stripping, unique-match edits, plan-mode filtering, snapshot round-trips, wrapper coverage.

His starter checklist: one model adapter, a loop with stop conditions, three typed tools, structured results with recovery hints, approval before writes, line-numbered reads, context pruning, one checkpoint, one skill, one namespaced MCP server, and one test where a tool fails and the model still gets a useful observation.

## What this repo is

Public. Concerto is Symphony's Elixir orchestrator with the agent runtime replaced by `claude -p`. It polls Linear, makes a workspace per issue, and runs Claude until the issue leaves an active state. Last pushed Aug 18, 2026.

## What applies

The public README tells strangers to run it "with full permissions", so the first suggestion matters more here, because other people may copy the default.

Suggested order if you touch this repo again:

1. **Treat Linear text as untrusted, and ship a safer default.** The prompt template pastes the issue title and description straight into the prompt (and the agent then reads comments through the Linear tools), while the README points people at a full-permissions run. Anyone who can write to that Linear project can tell an unsandboxed agent to run anything. Three steps, in order of cost: (a) in the prompt builder, put issue text inside a labeled block and say it is the task description, not authority to change permissions, touch other repos or read secrets; (b) turn on a label filter (for example `filters.labels: ["agent-ready"]` in `WORKFLOW.md`) so only issues you labeled get picked up; (c) replace `bypassPermissions` with an allowlist (`--allowedTools` for git, the test runner and `gh pr create`). Ship `WORKFLOW.md` with the label filter and the allowlist on, and document bypass as an opt-in.

2. **Add a cheap loop detector across turns.** Continuation turns can repeat the same failing command. If the runtime streams tool events, record a signature per tool call (name plus sorted args) and stop the run with a clear Linear comment after three identical calls or a short repeating cycle. AgentForge's `context/loop_detector.py` is about 50 lines and ports directly.

3. **Turn a "Done without a merged PR" outcome into a block.** If a run can mark an issue Done without a merged PR, don't just log it somewhere nobody reads. Move the issue back to `Rework` with a comment, or mark the run failed. Goyal: "If you build the stop conditions, you start building a harness."

## What doesn't apply

- Building your own tool contracts, file tools or compaction. Claude Code owns those inside its harness; Concerto shouldn't duplicate them.
- A provider circuit breaker only matters once a second provider exists, which this version doesn't have.
- Chase's memory argument cuts mildly here: Claude session continuity is harness-owned memory you can't move elsewhere. Keep durable run state in the workspace and Linear workpad, not in the session.
