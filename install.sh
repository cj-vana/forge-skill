#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLAUDE_DIR="$HOME/.claude"

echo "Installing Forge skill..."

# Create directories
mkdir -p "$CLAUDE_DIR/commands/forge"
mkdir -p "$CLAUDE_DIR/agents"

# Install command
cp "$SCRIPT_DIR/commands/forge/build.md" "$CLAUDE_DIR/commands/forge/build.md"
echo "  Installed commands/forge/build.md"

# Install agents
for agent in forge-researcher forge-synthesizer forge-reviewer; do
  cp "$SCRIPT_DIR/agents/${agent}.md" "$CLAUDE_DIR/agents/${agent}.md"
  echo "  Installed agents/${agent}.md"
done

echo ""
echo "Forge installed successfully."
echo ""
echo "Start a new Claude Code session, then run:"
echo "  /forge:build"
