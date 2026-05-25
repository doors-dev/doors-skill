# Doors Skill

Agent skill/plugin for building server-side interactive web applications with Doors, a Go UI framework with reactive state, typed routing, and GoX templates.

## Claude Code

Add the marketplace:

```bash
claude plugin marketplace add doors-dev/doors-skill
```

Install the plugin:

```bash
claude plugin install doors@doors-skill
```

Validate locally:

```bash
claude plugin validate .
claude plugin validate ./plugins/doors
```

## Codex

Add the marketplace:

```bash
codex plugin marketplace add doors-dev/doors-skill
```

For local testing:

```bash
codex plugin marketplace add .
codex plugin marketplace list
```

## OpenCode

Install the skill directly:

```bash
./install.sh opencode
```

This copies the skill to:

```text
~/.config/opencode/skills/doors/
```

## Manual portable install

```bash
./install.sh all
```
