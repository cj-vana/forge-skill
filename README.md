# Forge

A Claude Code skill that implements a dual-model (Claude + Codex) development workflow. Every piece of code goes through research, planning, and dual review gates before it's committed.

## What It Does

```
/forge:build
```

One command. Nine phases. Two AI models checking each other's work.

### The Workflow

1. **Intake** -- Asks what you want to build, gathers constraints
2. **Research** -- 5 parallel research tracks (4 Claude agents + Codex):
   - **Stack** -- tech choices with versions, rationale, what to avoid
   - **Pitfalls** -- domain-specific mistakes and how to prevent them
   - **Architecture** -- system structure, component boundaries, data flow
   - **Prior Art** -- existing solutions, what to reuse vs build
   - **Codex Analysis** -- Codex's independent research on all the above
3. **Synthesis** -- Combines all research, identifies conflicts, extracts questions
4. **Deep Questioning** -- 10+ research-driven follow-up questions (not generic -- driven by actual findings)
5. **Plan** -- Implementation plan with steps, acceptance criteria, and mapped risks
6. **Codex Plan Review** -- Codex adversarially challenges the plan
7. **Plan Refinement** -- Incorporate valid findings, reject bad ones, clarify with user
8. **Implementation Loop** -- For each plan step:
   - Claude implements
   - Codex reviews (bugs, security, edge cases)
   - Fix findings
   - Claude sub-agent reviews (plan alignment, quality, patterns)
   - Fix findings
   - Commit
9. **Completion** -- Final dual-review of the full project, summary, optional PR

### The Dual Review Guarantee

Every commit passes through two independent AI reviewers:

- **Codex (GPT-5.4)** -- Adversarial review focused on bugs, security, performance, edge cases
- **Claude sub-agent** -- Holistic review focused on plan alignment, code quality, patterns, integration

Both must approve. If either requests changes, the full review cycle restarts. No code ships without dual sign-off.

## Install

### Prerequisites

- [Claude Code](https://docs.anthropic.com/en/docs/claude-code) CLI installed
- [Codex CLI](https://github.com/openai/codex) installed and configured (`codex` command available)

### Quick Install

```bash
# Clone the repo
git clone https://github.com/cj-vana/forge-skill.git
cd forge-skill

# Run the install script
./install.sh
```

### Manual Install

Copy the files to your Claude Code directories:

```bash
# Command
cp commands/forge/build.md ~/.claude/commands/forge/build.md

# Agents
cp agents/forge-researcher.md ~/.claude/agents/
cp agents/forge-synthesizer.md ~/.claude/agents/
cp agents/forge-reviewer.md ~/.claude/agents/
```

### Verify

Start a new Claude Code session and check that `/forge:build` appears in your skill list.

## Usage

```
/forge:build
```

Or with a project description:

```
/forge:build a CLI tool that converts markdown to PDF with syntax highlighting
```

Or reference a file:

```
/forge:build @requirements.md
```

### Output

Forge creates a `.forge/` directory in your project:

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
    codex-plan-review.md     # Codex's plan review
    codex-step-{N}.md        # Codex review per step
    claude-step-{N}.json     # Claude reviewer output per step
    final-codex-review.md    # Final full review
    final-claude-review.json # Final Claude review
```

## Architecture

### Files

| File | Location | Purpose |
|------|----------|---------|
| `build.md` | `~/.claude/commands/forge/` | Main orchestrator -- runs the 9-phase workflow |
| `forge-researcher.md` | `~/.claude/agents/` | Research agent with 4 modes (stack, pitfalls, architecture, prior-art) |
| `forge-synthesizer.md` | `~/.claude/agents/` | Combines research outputs, extracts structured questions |
| `forge-reviewer.md` | `~/.claude/agents/` | Code review gate with 5-dimension scoring |

### Agent Communication

All agents return structured JSON to the orchestrator:

- **Researchers** return `{ status: "complete"|"incomplete"|"blocked", ... }`
- **Synthesizer** returns `{ status: "complete"|"degraded"|"insufficient", questions: [...], ... }`
- **Reviewer** returns `{ verdict: "APPROVED"|"CHANGES_REQUESTED", ... }`

### Degraded Mode

Forge handles failures gracefully:

- If a researcher is blocked, the synthesizer proceeds with available data
- If Codex is unavailable, falls back to Claude-only review with a warning
- If JSON parsing fails, uses regex fallback for routing fields
- If review cycles loop, escalates to user after 2 attempts

## Development History

Built through its own philosophy -- every file went through multiple rounds of Codex review:

| Round | Findings | Examples |
|-------|----------|---------|
| 1 | 7 | JSON returns needed structure, naming inconsistencies, no degraded mode |
| 2 | 7 | files_to_read contradiction, wait boundaries, review gate inconsistency |
| 3 | 3 | tee exit code masking, missing base-ref, leaky dual-review |
| 4 | 2 | Phase 9 no Claude re-review, greenfield base-ref empty |
| 5 | 2 | Non-git directory handling, final review gate closure |

21 findings across 5 rounds, all resolved.

## License

MIT
