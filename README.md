# skill-manager

Activate agent skills from your repo into Claude Code for the current session.

Skills live in your repo (shared with your team). Claude Code reads them locally from `.claude/skills/` — which is never committed.

## Installation

```bash
git clone <repo-url>
cd skill-manager
bash install.sh
```

The installer will offer to add `~/bin` to your PATH automatically. To install to a custom directory:

```bash
bash install.sh ~/.local/bin
```

Verify:

```bash
skill-manager version
```

**Requirements:** bash 3.2+, awk, grep — no extra dependencies.

## First run

```bash
cd your-project
skill-manager start
```

On first run it asks for the skills directory (relative to repo root):

```
First time setup for this repo
Skills directory (relative path from repo root): .agents/skills
```

This is saved to `.claude/.skill-manager.conf` and reused on every subsequent run.

## Session commands

| Command | Description |
|---|---|
| `start` | Clear previous session, select and load skills |
| `resume` | Show active skills and add more without clearing |
| `stop` | Remove all active skills |

## Info commands

| Command | Description |
|---|---|
| `list` | List all available skills grouped by source |
| `active` | Show currently active skills |
| `config` | Show repo and global config |
| `config reset` | Clear repo config (re-asks path on next start) |

## Global skills bank

Share skills across multiple repos by configuring a global directory:

```bash
skill-manager config global /path/to/your/global/skills
```

Global skills appear as a separate section in `start` and `resume`:

```
── repo: .agents/skills ──────────────────────────
   [ 1] owasp-security       OWASP Top 10 secure coding...
   [ 2] clean-architecture   Clean architecture patterns...

── global: /Users/you/skills ─────────────────────
   [ 3] my-custom-skill      Personal skill...
```

Manage global config:

```bash
skill-manager config global show     # show current global path
skill-manager config global remove   # remove global config
```

## Skill status

| Symbol | Meaning |
|---|---|
| `✓` | Currently active |
| `⚠` | Valid but missing recommended fields (e.g. description) |
| `✗` | Invalid — will be skipped on start |

Invalid skills are shown in `list` but never installed. Validation checks frontmatter format, `name` pattern (`^[a-z0-9-]{1,64}$`), `effort` values, and `context` values.

## Updating Claude Code conventions

If Anthropic changes where skills should be placed or updates the SKILL.md format, only update these files — no changes to the main script needed:

| File | Controls |
|---|---|
| `claude-defaults.sh` | Where skills are installed (`.claude/skills/`) |
| `claude-schema.sh` | SKILL.md validation rules |

## gitignore

Add to every repo that uses skill-manager:

```gitignore
**/.claude/
```

## Tests

```bash
bash tests/test_skill_manager.sh
```
