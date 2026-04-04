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

**Canonical file names (lowercase everywhere):**
- `.forge/research/stack.md`
- `.forge/research/pitfalls.md`
- `.forge/research/architecture.md`
- `.forge/research/prior-art.md`
- `.forge/research/codex-analysis.md`
- `.forge/research/SYNTHESIS.md`
- `.forge/PLAN.md`
- `.forge/PROJECT.md`
</objective>

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

Simultaneously run Codex research in background:

```bash
codex exec "Research this project idea and write a comprehensive analysis. Focus on: what exists already, what tech stack is standard for this in 2025/2026, what mistakes teams commonly make, and how to architect it well.

Project description:
$(cat .forge/PROJECT.md)

Write your analysis covering:
1. Existing solutions and prior art
2. Recommended tech stack with versions
3. Architecture patterns
4. Common pitfalls and how to avoid them
5. Questions you'd ask before building this

Be specific and opinionated." 2>&1 | tee .forge/research/codex-analysis.md
```

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

```bash
codex exec "You are reviewing an implementation plan. Be adversarial — challenge assumptions, find gaps, identify risks the plan doesn't address, and suggest improvements. Be specific about what's wrong and how to fix it.

$(cat .forge/PLAN.md)

Context from research:
$(cat .forge/research/SYNTHESIS.md)

Review the plan on these dimensions:
1. Completeness — does it cover everything needed?
2. Ordering — are steps in the right sequence?
3. Risk coverage — are researched pitfalls addressed?
4. Feasibility — can each step actually be done as described?
5. Acceptance criteria — are they specific enough to verify?
6. Missing steps — what did the plan forget?

Be specific. Reference step numbers. Suggest exact changes." 2>&1 | tee .forge/CODEX-PLAN-REVIEW.md
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

After implementing, run Codex adversarial review on the changes:

```bash
mkdir -p .forge/reviews
codex review --uncommitted "Focus on: bugs, security issues, performance problems, edge cases. Also check if this matches the plan step it's supposed to implement. Plan step context: [paste relevant plan step]" 2>&1 | tee .forge/reviews/codex-step-[N].md
```

### 8c. Address Codex Findings

Read the Codex review. Fix any issues found. If Codex identified something that requires a plan change, note it.

### 8d. Claude Sub-Agent Review

Stage the changes first, then spawn the reviewer with an explicit file list:

```bash
git add [specific files from this step]
```

```
Agent(
  subagent_type="forge-reviewer",
  prompt="<files_to_read>\n.forge/PLAN.md\n</files_to_read>\n\n<changed_files>\n[list of files changed in this step]\n</changed_files>\n\nReview the current staged changes against the plan. This is Step [N]: [step name].\n\nCodex already reviewed and the following was addressed: [summary of codex findings].\n\nYour focus: plan alignment, code quality, completeness, patterns, integration.",
  description="Review step [N]"
)
```

Parse the reviewer's JSON return:
- `"APPROVED"` — proceed to commit
- `"CHANGES_REQUESTED"` — fix the `required_changes`, then re-run reviewer

### 8e. Address Sub-Agent Findings

If the forge-reviewer returns `CHANGES_REQUESTED`:
1. Fix each item in `required_changes`
2. Re-stage changes
3. Re-run the reviewer (maximum 2 re-review cycles per step)

### 8f. Commit

```bash
git commit -m "forge: step [N] — [step name]"
```

### Repeat for each plan step.

---

## Phase 9: Completion

After all steps are implemented:

1. Run a final Codex review on the entire changeset:

```bash
codex review --base [branch-before-forge] "Full project review. Check for: integration issues between steps, missing error handling, security vulnerabilities, and anything that doesn't match the original plan." 2>&1 | tee .forge/reviews/final-codex-review.md
```

2. Address any final findings.

3. Show the user a summary:
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

1. **Never skip the dual review.** Every code change goes through Codex review AND Claude sub-agent review before commit.
2. **Never rush questioning.** Minimum 10 questions. If research raised complex topics, ask more.
3. **Research before opinions.** Don't form views about stack/architecture until research is done.
4. **Codex findings are serious.** Don't dismiss Codex review findings without explanation.
5. **Plan changes need user approval.** If Codex review causes significant plan changes, confirm with user.
6. **Small commits.** Each plan step = one commit. Don't bundle multiple steps.
7. **Track everything.** All reviews go to `.forge/reviews/`. All research to `.forge/research/`.
8. **Parse JSON returns.** Agent returns are JSON — parse the `status`/`verdict` field to determine next action.
9. **Handle degraded states.** If research is incomplete or blocked, proceed with warnings rather than failing entirely.
10. **Stage before review.** Always `git add` specific files before running the forge-reviewer, so it has a clear diff to review.

## File Structure

```
.forge/
  PROJECT.md                # Project description + Q&A
  PLAN.md                   # Implementation plan
  CODEX-PLAN-REVIEW.md      # Codex's review of the plan
  research/
    stack.md                # Tech stack research
    pitfalls.md             # Pitfalls research
    architecture.md         # Architecture research
    prior-art.md            # Prior art research
    codex-analysis.md       # Codex's parallel research
    SYNTHESIS.md            # Combined synthesis
  reviews/
    codex-step-1.md         # Codex review per step
    codex-step-2.md
    claude-step-1.md        # Claude reviewer output per step
    final-codex-review.md   # Final full review
```

## Error Recovery

- If a researcher agent returns `"blocked"`, re-run just that one
- If Codex is unavailable, note it and continue with Claude-only review (but warn the user)
- If synthesizer returns `"insufficient"`, re-run failed researchers before trying again
- If a review cycle finds fundamental issues, update the plan and re-confirm with user before continuing
- If the user wants to skip a review, let them but note the risk
- Maximum 2 re-review cycles per implementation step — if still failing, ask the user

</rules>
