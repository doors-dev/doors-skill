#!/usr/bin/env bash
set -euo pipefail

SKILL_NAME="doors"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SRC="$ROOT/plugins/doors/skills/$SKILL_NAME"

install_skill() {
  local dest_root="$1"
  local dest="$dest_root/$SKILL_NAME"

  mkdir -p "$dest"
  cp -R "$SRC/." "$dest/"

  echo "Installed $SKILL_NAME to $dest"
}

case "${1:-all}" in
  opencode)
    install_skill "$HOME/.config/opencode/skills"
    ;;
  codex-skill)
    install_skill "$HOME/.agents/skills"
    ;;
  claude-skill)
    install_skill "$HOME/.claude/skills"
    ;;
  all)
    install_skill "$HOME/.config/opencode/skills"
    install_skill "$HOME/.agents/skills"
    install_skill "$HOME/.claude/skills"
    ;;
  *)
    echo "usage: $0 [opencode|codex-skill|claude-skill|all]"
    exit 1
    ;;
esac
