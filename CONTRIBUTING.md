# Contributing to Forge

Thanks for your interest in contributing. Forge is a Claude Code skill -- all files are markdown, no build step required.

## Project Structure

```
forge-skill/
  commands/forge/
    build.md              # Main orchestrator
  agents/
    forge-researcher.md   # 4-mode research agent
    forge-synthesizer.md  # Research synthesis + question extraction
    forge-reviewer.md     # Code review gate
  install.sh              # Install script
  README.md
  CONTRIBUTING.md
  LICENSE
```

## How to Contribute

### Reporting Issues

Open an issue with:
- What you were trying to build
- Which phase failed or behaved unexpectedly
- The contents of any `.forge/` files relevant to the issue

### Making Changes

1. Fork the repo
2. Create a branch: `git checkout -b my-change`
3. Edit the relevant `.md` files
4. Test by installing locally (`./install.sh`) and running `/forge:build` on a test project
5. Open a PR

### Testing

There's no automated test suite -- these are prompt files. To test:

1. Install your modified files: `./install.sh`
2. Start a new Claude Code session (agents register at session start)
3. Run `/forge:build` with a simple project
4. Verify each phase works as expected

### What Makes a Good Change

**Do:**
- Fix edge cases in the workflow (the kind Codex keeps finding)
- Improve agent prompts to produce more consistent output
- Add handling for failure modes you've encountered
- Tighten the JSON return schemas
- Improve the research quality by refining search strategies

**Don't:**
- Add phases without a clear reason -- the workflow is already 9 phases
- Remove the dual-review requirement -- that's the core value proposition
- Make agents chatty -- structured JSON returns exist for a reason
- Add features that only work with specific tech stacks

### Style

- Agent returns must be single fenced JSON blocks
- Use canonical identifiers (lowercase for research files, UPPERCASE for documents)
- Every error path needs a defined next step
- `set -o pipefail` on any bash pipeline with `tee`
- No `isolation: "worktree"` on parallel agent spawns (auth race condition)

### Code Review

PRs will be reviewed. For significant changes, we'll run them through the Codex review process that built the original skill.

## Architecture Notes

### Why Dual-Model?

Different models have different blind spots. Claude and GPT-family models are trained on different data with different RLHF approaches. Using both as independent reviewers catches more issues than either alone.

### Why So Many Research Agents?

Four focused agents produce better research than one agent trying to cover everything. Each agent has a specific evidence strategy tuned to its domain (e.g., pitfalls research uses post-mortem searches, stack research uses Context7 for version verification).

### Why JSON Returns?

Early versions used markdown returns. Codex review round 1 flagged this as unreliable for orchestrator parsing. JSON with a defined schema and fallback regex extraction is more robust.

### Known Limitations

- Agents created in `~/.claude/agents/` don't register until the next session start
- Codex `exec` auto-compaction is broken in headless mode -- keep prompts concise
- Parallel agent spawns must not use worktrees (credential race condition)
- LLM JSON output can fail non-deterministically -- the fallback regex parser is essential
