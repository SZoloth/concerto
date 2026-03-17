# PRD: Concerto Feature Parity — Productized Edition

**Status**: Draft
**Author**: Claude (autonomous execution)
**Date**: 2026-03-16

## Problem

Concerto (public) is a solid single-project orchestrator, but it lacks key features proven in concerto-personal that are necessary for real-world adoption. A user who downloads Concerto today can only run one project, gets no planning phase, has no model routing, and must understand the internals to get started. These gaps make the tool feel like a demo rather than a product.

## Goal

Bring five features from concerto-personal into the public Concerto repo, adapted for a multi-user audience with sensible defaults and full configurability. No feature should require understanding the codebase to use — WORKFLOW.md is the sole configuration surface.

---

## Feature 1: Two-Phase Execution (Plan → Execute)

### What

Add optional Opus-powered planning phase on turn 1 that writes a structured execution plan to the Linear issue, followed by Sonnet execution on subsequent turns.

### Config Surface (WORKFLOW.md)

```yaml
claude:
  model: sonnet                    # default execution model
  planning_model: opus             # set to enable two-phase; omit to disable
  execution_model: sonnet          # explicit execution model (optional, defaults to model)
```

### Behavior

- When `planning_model` is set AND issue does NOT have `spec-ready` label:
  - Turn 1 uses `planning_model`, sends planning-only prompt
  - Turn 2 gets full workflow prompt + execution continuation context
  - Turns 3+ get standard continuation prompt
- When `planning_model` is set AND issue HAS `spec-ready` label:
  - Skip planning, go straight to execution with `execution_model` (or `model`)
- When `planning_model` is NOT set:
  - Current behavior unchanged (single-phase execution)

### Implementation

1. **Schema** (`config/schema.ex`): Add `planning_model`, `execution_model` fields to `Claude` embedded schema
2. **PromptBuilder** (`prompt_builder.ex`): Add `build_planning_prompt/2` and `build_execution_continuation_prompt/2` functions (port from concerto-personal)
3. **AgentRunner** (`agent_runner.ex`): Update `build_turn_prompt/4` to branch on planning_model presence and spec-ready label
4. **AppServer** (`claude/app_server.ex`): Update `build_command/2` to accept issue, call `resolve_model/3` for per-turn model selection
5. **Issue struct**: Ensure `labels` and `priority` fields are available (verify existing Linear client populates these)

### Acceptance Criteria

- [ ] `planning_model: opus` in WORKFLOW.md causes turn 1 to use Opus with planning prompt
- [ ] `spec-ready` label skips planning turn
- [ ] Omitting `planning_model` preserves current single-phase behavior (backward compatible)
- [ ] Planning prompt follows the structured format (Design Intent, Task Type, Approach, Acceptance Criteria, Risks)

---

## Feature 2: Model Upgrade Routes (Label + Priority)

### What

Automatically upgrade the Claude model for specific issues based on Linear labels or priority levels, without manual intervention.

### Config Surface (WORKFLOW.md)

```yaml
claude:
  model: sonnet
  upgrade_model: opus              # model to use when upgrade triggers match (default: opus)
  upgrade_labels:                  # issues with these labels get upgrade_model
    - opus
    - complex
  upgrade_priorities:              # Linear priority numbers that trigger upgrade
    - 1                            # Urgent
    - 2                            # High
```

### Behavior

Resolution order: label match → priority match → default model. Planning model (if configured) takes precedence on turn 1.

### Implementation

1. **Schema** (`config/schema.ex`): Add `upgrade_model`, `upgrade_labels`, `upgrade_priorities` to Claude schema
2. **AppServer** (`claude/app_server.ex`):
   - Change `build_command/2` signature to `build_command/3` (add `issue` parameter)
   - Add `resolve_model/3` function with label/priority matching logic
   - Add `upgraded_by_label?/2` and `upgraded_by_priority?/2` helpers
3. **AgentRunner**: Pass issue through to AppServer.run_turn (already done)

### Acceptance Criteria

- [ ] Issue with `opus` label uses `upgrade_model` instead of `model`
- [ ] Issue with priority 1 uses `upgrade_model` when `upgrade_priorities: [1, 2]`
- [ ] Label match takes precedence over priority match
- [ ] Planning model takes precedence over upgrade model on turn 1
- [ ] Empty `upgrade_labels`/`upgrade_priorities` means no upgrades (backward compatible)

---

## Feature 3: CLI with Prerequisite Validation

### What

Add a proper CLI entrypoint with guardrail acknowledgment and prerequisite checks so first-time users get clear error messages instead of cryptic crashes.

### Interface

```bash
bin/concerto --yolo [--logs-root /path] [--port 4000] [WORKFLOW.md]
```

### Behavior

- Requires `--yolo` or `--i-understand-that-this-will-be-running-without-the-usual-guardrails` flag
- Validates `claude` CLI is installed
- Validates `LINEAR_API_KEY` is set and non-empty
- Accepts optional workflow file path (defaults to `./WORKFLOW.md`)
- Accepts optional `--logs-root` for log directory
- Accepts optional `--port` for web dashboard

### Implementation

The public repo already has `cli.ex` and `cli_test.exs` — this feature is already present. Verify completeness and ensure escript build works.

### Acceptance Criteria

- [ ] Running without `--yolo` shows red banner with explanation
- [ ] Missing `claude` CLI shows actionable install link
- [ ] Missing `LINEAR_API_KEY` shows where to get one
- [ ] Custom workflow path loads correctly
- [ ] `--port` and `--logs-root` flags work

---

## Feature 4: Planning Prompt Template

### What

Ship a high-quality default planning prompt that produces structured execution plans, while allowing users to override it via WORKFLOW.md.

### Implementation

The planning prompt is hard-coded in `PromptBuilder.build_planning_prompt/2` (ported from concerto-personal). It produces:

```
## Execution Plan (generated by Opus)

### Design Intent
### Task Type
### Approach
### Acceptance Criteria
### Risks / Ambiguities
```

This is intentionally NOT a configurable template in v1 — the structured format is the value proposition. Users who want custom planning can set `planning_model: null` and write their own prompt in WORKFLOW.md.

### Acceptance Criteria

- [ ] Planning prompt includes all five sections
- [ ] Planning prompt instructs agent NOT to implement (plan only)
- [ ] Execution continuation prompt on turn 2 references the Opus plan

---

## Feature 5: Model Resolution in AppServer

### What

Centralize per-turn model selection in AppServer so the correct model is used for each phase (planning, execution, upgrade).

### Implementation

1. **AppServer** (`claude/app_server.ex`):
   - `build_command/2` → `build_command/3` with `issue` parameter
   - Add `resolve_model/3` that implements the resolution chain:
     1. Turn 1 + planning_model configured → planning_model
     2. Turn 2+ + execution_model configured → execution_model (with upgrade checks)
     3. Label upgrade match → upgrade_model
     4. Priority upgrade match → upgrade_model
     5. Default → model
   - Log model resolution when it differs from default

2. **run_turn/4**: Thread issue into `build_command/3`

### Acceptance Criteria

- [ ] Model resolution follows documented precedence chain
- [ ] Non-default model selection is logged with reason
- [ ] All existing tests pass (backward compatible when new fields are absent)

---

## Out of Scope (v2+)

These features exist in concerto-personal but are deferred:

- **Multi-workflow directory** (`workflows/*.md` with WorkflowStore): Significant orchestrator refactor needed. Ship as separate PR.
- **SSH worker distribution**: Power-user feature, needs security review.
- **Web dashboard LiveView**: Already present in both codebases, just needs the data wired.

---

## Test Plan

All changes must pass `make all` (format, lint, coverage, dialyzer).

### New Tests Required

1. **Schema tests**: Parse configs with planning_model, execution_model, upgrade_model, upgrade_labels, upgrade_priorities
2. **Model resolution tests**: Unit tests for `resolve_model/3` covering all precedence paths
3. **Planning prompt tests**: Verify `build_planning_prompt/2` output structure
4. **Execution continuation tests**: Verify `build_execution_continuation_prompt/2` output
5. **AgentRunner turn routing tests**: Verify correct prompt builder function called per turn/label combination
6. **Backward compatibility tests**: Verify configs WITHOUT new fields still work identically

### Existing Tests

- CLI tests already exist (`cli_test.exs`) — verify they still pass
- AppServer tests (`app_server_test.exs`) — extend with model resolution cases
- Config/Schema tests (`workspace_and_config_test.exs`) — extend with new fields

---

## Implementation Order

1. Schema changes (add fields) — no behavior change, all tests pass
2. PromptBuilder additions (planning + continuation prompts) — new functions, no existing behavior change
3. AppServer model resolution — `build_command/3` with issue, `resolve_model/3`
4. AgentRunner turn routing — two-phase branching logic
5. Tests for all of the above
6. Verify `make all` passes
