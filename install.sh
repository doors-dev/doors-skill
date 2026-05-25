#!/usr/bin/env bash
set -euo pipefail

SKILL_NAME="doors"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SRC="$ROOT/plugins/doors/skills/$SKILL_NAME"

json_check() {
  local file="$1"

  if command -v python3 >/dev/null 2>&1; then
    python3 -m json.tool "$file" >/dev/null
  fi
}

validate_eval_coverage() {
  if ! command -v python3 >/dev/null 2>&1; then
    return 0
  fi

  python3 - "$SRC" <<'PY'
import json
import sys
from pathlib import Path

skill = Path(sys.argv[1])
evals = json.loads((skill / "evals.json").read_text())
ids = [case.get("id") for case in evals.get("cases", [])]
dupes = sorted({id_ for id_ in ids if ids.count(id_) > 1})
if dupes:
    print("evals.json contains duplicate case ids:", ", ".join(dupes), file=sys.stderr)
    sys.exit(1)

covered = {
    ref
    for case in evals.get("cases", [])
    for ref in case.get("expected_references", [])
    if ref.startswith("references/")
}
unknown = sorted(ref for ref in covered if not (skill / ref).exists())
if unknown:
    print("evals.json references missing files:", ", ".join(unknown), file=sys.stderr)
    sys.exit(1)

missing = []
for path in sorted((skill / "references").glob("*.md")):
    ref = f"references/{path.name}"
    if ref not in covered:
        missing.append(ref)

if missing:
    print("evals.json does not cover reference files:", ", ".join(missing), file=sys.stderr)
    sys.exit(1)
PY
}

validate_source() {
  [ -d "$SRC" ] || {
    echo "Missing source skill directory: $SRC" >&2
    return 1
  }

  [ -f "$SRC/SKILL.md" ] || {
    echo "Missing SKILL.md in $SRC" >&2
    return 1
  }

  [ -f "$SRC/references/gox-minimal.md" ] || {
    echo "Missing references/gox-minimal.md fallback" >&2
    return 1
  }

  [ -f "$SRC/evals.json" ] || {
    echo "Missing evals.json" >&2
    return 1
  }

  json_check "$SRC/evals.json"
  json_check "$ROOT/plugins/doors/.codex-plugin/plugin.json"
  json_check "$ROOT/plugins/doors/.claude-plugin/plugin.json"
  json_check "$ROOT/.agents/plugins/marketplace.json"
  json_check "$ROOT/.claude-plugin/marketplace.json"
  validate_eval_coverage

  grep -q '^name: doors$' "$SRC/SKILL.md"
  grep -q '^description:' "$SRC/SKILL.md"
}

validate_installed() {
  local dest_root="$1"
  local dest="$dest_root/$SKILL_NAME"

  [ -f "$dest/SKILL.md" ] || {
    echo "Install validation failed: missing $dest/SKILL.md" >&2
    return 1
  }

  [ -f "$dest/references/gox-minimal.md" ] || {
    echo "Install validation failed: missing $dest/references/gox-minimal.md" >&2
    return 1
  }

  [ -f "$dest/evals.json" ] || {
    echo "Install validation failed: missing $dest/evals.json" >&2
    return 1
  }

  echo "Validated $SKILL_NAME at $dest"
}

install_skill() {
  local dest_root="$1"
  local dest="$dest_root/$SKILL_NAME"

  validate_source
  mkdir -p "$dest"
  cp -R "$SRC/." "$dest/"

  echo "Installed $SKILL_NAME to $dest"
  validate_installed "$dest_root"
}

validate_all_targets() {
  local tmp
  tmp="$(mktemp -d)"
  trap "rm -rf '$tmp'" EXIT

  validate_source
  install_skill "$tmp/.config/opencode/skills"
  install_skill "$tmp/.agents/skills"
  install_skill "$tmp/.claude/skills"

  echo "Validation passed for source, opencode, codex-skill, and claude-skill install layouts."
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
  validate)
    validate_all_targets
    ;;
  powershell)
    src_win="$(cd "$SRC" && pwd -W 2>/dev/null)" || {
      printf '%s\n' "This command must be run from Git Bash (MSYS2/MinGW) on Windows." >&2
      exit 1
    }
    printf '\n%s\n\n' "Run the following in PowerShell:"
    printf '  Copy-Item -Recurse '\''%s'\'' "$env:USERPROFILE\\.config\\opencode\\skills\\%s"\n' "$src_win" "$SKILL_NAME"
    printf '  Copy-Item -Recurse '\''%s'\'' "$env:USERPROFILE\\.agents\\skills\\%s"\n' "$src_win" "$SKILL_NAME"
    printf '  Copy-Item -Recurse '\''%s'\'' "$env:USERPROFILE\\.claude\\skills\\%s"\n' "$src_win" "$SKILL_NAME"
    printf '\n'
    ;;
  *)
    echo "usage: $0 [opencode|codex-skill|claude-skill|all|validate|powershell]"
    exit 1
    ;;
esac
