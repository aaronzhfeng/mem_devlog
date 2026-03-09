#!/bin/bash
# Usage: ./setup.sh /path/to/workspace
#
# workspace is the directory where you run Claude Code from (e.g. /root/arc).
# This script places CLAUDE.md, settings.json, and MEMORY.md where Claude Code
# expects them.

set -euo pipefail

WORKSPACE="${1:?Usage: ./setup.sh /path/to/workspace}"
WORKSPACE="$(realpath "$WORKSPACE")"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# 1. CLAUDE.md → workspace root
cp "$SCRIPT_DIR/CLAUDE.md" "$WORKSPACE/CLAUDE.md"
echo "Copied CLAUDE.md → $WORKSPACE/CLAUDE.md"

# 2. settings.json → workspace/.claude/settings.json  (project-level)
mkdir -p "$WORKSPACE/.claude"
cp "$SCRIPT_DIR/settings.json" "$WORKSPACE/.claude/settings.json"
echo "Copied settings.json → $WORKSPACE/.claude/settings.json"

# 3. MEMORY.md → ~/.claude/projects/<project-key>/memory/MEMORY.md
#    The project key is the workspace path with / replaced by -
PROJECT_KEY="$(echo "$WORKSPACE" | sed 's|^/||; s|/|-|g')"
MEMORY_DIR="$HOME/.claude/projects/-${PROJECT_KEY}/memory"
mkdir -p "$MEMORY_DIR"
cp "$SCRIPT_DIR/MEMORY.md" "$MEMORY_DIR/MEMORY.md"
echo "Copied MEMORY.md → $MEMORY_DIR/MEMORY.md"

echo "Done. Start Claude Code from: $WORKSPACE"
