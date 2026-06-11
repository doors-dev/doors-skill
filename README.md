# Doors Skill

Skill for building server-side interactive web applications with Doors, a Go UI framework with reactive state, typed routing, and GoX templates.

The canonical skill source is `skills/doors/`. The `packaging/` directory contains generated/secondary distribution support for Claude Code plugin marketplace.

## Install

### Claude

```bash
./install.sh claude
```

This copies the skill to:

```
~/.claude/skills/doors/
```

After installation, use:

```
/doors
```

### OpenCode

```bash
./install.sh opencode
```

This copies the skill to:

```
~/.config/opencode/skills/doors/
```

### Both

```bash
./install.sh all
```

### Manual install

Copy `skills/doors/` to your agent's skills directory.

## Validate

```bash
./install.sh validate
```

## Optional: Claude Code plugin packaging

Plugin packaging is only needed for Claude Code marketplace-style distribution.

Generate plugin package:

```bash
./install.sh package-plugin
```

Then validate the generated plugin package:

```bash
claude plugin validate ./packaging/claude-code-plugin
claude plugin validate ./packaging/claude-code-plugin/plugins/doors
```

When editing the skill, edit `skills/doors/` first, then run `./install.sh package-plugin` to refresh the plugin package copy.

## Windows

From Git Bash:

```bash
./install.sh powershell
```

## Structure

```
skills/doors/                           # Source of truth — edit here first
  SKILL.md
  evals.json
  references/
packaging/claude-code-plugin/           # Plugin marketplace packaging
  .claude-plugin/marketplace.json
  plugins/doors/
    .claude-plugin/plugin.json
    skills/doors/                       # Generated copy — always refresh via ./install.sh package-plugin
```

`packaging/claude-code-plugin/plugins/doors/skills/doors/` is a generated copy of `skills/doors/`. When editing the skill or bumping the version, always edit `skills/doors/` first, then run `./install.sh package-plugin` to refresh the copy.

## License

Apache-2.0
