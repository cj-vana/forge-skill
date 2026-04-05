---
name: forge:build
description: Dual-model build workflow — research, deep questioning, plan, implement with Claude + Codex review gates
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
Build software through a rigorous dual-model workflow combining Claude and Codex (GPT-5.4).

**The Forge Process:**
1. **Intake** — Understand what to build
2. **Research** — 4 parallel Claude agents + Codex research (stack, pitfalls, architecture, prior-art)
3. **Synthesis** — Combine research, extract questions
4. **Deep Questioning** — 10+ follow-up questions driven by research
5. **Plan** — Write implementation plan
6. **Codex Plan Review** — Codex reviews the plan adversarially
7. **Plan Refinement** — Update plan based on Codex review, ask clarifying questions
8. **Implementation Loop** — For each change:
   a. Claude implements
   b. Codex reviews (adversarial)
   c. Fix Codex findings
   d. Claude sub-agent reviews (holistic)
   e. Fix sub-agent findings
   f. Commit
9. **Completion** — Final dual-review and wrap-up

**Output directory:** `.forge/` in the current project

**Canonical file names:**
Research dimensions are lowercase. User-facing documents are UPPERCASE. This is intentional — research files are machine-consumed, documents are human-consumed.

Research (lowercase):
- `.forge/research/stack.md`
- `.forge/research/pitfalls.md`
- `.forge/research/architecture.md`
- `.forge/research/prior-art.md`
- `.forge/research/codex-analysis.md`

Documents (UPPERCASE):
- `.forge/research/SYNTHESIS.md`
- `.forge/PLAN.md`
- `.forge/PROJECT.md`

Reviews (in `.forge/reviews/`):
- `.forge/reviews/codex-plan-review.md`
- `.forge/reviews/codex-step-{N}.md`
- `.forge/reviews/claude-step-{N}.json`
- `.forge/reviews/final-codex-review.md`
</objective>

<critical_rules>

## Argument Disambiguation

**Arguments ALWAYS describe WHAT to build, never which forge phase to start at.**

If the user runs `/forge:build phase 5` or `/forge:build step 3`, the argument is the project task description — it means "build phase 5 of my project" or "build step 3 of my project." It does NOT mean "skip to forge process phase 5."

The forge process ALWAYS runs phases 1-9 sequentially. There is no skip mechanism.

To resume a previous run, the user must explicitly say "resume" or "continue where we left off."

## Stale Artifacts

If `.forge/` already exists from a previous run, **do not assume it applies to the current task.** At the start of every fresh invocation:

1. Check if `.forge/PROJECT.md` exists
2. If it does, ask the user: "Found existing .forge/ artifacts from a previous run. Start fresh (clear .forge/) or resume the previous build?"
3. If starting fresh, move the old directory: `mv .forge .forge.bak.$(date +%s)`

Never silently reuse artifacts from a previous run.

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

Create the output directory and write project description:

```bash
mkdir -p .forge/research .forge/reviews

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
- Date: [today's date]
```

---

## Phase 2: Research

Run 5 research tracks in parallel — 4 Claude agents + 1 Codex research.

### Claude Research (4 parallel agents)

**WARNING: Do NOT use `isolation: "worktree"` for parallel agents.** Concurrent worktree spawns race on `~/.claude/` credential files causing ~50% auth failures. Use default isolation (shared repo).

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

### Codex Research (parallel with Claude agents)

Run Codex research as a foreground Bash command (NOT background — must complete before synthesis):

```bash
set -o pipefail
codex exec --full-auto "Read .forge/PROJECT.md. Then write a comprehensive research analysis to stdout. Do NOT search the web — analyze based on your training knowledge.

Cover these sections with specific, opinionated recommendations:
1. EXISTING SOLUTIONS — what open-source and commercial products exist in this space
2. RECOMMENDED STACK — specific libraries with versions, and what to avoid
3. ARCHITECTURE — how to structure the system, component boundaries, data flow
4. PITFALLS — domain-specific mistakes and how to prevent them
5. QUESTIONS — what you would ask before building this

Output ONLY your analysis text. No tool call logs, no search results, just the analysis." 2>&1 | tee .forge/research/codex-analysis.raw
CODEX_EXIT=$?
```

**IMPORTANT:** Codex `exec` often produces log noise (`web search:`, `exec\n`, tool call traces) mixed with real content. Strip logs and validate:

```bash
# Strip codex log noise — keep only substantive lines
grep -v -E '^(web search:|exec$|  succeeded|  failed|tokens used|/bin/zsh)' .forge/research/codex-analysis.raw > .forge/research/codex-analysis.md 2>/dev/null

# Validate: must have real content (>10 substantive lines), not just logs
REAL_LINES=$(wc -l < .forge/research/codex-analysis.md 2>/dev/null || echo 0)
if [ "$CODEX_EXIT" -ne 0 ] || [ "$REAL_LINES" -lt 10 ]; then
  echo "CODEX_RESEARCH_FAILED — got $REAL_LINES lines of content"
  rm -f .forge/research/codex-analysis.md
fi
rm -f .forge/research/codex-analysis.raw
```

If codex research fails or produces only logs, mark it as `missing` in the research status passed to the synthesizer.

### Wait for ALL research to complete

ALL 5 research tracks (4 Claude agents + 1 Codex) must finish before proceeding to synthesis. Do not start Phase 3 until every agent has returned and the codex command has completed.

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
  prompt="<files_to_read>\n.forge/research/stack.md\n.forge/research/pitfalls.md\n.forge/research/architecture.md\n.forge/research/prior-art.md\n.forge/research/codex-analysis.md\n.forge/PROJECT.md\n</files_to_read>\n\n<research_status>\nstack: [complete|incomplete|blocked]\npitfalls: [complete|incomplete|blocked]\narchitecture: [complete|incomplete|blocked]\nprior-art: [complete|incomplete|blocked]\ncodex-analysis: [complete|missing]\n</research_status>\n\nSynthesize all available research into .forge/research/SYNTHESIS.md. Extract minimum 10 questions for the user.",
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

## Phase 5: Write Plan

Based on PROJECT.md (with all Q&A) and SYNTHESIS.md, write `.forge/PLAN.md`:

```markdown
# Forge Implementation Plan

## Overview
[What we're building, one paragraph]

## Technical Decisions
[Stack, architecture, key libraries — decided from research + questions]
[Reference ITEM IDs from research for traceability]

## Implementation Steps

### Step 1: [Name]
**What:** [description]
**Files:** [files to create/modify]
**Acceptance:** [how to verify this step is done]
**Risks:** [pitfalls from research that apply here, with ITEM IDs]

### Step 2: [Name]
...

## Testing Strategy
[How we'll verify the implementation]

## Out of Scope
[What we're explicitly NOT doing]
```

**Plan quality requirements:**
- Each step should be small enough to implement and review in one cycle
- Steps should have clear acceptance criteria
- Risks from pitfalls research should be mapped to relevant steps with ITEM IDs
- Prior art leverage opportunities should be noted with ITEM IDs

---

## Phase 6: Codex Plan Review

Submit the plan to Codex for adversarial review:

Write the plan and synthesis content to a temporary review prompt file, then pass it to codex:

```bash
set -o pipefail
cat > /tmp/forge-plan-review-prompt.md << 'PROMPT_END'
You are reviewing an implementation plan. Be adversarial — challenge assumptions, find gaps, identify risks the plan doesn't address, and suggest improvements.

Review dimensions:
1. Completeness — does it cover everything needed?
2. Ordering — are steps in the right sequence?
3. Risk coverage — are researched pitfalls addressed?
4. Feasibility — can each step actually be done as described?
5. Acceptance criteria — are they specific enough to verify?
6. Missing steps — what did the plan forget?

Be specific. Reference step numbers. Suggest exact changes. Output ONLY your review findings as structured text — no tool call logs.
PROMPT_END

codex exec --full-auto "Read .forge/PLAN.md and .forge/research/SYNTHESIS.md. Then read /tmp/forge-plan-review-prompt.md for your review instructions. Output your review to stdout." 2>&1 | grep -v -E '^(web search:|exec$|  succeeded|  failed|tokens used|/bin/zsh)' | tee .forge/reviews/codex-plan-review.md
rm -f /tmp/forge-plan-review-prompt.md
```

---

## Phase 7: Plan Refinement

Read the Codex plan review. For each finding:

1. **If the finding is valid:** Update PLAN.md to address it
2. **If the finding needs user input:** Ask the user via AskUserQuestion
3. **If the finding is wrong:** Note why in the plan as a considered-and-rejected item

After addressing all Codex findings, ask the user 2-3 follow-up questions about any plan changes that affect scope or approach.

Show the user the final plan summary and get approval before proceeding:

Use AskUserQuestion:
- "The plan has [N] steps. Codex suggested [M] changes, [X] were incorporated. Ready to implement?" with options: "Yes, start building" / "I have changes" / "Show me the full plan first"

---

## Phase 8: Implementation Loop

For each step in the plan:

### 8a. Implement

Implement the step. Write code using Write/Edit tools. Follow the plan's specifications for this step.

### 8b. Codex Review

After implementing, run Codex adversarial review on the changes. **Do NOT use `codex review --uncommitted "prompt"` — it doesn't accept a prompt argument.** Use `codex exec` with the diff piped in instead:

```bash
mkdir -p .forge/reviews
set -o pipefail
git diff > /tmp/forge-step-diff.patch
codex exec --full-auto "Review this code diff for: bugs, security issues, performance problems, edge cases. Also check if it matches this plan step:

[paste relevant plan step text here]

The diff is in /tmp/forge-step-diff.patch — read it and provide your review. Output ONLY structured review findings, no tool call logs." 2>&1 | grep -v -E '^(web search:|exec$|  succeeded|  failed|tokens used|/bin/zsh)' | tee .forge/reviews/codex-step-[N].md
rm -f /tmp/forge-step-diff.patch
```

### 8c. Address Codex Findings

Read the Codex review. Fix any issues found. If Codex identified something that requires a plan change, note it.

### 8d. Claude Sub-Agent Review

Stage the changes first, then spawn the reviewer with an explicit file list AND the specific plan step text (not just the step number):

```bash
git add [specific files from this step]
```

Extract the specific plan step text from PLAN.md for the reviewer:

```
Agent(
  subagent_type="forge-reviewer",
  prompt="<files_to_read>\n.forge/PLAN.md\n</files_to_read>\n\n<plan_step>\n### Step [N]: [step name]\n**What:** [copied from PLAN.md]\n**Files:** [copied from PLAN.md]\n**Acceptance:** [copied from PLAN.md]\n**Risks:** [copied from PLAN.md]\n</plan_step>\n\n<changed_files>\n[list of files changed in this step]\n</changed_files>\n\nReview the current staged changes against the plan step above.\n\nCodex already reviewed and the following was addressed: [summary of codex findings].\n\nYour focus: plan alignment, code quality, completeness, patterns, integration.",
  description="Review step [N]"
)
```

**Save the reviewer output** to `.forge/reviews/claude-step-[N].json` using the Write tool after parsing the JSON return.

Parse the reviewer's JSON return:
- `"APPROVED"` — proceed to commit
- `"CHANGES_REQUESTED"` — fix the `required_changes`, then re-run reviewer

### 8e. Address Sub-Agent Findings

If the forge-reviewer returns `CHANGES_REQUESTED`:
1. Fix each item in `required_changes`
2. Re-stage changes
3. **Re-run BOTH reviews** (Codex + Claude) — post-fix edits may have introduced new issues that Codex would catch. This maintains the dual-review guarantee.
4. Maximum 2 full re-review cycles per step (each cycle = Codex review + Claude review)

### 8f. Commit

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

## Phase 9: Completion

After all steps are implemented:

1. Run a final Codex review on the entire changeset:

```bash
FORGE_BASE=$(cat .forge/.base-ref 2>/dev/null)
set -o pipefail
if [ -n "$FORGE_BASE" ] && git cat-file -t "$FORGE_BASE" >/dev/null 2>&1; then
  git diff "$FORGE_BASE"..HEAD > /tmp/forge-final-diff.patch
  codex exec --full-auto "Read /tmp/forge-final-diff.patch and .forge/PLAN.md. Review the full changeset for: integration issues between steps, missing error handling, security vulnerabilities, and anything that doesn't match the plan. Output ONLY your review findings." 2>&1 | grep -v -E '^(web search:|exec$|  succeeded|  failed|tokens used|/bin/zsh)' | tee .forge/reviews/final-codex-review.md
  rm -f /tmp/forge-final-diff.patch
else
  codex exec --full-auto "Review the entire codebase and .forge/PLAN.md for: integration issues between components, missing error handling, security vulnerabilities, and anything that doesn't match the plan. Output ONLY your review findings." 2>&1 | grep -v -E '^(web search:|exec$|  succeeded|  failed|tokens used|/bin/zsh)' | tee .forge/reviews/final-codex-review.md
fi
```

2. If the final Codex review finds issues, address them through the **full dual-review loop** (steps 8b-8f). Final review findings are not exempt from the dual-review guarantee.

3. Run a final Claude sub-agent review on the complete project. Save the output to `.forge/reviews/final-claude-review.json`.

   If the final Claude review returns `CHANGES_REQUESTED`:
   - Fix the required changes
   - Re-run **both** Codex and Claude final reviews (same dual-review loop)
   - Maximum 2 final re-review cycles — escalate to user after that

4. Show the user a summary:
   - What was built
   - How many steps completed
   - Key decisions made
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
3. **Codex findings are serious.** Don't dismiss Codex review findings without explanation.
4. **Plan changes need user approval.** If Codex review causes significant plan changes, confirm with user.
5. **Small commits.** Each plan step = one commit. Don't bundle multiple steps.
6. **Track everything.** All reviews saved to `.forge/reviews/`. All research to `.forge/research/`.
7. **Parse JSON returns.** Agent returns are JSON — parse the `status`/`verdict` field to determine next action.
8. **Handle degraded states.** If research is incomplete or blocked, proceed with warnings rather than failing entirely.
9. **Stage before review.** Always `git add` specific files before running the forge-reviewer, so it has a clear diff to review.
10. **Save all review artifacts.** Codex reviews → `.forge/reviews/codex-step-{N}.md`. Claude reviewer JSON → `.forge/reviews/claude-step-{N}.json`.

## Review Gate Policy (precedence order)

The review gate has a clear precedence hierarchy:

1. **Default: Dual review required.** Both Codex + Claude sub-agent must review before commit.
2. **Codex unavailable:** Fall back to Claude-only review. Warn the user: "Codex unavailable — proceeding with single-model review. This reduces coverage." Log the degraded state.
3. **User explicitly requests skip:** Allow it. Warn: "Skipping review for step [N]. Risk accepted by user." Record in the commit message: `forge: step [N] — [name] (review skipped by user request)`.

The user can always override, but the system defaults to maximum review coverage.

## File Structure

```
.forge/
  PROJECT.md                 # Project description + Q&A
  PLAN.md                    # Implementation plan
  research/
    stack.md                 # Tech stack research
    pitfalls.md              # Pitfalls research
    architecture.md          # Architecture research
    prior-art.md             # Prior art research
    codex-analysis.md        # Codex's parallel research
    SYNTHESIS.md             # Combined synthesis
  reviews/
    codex-plan-review.md     # Codex's review of the plan
    codex-step-1.md          # Codex review per step
    claude-step-1.json       # Claude reviewer JSON output per step
    final-codex-review.md    # Final full review
```

## Error Recovery

- If a researcher agent returns `"blocked"`, re-run just that one
- If Codex is unavailable, follow Review Gate Policy precedence (rule 2)
- If synthesizer returns `"insufficient"`, re-run failed researchers before trying again
- If a review cycle finds fundamental issues, update the plan and re-confirm with user before continuing
- If the user wants to skip a review, follow Review Gate Policy precedence (rule 3)
- Maximum 2 re-review cycles per implementation step — if still failing, ask the user

## Codex CLI Reliability

Codex `exec` has known issues in headless mode. Follow these practices:

**Always use `codex exec --full-auto`, never `codex review` with custom prompts.** The `codex review --uncommitted "prompt"` syntax is invalid — codex review doesn't accept a trailing prompt argument. Instead, use `codex exec --full-auto` with the diff saved to a file and explicit review instructions.

**Strip log noise from output.** Codex exec frequently produces `web search:`, `exec`, `succeeded`, `tokens used` log lines mixed with real content. Always pipe through:
```bash
grep -v -E '^(web search:|exec$|  succeeded|  failed|tokens used|/bin/zsh)' output.raw > output.clean
```

**Validate content, not just exit code.** Even with exit code 0, codex may produce only log noise. Check that the cleaned output has >10 substantive lines before treating it as valid.

**Never use `run_in_background: true` for codex commands.** Codex commands go to background unpredictably when invoked from Claude Code Bash. This breaks the "all research must complete before synthesis" requirement. Always run codex as foreground commands and wait for completion before proceeding.

**Retry with backoff:** Codex has a 60-second default timeout that causes silent failures. If a codex command fails or returns empty:
```bash
for attempt in 1 2 3; do
  result=$(codex exec --full-auto "..." 2>&1) && break
  sleep $((attempt * 5))
done
```

**Keep prompts concise:** Codex auto-compaction is broken in `exec` mode (openai/codex#16033). Long context accumulates until crash. Use `--full-auto` instead of `--ephemeral`. For reviews, save the diff to a temp file and tell codex to read it, rather than inlining the diff in the prompt.

## Agent JSON Return Validation

LLM JSON output fails non-deterministically at different character positions across retries. Do NOT rely on simple retry logic.

**When parsing agent returns:**
1. Extract the fenced `json` block from the agent's output
2. Attempt `JSON.parse` / manual parsing
3. If parse fails, look for the key routing fields (`status`, `verdict`) via regex as fallback
4. If both fail, treat as `"blocked"` / `"CHANGES_REQUESTED"` (fail-safe, not fail-open)

**Never trust retry alone** — the same agent with the same prompt can produce differently-malformed JSON each time.

## Parallel Agent Safety

**Never use `isolation: "worktree"`** for forge research agents. Concurrent worktree spawns race on `~/.claude/` credential files causing ~50% auth failures (anthropics/claude-code#37324). Use default isolation.

</rules>
