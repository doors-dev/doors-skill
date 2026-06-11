#!/usr/bin/env bash
set -euo pipefail

SKILL_NAME="doors"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILL_SOURCE="$ROOT/skills/$SKILL_NAME"
PLUGIN_PACKAGE="$ROOT/packaging/claude-code-plugin"
PLUGIN_SKILL_COPY="$PLUGIN_PACKAGE/plugins/$SKILL_NAME/skills/$SKILL_NAME"

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

  python3 - "$SKILL_SOURCE" <<'PY'
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

missing_gox = [
    case.get("id", "<unknown>")
    for case in evals.get("cases", [])
    if "references/00-gox.md" not in case.get("expected_references", [])
]
if missing_gox:
    print("evals.json cases must include references/00-gox.md:", ", ".join(missing_gox), file=sys.stderr)
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
  [ -d "$SKILL_SOURCE" ] || {
    echo "Missing source skill directory: $SKILL_SOURCE" >&2
    return 1
  }

  [ -f "$SKILL_SOURCE/SKILL.md" ] || {
    echo "Missing SKILL.md in $SKILL_SOURCE" >&2
    return 1
  }

  [ -s "$SKILL_SOURCE/SKILL.md" ] || {
    echo "SKILL.md is empty" >&2
    return 1
  }

  [ -f "$SKILL_SOURCE/references/00-gox.md" ] || {
    echo "Missing references/00-gox.md" >&2
    return 1
  }

  [ -f "$SKILL_SOURCE/evals.json" ] || {
    echo "Missing evals.json" >&2
    return 1
  }

  json_check "$SKILL_SOURCE/evals.json"
  json_check "$PLUGIN_PACKAGE/plugins/$SKILL_NAME/.codex-plugin/plugin.json" 2>/dev/null || true
  json_check "$PLUGIN_PACKAGE/plugins/$SKILL_NAME/.claude-plugin/plugin.json"
  json_check "$ROOT/.agents/plugins/marketplace.json"
  json_check "$PLUGIN_PACKAGE/.claude-plugin/marketplace.json"
  validate_eval_coverage

  grep -q '^name: doors$' "$SKILL_SOURCE/SKILL.md"
  grep -q '^description:' "$SKILL_SOURCE/SKILL.md"

  # Ensure no old source path still exists outside packaging
  if [ -d "$ROOT/plugins/doors/skills/doors" ]; then
    echo "ERROR: Old source path plugins/doors/skills/doors still exists. Remove it." >&2
    return 1
  fi
}

validate_installed() {
  local dest_root="$1"
  local dest="$dest_root/$SKILL_NAME"

  [ -f "$dest/SKILL.md" ] || {
    echo "Install validation failed: missing $dest/SKILL.md" >&2
    return 1
  }

  [ -f "$dest/references/00-gox.md" ] || {
    echo "Install validation failed: missing $dest/references/00-gox.md" >&2
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
  cp -R "$SKILL_SOURCE/." "$dest/"

  echo "Installed $SKILL_NAME to $dest"
  validate_installed "$dest_root"
}

package_plugin() {
  echo "Generating plugin package from source skill..."

  rm -rf "$PLUGIN_SKILL_COPY"
  mkdir -p "$PLUGIN_SKILL_COPY/references"
  cp "$SKILL_SOURCE/SKILL.md" "$PLUGIN_SKILL_COPY/"
  cp "$SKILL_SOURCE/evals.json" "$PLUGIN_SKILL_COPY/"
  cp "$SKILL_SOURCE/references/"*.md "$PLUGIN_SKILL_COPY/references/"

  if [ -f "$PLUGIN_SKILL_COPY/SKILL.md" ]; then
    echo "Plugin package generated at $PLUGIN_SKILL_COPY"
  else
    echo "ERROR: Plugin package generation failed - missing SKILL.md" >&2
    return 1
  fi
}

validate_all_targets() {
  local tmp
  tmp="$(mktemp -d)"
  trap "rm -rf '$tmp'" EXIT

  validate_source
  install_skill "$tmp/.config/opencode/skills"
  install_skill "$tmp/.claude/skills"

  echo "All validations passed."
}

case "${1:-help}" in
  opencode)
    install_skill "$HOME/.config/opencode/skills"
    ;;
  claude)
    install_skill "$HOME/.claude/skills"
    ;;
  all)
    install_skill "$HOME/.config/opencode/skills"
    install_skill "$HOME/.claude/skills"
    ;;
  validate)
    validate_all_targets
    ;;
  package-plugin)
    package_plugin
    ;;
  powershell)
    src_win="$(cd "$SKILL_SOURCE" && pwd -W 2>/dev/null)" || {
      printf '%s\n' "This command must be run from Git Bash (MSYS2/MinGW) on Windows." >&2
      exit 1
    }
    printf '\n%s\n\n' "Run the following in PowerShell:"
    printf '  Copy-Item -Recurse '\''%s'\'' "$env:USERPROFILE\\.config\\opencode\\skills\\%s"\n' "$src_win" "$SKILL_NAME"
    printf '  Copy-Item -Recurse '\''%s'\'' "$env:USERPROFILE\\.claude\\skills\\%s"\n' "$src_win" "$SKILL_NAME"
    printf '\n'
    ;;
  help|--help|-h)
    echo "usage: $0 [command]"
    echo ""
    echo "Commands:"
    echo "  opencode         Install skill to ~/.config/opencode/skills/$SKILL_NAME"
    echo "  claude           Install skill to ~/.claude/skills/$SKILL_NAME"
    echo "  all              Install to both opencode and claude"
    echo "  validate         Validate source skill integrity"
    echo "  package-plugin   Generate plugin packaging from source skill"
    echo "  powershell       Print PowerShell copy commands for Windows"
    ;;
  *)
    echo "usage: $0 [opencode|claude|all|validate|package-plugin|powershell|help]"
    exit 1
    ;;
esac
