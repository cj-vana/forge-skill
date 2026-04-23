---
name: forge:build
description: Claude-led build workflow — research, deep questioning, detailed step plans, implement with Claude review gates
argument-hint: "[project description or @ file reference]"
allowed-tools:
  - Read
  - Write
  - Edit
  - Bash
  - Glob
  - Grep
  - Agent
  - AskUserQuestion
  - WebSearch
  - WebFetch
---

<objective>
Build software through a rigorous Claude-led workflow with research, deep questioning, detailed per-step planning, implementation, and Claude review gates.

**Codex policy:** Forge no longer uses Codex for plan reviews, per-step code reviews, regression reviews, document reviews, or final reviews. Codex may be used only as optional supplemental research when the CLI is available; its output is never a review gate.

**The Forge Process:**
1. **Intake** — Understand what to build
2. **Research** — 4 parallel Claude agents, with optional supplemental Codex research only
3. **Synthesis** — Combine research, extract questions
4. **Deep Questioning** — 10+ follow-up questions driven by research
5. **Master Plan** — Write `.forge/PLAN.md` with detailed plans for every implementation step
6. **Plan Approval** — Present the final plan summary and get user approval before implementation
7. **Implementation Loop** — For each step:
   a. Write or refresh the detailed step execution plan before touching implementation files
   b. Implement the step
   c. Run planned verification
   d. Stage specific files
   e. Claude sub-agent reviews the staged changes
   f. Fix reviewer findings and re-review if needed
   g. Commit
8. **Completion** — Final Claude review and wrap-up

**Output directory:** `.forge/` in the current project

**Canonical file names:**
Research dimensions are lowercase. User-facing documents are UPPERCASE. This is intentional — research files are machine-consumed, documents are human-consumed.

Research (lowercase):
- `.forge/research/stack.md`
- `.forge/research/pitfalls.md`
- `.forge/research/architecture.md`
- `.forge/research/prior-art.md`
- `.forge/research/codex-analysis.md` (optional supplemental research only)

Documents (UPPERCASE):
- `.forge/research/SYNTHESIS.md`
- `.forge/PLAN.md`
- `.forge/PROJECT.md`

Detailed step plans:
- `.forge/steps/step-{N}-plan.md`

Reviews (in `.forge/reviews/`):
- `.forge/reviews/claude-step-{N}.json`
- `.forge/reviews/final-claude-review.json`
</objective>

<critical_rules>

## Argument Disambiguation

**Arguments ALWAYS describe WHAT to build, never which forge phase to start at.**

If the user runs `/forge:build phase 5` or `/forge:build step 3`, the argument is the project task description — it means "build phase 5 of my project" or "build step 3 of my project." It does NOT mean "skip to forge process phase 5."

The forge process ALWAYS runs phases 1-8 sequentially. There is no skip mechanism.

To resume a previous run, the user must explicitly say "resume" or "continue where we left off."

## Stale Artifacts

If `.forge/` already exists from a previous run, **do not assume it applies to the current task.** At the start of every fresh invocation:

1. Check if `.forge/PROJECT.md` exists
2. Compare the existing PROJECT.md description against the new task argument
3. **If descriptions clearly differ:** auto-archive without asking. `mv .forge .forge.bak.$(date +%s)` and proceed fresh. Tell the user: "Auto-archived previous .forge/ (different task)."
4. **If descriptions look similar OR no new task argument provided:** ask the user whether to resume or start fresh
5. **Only ask once per session** — don't re-prompt on subsequent forge:build calls in the same session

Never silently reuse artifacts from an unrelated previous run.

## Minimal Mode

If the user runs `/forge:build --minimal` or the task is clearly trivial (one-line fix, dependency bump, single function rename, delete unused code), run a stripped-down workflow:

1. Skip Phase 2 (Research)
2. Skip Phase 3 (Synthesis)
3. Phase 4 (Questioning) reduced to 2-3 questions max
4. Phase 5 (Master Plan) becomes one detailed step with an explicit step execution plan
5. Phase 7 still does Claude sub-agent review for the change unless the user explicitly skips it
6. Phase 8 final review skipped if the single step review covers the full change

When in doubt, ask: "This looks like a trivial change (X lines). Use minimal mode (skip research/synthesis) or full forge?"

The full process is overkill for trivial fixes. Don't burn 30 minutes on research for "add a devDep and delete 14 lines."

</critical_rules>

<process>

## Phase 1: Intake

If the user provided a description via argument or @ file reference, read it. Otherwise ask:

Use AskUserQuestion:
- "What do you want to build?" — Free-form description with options for common project types

Then ask 2-3 immediate clarifying questions to understand the basics:
- Is this greenfield or adding to an existing project?
- What's the target platform/environment?
- Any hard constraints (language, framework, etc.)?

**CRITICAL: Detect deliverable type.** Ask the user (or infer from description):

Use AskUserQuestion:
- "What kind of deliverable is this?" with options:
  - **Code project** — Software with source files, tests, builds (default forge flow)
  - **Document** — Markdown, PRD, spec, brand guide, research report
  - **Hybrid** — Code with significant documentation deliverables

Save the answer to `.forge/PROJECT.md` as `Deliverable type: code|document|hybrid`. This determines how Phase 7 (Implementation Loop) operates — see the deliverable modes section.

Create the output directory and write project description:

```bash
mkdir -p .forge/research .forge/reviews .forge/steps

# Capture the starting point for final review diff
# Handle: not a git repo, repo with no commits, or normal repo
if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  git init
fi
if ! git rev-parse HEAD >/dev/null 2>&1; then
  git commit --allow-empty -m "forge: initialize repository"
fi
FORGE_BASE_REF=$(git rev-parse HEAD)
echo "$FORGE_BASE_REF" > .forge/.base-ref
```

Write `.forge/PROJECT.md`:

```markdown
# Forge Project

## Description
[user's description]

## Constraints
[any constraints mentioned]

## Context
- Greenfield/Brownfield: [answer]
- Platform: [answer]
- Deliverable type: code|document|hybrid
- Date: [today's date]
```

---

## Phase 2: Research

Run 4 Claude research tracks in parallel. Optional Codex research may run in parallel as supplemental context only; it is never a review step and failure must not block the workflow.

### Claude Research (4 parallel agents)

**WARNING: Do NOT use `isolation: "worktree"` for parallel agents.** Concurrent worktree spawns race on `~/.claude/` credential files causing auth failures. Use default isolation.

Spawn ALL 4 `forge-researcher` agents simultaneously in a single message:

```
Agent(
  subagent_type="forge-researcher",
  prompt="Mode: stack\n\n<project>\n[contents of .forge/PROJECT.md]\n</project>\n\nResearch the optimal tech stack for this project. Write findings to .forge/research/stack.md",
  description="Research: stack"
)

Agent(
  subagent_type="forge-researcher",
  prompt="Mode: pitfalls\n\n<project>\n[contents of .forge/PROJECT.md]\n</project>\n\nResearch common pitfalls for this type of project. Write findings to .forge/research/pitfalls.md",
  description="Research: pitfalls"
)

Agent(
  subagent_type="forge-researcher",
  prompt="Mode: architecture\n\n<project>\n[contents of .forge/PROJECT.md]\n</project>\n\nResearch architecture patterns for this project. Write findings to .forge/research/architecture.md",
  description="Research: architecture"
)

Agent(
  subagent_type="forge-researcher",
  prompt="Mode: prior-art\n\n<project>\n[contents of .forge/PROJECT.md]\n</project>\n\nResearch prior art and existing solutions. Write findings to .forge/research/prior-art.md",
  description="Research: prior-art"
)
```

### Optional Codex Research (supplemental only)

If `codex` is available and the user has not asked to avoid Codex entirely, run a single supplemental research pass. Treat this as one research source, not a gate:

```bash
set -o pipefail
codex exec --full-auto "Read .forge/PROJECT.md. Then write a concise research analysis to stdout. Do NOT review any code or plan. Do NOT search the web — analyze based on your training knowledge.

Cover these sections with specific, opinionated recommendations:
1. EXISTING SOLUTIONS — what open-source and commercial products exist in this space
2. RECOMMENDED STACK — specific libraries with versions, and what to avoid
3. ARCHITECTURE — how to structure the system, component boundaries, data flow
4. PITFALLS — domain-specific mistakes and how to prevent them
5. QUESTIONS — what you would ask before building this

Output ONLY your analysis text. No tool call logs, no search results, just the analysis." </dev/null 2>&1 | tee .forge/research/codex-analysis.raw
CODEX_EXIT=$?
```

Strip Codex CLI log noise and validate content:

```bash
grep -v -E '^(web search:|exec$|  succeeded|  failed|tokens used|/bin/zsh|Reading additional input|thinking|reasoning|workdir:|model:|provider:|approval:|sandbox:|^\[20|^\[Session|^\[Tool|user instructions|<files_to_read>)' .forge/research/codex-analysis.raw > .forge/research/codex-analysis.md 2>/dev/null
REAL_LINES=$(wc -l < .forge/research/codex-analysis.md 2>/dev/null || echo 0)
if [ "$CODEX_EXIT" -ne 0 ] || [ "$REAL_LINES" -lt 10 ]; then
  echo "CODEX_RESEARCH_FAILED — got $REAL_LINES lines of content"
  rm -f .forge/research/codex-analysis.md
fi
rm -f .forge/research/codex-analysis.raw
```

If Codex research fails, mark it as `missing` in the research status passed to the synthesizer and continue.

### Wait for research to complete

All 4 Claude research agents must finish before synthesis. Optional Codex research should finish if started, but it must not block if unavailable or invalid.

### Parse Agent Results

Each researcher returns a JSON block. Parse the `status` field:
- `"complete"` — research file written, extract `questions_for_user`
- `"incomplete"` — partial results, note `missing` fields
- `"blocked"` — no file written, note `blocker`

Collect all `questions_for_user` arrays from all researchers for the questioning phase.

---

## Phase 3: Synthesis

Build the research status summary from the agent returns, then spawn the synthesizer:

```
Agent(
  subagent_type="forge-synthesizer",
  prompt="<files_to_read>\n.forge/research/stack.md\n.forge/research/pitfalls.md\n.forge/research/architecture.md\n.forge/research/prior-art.md\n.forge/research/codex-analysis.md\n.forge/PROJECT.md\n</files_to_read>\n\n<research_status>\nstack: [complete|incomplete|blocked]\npitfalls: [complete|incomplete|blocked]\narchitecture: [complete|incomplete|blocked]\nprior-art: [complete|incomplete|blocked]\ncodex-analysis: [complete|missing]\n</research_status>\n\nSynthesize all available research into .forge/research/SYNTHESIS.md. Extract minimum 10 questions for the user. Codex analysis, if present, is supplemental research only and must not be treated as a review.",
  description="Synthesize research"
)
```

Parse the synthesizer's JSON return:
- `"complete"` — proceed to questioning with the `questions` array
- `"degraded"` — proceed but warn user about gaps
- `"insufficient"` — re-run failed researchers or fall back to manual questioning

---

## Phase 4: Deep Questioning

Present the user with questions from two sources:
1. Individual researcher `questions_for_user` arrays
2. Synthesizer `questions` array (deduplicated, prioritized)

Use AskUserQuestion for structured questions. Rules:

- Ask AT MINIMUM 10 questions — often 12-15 is appropriate
- Group by category: scope, technical, ux, constraints, risk, prior-art
- Ask in batches of 3-4 using AskUserQuestion (max 4 per call)
- Include the `why` context and `default_recommendation` from the question objects
- After each batch, assess whether more questions are needed
- If the user's answer raises new questions, ask those too
- Don't rush this phase — thoroughness here prevents rework later

After all questions are answered, update `.forge/PROJECT.md` with:
- All Q&A pairs
- Refined project understanding
- Decisions made

---

## Phase 5: Master Plan

Based on PROJECT.md (with all Q&A) and SYNTHESIS.md, write `.forge/PLAN.md`.

**CRITICAL: The master plan must contain longer, execution-ready plans for every step before implementation starts.** Do not write placeholder steps. Do not proceed to implementation with steps that only say "implement X." Each step must be detailed enough that a separate implementer could execute it without asking what to do next.

Use this structure:

```markdown
# Forge Implementation Plan

## Overview
[What we're building, one paragraph]

## Technical Decisions
[Stack, architecture, key libraries — decided from research + questions]
[Reference ITEM IDs from research for traceability]

## Implementation Steps

### Step 1: [Name]
**Goal:** [user-visible or system-level outcome]
**Why now:** [why this step is ordered here]
**Dependencies:** [previous steps, packages, migrations, assets, decisions]
**Files:** [files to create/modify/delete]
**Existing code to inspect first:** [specific files, symbols, routes, components, tests]
**Implementation plan:**
1. [Concrete sub-action]
2. [Concrete sub-action]
3. [Concrete sub-action]
4. [Concrete sub-action]
5. [Concrete sub-action]
**Contracts and interfaces:** [APIs, props, data shapes, config keys, CLI flags]
**State/data changes:** [schema, persistence, cache, migration, fixture changes]
**Edge cases:** [specific cases this step must handle]
**Acceptance criteria:** [observable outcomes]
**Verification commands:** [exact tests/builds/lints/manual checks]
**Manual validation:** [browser/API/CLI flow to exercise]
**Risks:** [real, verified pitfalls from research or codebase checks, with ITEM IDs]
**Out of scope for this step:** [explicit exclusions]

### Step 2: [Name]
...

## Cross-Step Integration Checks
[Checks that only make sense after multiple steps are assembled]

## Testing Strategy
[How we'll verify the implementation overall]

## Out of Scope
[What we're explicitly NOT doing]
```

**Plan quality requirements:**
- Each step must include at least 5 concrete implementation sub-actions unless the step is intentionally tiny and marked as such
- Each step must list exact files or file patterns and existing code to inspect first
- Each step must define contracts/interfaces when the step changes behavior across boundaries
- Each step must include step-level verification commands and at least one acceptance criterion
- Each step should be small enough to implement and review in one cycle, but detailed enough to prevent ambiguity
- Risks from pitfalls research should be mapped to relevant steps with ITEM IDs
- Prior art leverage opportunities should be noted with ITEM IDs
- The plan must call out cross-step integration checks separately from per-step verification

**CRITICAL: Verify before manufacturing risks.** Before adding a "Risks" or "Fallback" item to a step, run a quick grep/find to check whether the risk is real. Examples:
- Don't add "if vitest setup doesn't work, defer the test" without first checking whether tests already work in the repo
- Don't add "if the build breaks" caveats without checking what the build actually does
- Don't speculate about library compatibility without checking package.json

**5 seconds of grep beats 5 minutes of fallback planning.** Speculative risks bloat the plan and waste implementation time.

---

## Phase 6: Plan Approval

Before implementing, present the user with a concise summary of the final `.forge/PLAN.md`:
- Number of steps
- The goal of each step
- Key files or subsystems touched
- Highest-risk items and how the plan handles them
- Verification strategy

Use AskUserQuestion:
- "The plan has [N] detailed steps and no Codex review gates. Ready to implement?" with options: "Yes, start building" / "I have changes" / "Show me the full plan first"

If the user asks for changes, update `.forge/PLAN.md`, then ask again.

---

## Phase 7: Implementation Loop

**Branches based on deliverable type from Phase 1.** Read `.forge/PROJECT.md` for the `Deliverable type` field.

### 7a. Step Execution Plan (required before each step)

Before touching implementation files for step N, write `.forge/steps/step-{N}-plan.md`. This is a focused execution plan derived from `.forge/PLAN.md` and current codebase state.

The step execution plan must include:

```markdown
# Step N Execution Plan: [Name]

## Goal
[Specific outcome for this step]

## Current Code Observations
[What was found after reading the files listed in the master plan]

## Files to Change
- [path] — [intended change]

## Ordered Implementation Checklist
1. [Small concrete action]
2. [Small concrete action]
3. [Small concrete action]
4. [Small concrete action]
5. [Small concrete action]

## Interfaces and Data Contracts
[Exact signatures, props, schema, route contracts, CLI flags, config keys]

## Verification Plan
- Automated: [commands]
- Manual: [specific flow]
- Regression: [what existing behavior must still work]

## Stop Conditions
[Cases where implementation should pause and ask user instead of improvising]
```

Rules:
- Read the existing files named in the master plan before writing this step plan
- Include at least 5 ordered checklist items unless the step is intentionally tiny
- If current code contradicts `.forge/PLAN.md`, update `.forge/PLAN.md` or ask the user before implementing
- Do not use this file for speculative future work; keep it tied to the current step

### Deliverable Mode: code (default)

For code projects, each step = a unit of code change. Loop:

### 7b. Implement (code mode)

Implement the step from `.forge/steps/step-{N}-plan.md`. Write code using Write/Edit tools. Keep changes scoped to the current step.

### 7c. Verify (code mode)

Run the verification commands from the step execution plan. For UI/frontend changes, start the dev server and use the feature in a browser before reporting the step complete. Monitor console/network errors and test golden paths plus relevant edge cases.

If verification fails, fix the issue before review. If the fix requires changing the step scope or the master plan, update `.forge/PLAN.md` and ask the user before proceeding.

### Deliverable Mode: document

For document projects (PRD, spec, brand guide, research report), each step = one section of the document.

### 7b. Write/edit (document mode)

Use Write/Edit to draft the section specified by the step execution plan.

### 7c. Section consistency check (document mode)

After each section, read the new section and earlier related sections yourself. Check for contradictions in dates, scope, definitions, decisions, numbers, and terminology. Fix contradictions before review.

No commit per section unless the user wants section-level commits — the document is usually one artifact.

### Deliverable Mode: hybrid

Use code mode for source files, document mode for documentation deliverables. Decide per plan step which mode applies based on what the step produces.

### 7d. Claude Sub-Agent Review

Stage the changes first, then spawn the reviewer with an explicit file list AND the specific plan step text and execution plan (not just the step number):

```bash
git add [specific files from this step]
```

```
Agent(
  subagent_type="forge-reviewer",
  prompt="<files_to_read>\n.forge/PLAN.md\n.forge/steps/step-[N]-plan.md\n</files_to_read>\n\n<plan_step>\n### Step [N]: [step name]\n[copy full step from PLAN.md]\n</plan_step>\n\n<changed_files>\n[list of files changed in this step]\n</changed_files>\n\n<verification_performed>\n[commands/manual checks run and outcomes]\n</verification_performed>\n\nReview the current staged changes against the master plan and step execution plan. There is no Codex review for this workflow. Your focus includes correctness, security, performance, plan alignment, code quality, completeness, patterns, and integration.",
  description="Review step [N]"
)
```

**Save the reviewer output** to `.forge/reviews/claude-step-[N].json` using the Write tool after parsing the JSON return.

Parse the reviewer's JSON return:
- `"APPROVED"` — proceed to commit
- `"CHANGES_REQUESTED"` — fix the `required_changes`, then re-run reviewer

### 7e. Address Sub-Agent Findings

If the forge-reviewer returns `CHANGES_REQUESTED`:
1. Fix each item in `required_changes`
2. Re-run relevant verification commands
3. Re-stage changes
4. Re-run the Claude reviewer
5. Maximum 2 re-review cycles per step; after that, ask the user how to proceed

### 7f. Commit

**Pre-check commit message format.** Before invoking `git commit`, check the project for commitlint config (`commitlint.config.js`, `.commitlintrc*`, `commitlint` field in `package.json`). If found, validate your commit message subject against common rules:

- Conventional commits format: `type(scope): subject`
- Lowercase subject (no `Add`, only `add`)
- No period at end
- Subject under 100 chars

Failing commits because of commitlint mid-implementation wastes time. Pre-validate.

Before committing, run any project formatters/linters to avoid pre-commit hook failures:

```bash
# Detect and run formatters before committing (avoids hook churn)
# Check for common formatter configs and run them on staged files
if [ -f .prettierrc ] || [ -f .prettierrc.json ] || [ -f prettier.config.js ]; then
  npx prettier --write $(git diff --cached --name-only) 2>/dev/null || true
fi
if [ -f .eslintrc ] || [ -f .eslintrc.json ] || [ -f eslint.config.js ]; then
  npx eslint --fix $(git diff --cached --name-only) 2>/dev/null || true
fi
if [ -f pyproject.toml ] && grep -q "ruff\|black" pyproject.toml 2>/dev/null; then
  ruff format $(git diff --cached --name-only) 2>/dev/null || black $(git diff --cached --name-only) 2>/dev/null || true
fi
# Re-stage after formatting
git add $(git diff --cached --name-only)
```

Then commit:

```bash
git commit -m "forge: step [N] — [step name]"
```

**If the commit fails due to pre-commit hooks:**
1. Read the hook error output
2. Fix the issue (usually formatting or lint)
3. Re-stage the files: `git add [files]`
4. Retry the commit (do NOT use `--no-verify`)
5. If the hook fails again with different issues, fix those too (max 3 attempts)

### Repeat for each plan step.

---

## Phase 8: Completion

After all steps are implemented:

1. Run final verification from `.forge/PLAN.md`.

2. Run a final Claude sub-agent review on the complete project. Save the output to `.forge/reviews/final-claude-review.json`.

   Prompt shape:

   ```
   Agent(
     subagent_type="forge-reviewer",
     prompt="<files_to_read>\n.forge/PLAN.md\n.forge/PROJECT.md\n</files_to_read>\n\n<review_scope>\nFull project changes since base ref: [base ref from .forge/.base-ref]\n</review_scope>\n\n<verification_performed>\n[final verification commands/manual checks and outcomes]\n</verification_performed>\n\nReview the full completed project against the plan. There is no Codex review for this workflow. Check integration issues between steps, missing requirements, correctness, security, performance, maintainability, and anything that doesn't match the plan.",
     description="Final Forge review"
   )
   ```

   If the final Claude review returns `CHANGES_REQUESTED`:
   - Fix the required changes
   - Re-run relevant verification
   - Re-run the final Claude review
   - Maximum 2 final re-review cycles — escalate to user after that

3. Show the user a summary:
   - What was built
   - How many steps completed
   - Key decisions made
   - Verification performed
   - Any deferred items or known limitations

4. Ask if they want to:
   - Create a PR
   - Continue with additional features
   - Done

</process>

<rules>

## Orchestration Rules

1. **Never rush questioning.** Minimum 10 questions (5 in degraded mode). If research raised complex topics, ask more.
2. **Research before opinions.** Don't form views about stack/architecture until research is done.
3. **No Codex reviews.** Do not run Codex plan review, step review, regression review, document review, or final review.
4. **Detailed step plans before implementation.** Every implementation step must have both a detailed section in `.forge/PLAN.md` and a `.forge/steps/step-{N}-plan.md` written before code/document edits for that step.
5. **Plan changes need user approval.** If implementation discoveries cause significant plan changes, confirm with user.
6. **Small commits.** Each plan step = one commit for code projects. Don't bundle multiple steps.
7. **Track everything.** All reviews saved to `.forge/reviews/`. All research to `.forge/research/`. All step execution plans to `.forge/steps/`.
8. **Parse JSON returns.** Agent returns are JSON — parse the `status`/`verdict` field to determine next action.
9. **Handle degraded states.** If research is incomplete or blocked, proceed with warnings rather than failing entirely.
10. **Stage before review.** Always `git add` specific files before running the forge-reviewer, so it has a clear diff to review.
11. **Save all review artifacts.** Claude reviewer JSON → `.forge/reviews/claude-step-{N}.json` and `.forge/reviews/final-claude-review.json`.

## Review Gate Policy (precedence order)

The review gate is Claude-only:

1. **Default: Claude sub-agent review required.** The forge-reviewer must review before commit.
2. **Reviewer unavailable or repeatedly malformed:** Ask the user whether to retry, proceed with manual review, or pause. Do not silently skip.
3. **User explicitly requests skip:** Allow it. Warn: "Skipping review for step [N]. Risk accepted by user." Record in the commit message: `forge: step [N] — [name] (review skipped by user request)`.

The user can always override, but the system defaults to reviewed commits.

## File Structure

```
.forge/
  PROJECT.md                 # Project description + Q&A
  PLAN.md                    # Master implementation plan with detailed per-step plans
  .base-ref                  # Base commit for final review scope
  research/
    stack.md                 # Tech stack research
    pitfalls.md              # Pitfalls research
    architecture.md          # Architecture research
    prior-art.md             # Prior art research
    codex-analysis.md        # Optional supplemental Codex research, not a review
    SYNTHESIS.md             # Combined synthesis
  steps/
    step-1-plan.md           # Focused execution plan written before step 1 implementation
  reviews/
    claude-step-1.json       # Claude reviewer JSON output per step
    final-claude-review.json # Final full review
```

## Error Recovery

- If a researcher agent returns `"blocked"`, re-run just that one
- If optional Codex research is unavailable, mark `codex-analysis` as missing and continue
- If synthesizer returns `"insufficient"`, re-run failed researchers before trying again
- If current code contradicts a planned step, update the step plan and, when scope changes, update `.forge/PLAN.md` and re-confirm with user
- If a review cycle finds fundamental issues, update the plan and re-confirm with user before continuing
- If the user wants to skip a review, follow Review Gate Policy precedence (rule 3)
- Maximum 2 re-review cycles per implementation step — if still failing, ask the user

## Optional Codex Research Reliability

Codex is supplemental research only. If used, follow these practices:

**Use `codex exec --full-auto`; never use Codex review commands.** Forge must not invoke `codex review` or use Codex as a plan/code review gate.

**ALWAYS pipe `</dev/null` to Codex commands.** Codex `exec` can hang waiting for stdin if no input is piped in.

**Strip log noise aggressively.** Codex exec may produce tool logs, file echoes, session preambles, and thinking blocks. Always filter before saving `.forge/research/codex-analysis.md`.

**Validate content, not just exit code.** Even with exit code 0, Codex may produce only log noise. Check that cleaned output has >10 substantive lines before treating it as present. Mark as `missing` and proceed in degraded mode if validation fails.

**Never use `run_in_background: true` for Codex commands.** If the command is run, it must complete before synthesis uses the optional file.

## Agent JSON Return Validation

LLM JSON output fails non-deterministically at different character positions across retries. Do NOT rely on simple retry logic.

**When parsing agent returns:**
1. Extract the fenced `json` block from the agent's output
2. Attempt `JSON.parse` / manual parsing
3. If parse fails, look for the key routing fields (`status`, `verdict`) via regex as fallback
4. If both fail, treat as `"blocked"` / `"CHANGES_REQUESTED"` (fail-safe, not fail-open)

**Never trust retry alone** — the same agent with the same prompt can produce differently-malformed JSON each time.

## Parallel Agent Safety

**Never use `isolation: "worktree"`** for forge research agents. Concurrent worktree spawns race on `~/.claude/` credential files causing auth failures. Use default isolation.

## Content Filter Workaround

The Write tool can hit content filtering on certain text — license bodies (BUSL-1.1, MIT, Apache, Contributor Covenant), CLA text, security disclosure templates. If `Write` fails with a content filter error, fall back to writing via Bash heredoc:

```bash
cat > path/to/LICENSE << 'EOF'
[license text]
EOF
```

The single-quoted heredoc delimiter prevents shell interpolation. Don't try to retry the Write tool — it will fail again with the same content. Go straight to the heredoc workaround.

## Per-Step Review Coverage Caveat

Claude per-step review primarily sees the current staged diff. It may miss issues that only appear after multiple steps are assembled:
- SSR/hydration regressions that only manifest at runtime
- Cross-component state contract violations
- Framework lifecycle assumption mismatches
- Integration issues between sequential commits

These are caught by:
1. The **Cross-Step Integration Checks** in `.forge/PLAN.md`
2. The **Final Claude review** in Phase 8
3. Manual/browser verification for UI work

Do not skip Phase 8 for multi-step projects.

## Plan Refinement Loop Cap

Plan refinement can ping-pong indefinitely. Cap rounds:

- **Max 2 plan refinement rounds** after user feedback. After that, present remaining tradeoffs to the user and ask whether to address or accept.
- **Max 2 final review rounds**. After that, surface remaining findings to the user.

Each round catches real issues but marginal value diminishes. Don't loop forever on cosmetic concerns.

</rules>
