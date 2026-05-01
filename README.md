# skill-manager

Activate agent skills from your repo into Claude Code for the current session.

Skills live in your repo (shared with your team). Claude Code reads them locally from `.claude/commands/` — which is never committed.

## Installation

```bash
git clone <repo-url>
cd skill-manager
bash install.sh
```

Or to a custom directory:

```bash
bash install.sh ~/.local/bin
```

If `~/bin` is not in your PATH, add it:

```bash
echo 'export PATH="$HOME/bin:$PATH"' >> ~/.zshrc && source ~/.zshrc
```

Verify:

```bash
skill-manager version
```

**Requirements:** bash 4+, awk, grep — no extra dependencies.

## Usage

```bash
cd your-project
skill-manager activate     # first run asks where your skills live
```

On first run it asks for the skills directory (relative to repo root):

```
First time setup for this repo
Skills directory (relative path from repo root): .agents/skills
```

This is saved to `.claude/.skill-manager.conf` and reused on every subsequent run.

### Commands

| Command | Description |
|---|---|
| `activate` | Select and load skills for this session (clears previous session) |
| `list` | List all available skills with active status |
| `active` | Show currently loaded skills |
| `deactivate` | Manually remove all loaded skills |
| `config` | Show current repo config |
| `config reset` | Clear config (re-asks path on next activate) |

## How it works

- Skills are read from your configured path (e.g. `.agents/skills/`)
- Selected skills are copied to `.claude/commands/<name>.md`
- Each new `activate` clears the previous session automatically
- `.claude/` is local only — add it to `.gitignore`

```gitignore
**/.claude/
```

## Tests

```bash
bash tests/test_skill_manager.sh
```
