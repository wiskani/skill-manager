#!/usr/bin/env bash
# Test suite for skill-manager
set -euo pipefail

SCRIPT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/skill-manager"
FIXTURES="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/fixtures/sample-skills"

# ---------------------------------------------------------------------------
# Mini test framework
# ---------------------------------------------------------------------------

PASS=0
FAIL=0
ERRORS=()

pass() { PASS=$((PASS + 1)); echo "  ✓ $1"; }
fail() { FAIL=$((FAIL + 1)); ERRORS+=("$1"); echo "  ✗ $1"; }

assert_exit_ok()   { [[ $? -eq 0 ]] && pass "$1" || fail "$1: expected exit 0"; }
assert_exit_fail() { [[ $? -ne 0 ]] && pass "$1" || fail "$1: expected non-zero exit"; }

assert_contains() {
  local label="$1" pattern="$2" text="$3"
  if echo "$text" | grep -q "$pattern"; then
    pass "$label"
  else
    fail "$label: expected to find '$pattern'"
  fi
}

assert_not_contains() {
  local label="$1" pattern="$2" text="$3"
  if ! echo "$text" | grep -q "$pattern"; then
    pass "$label"
  else
    fail "$label: did not expect to find '$pattern'"
  fi
}

assert_file_exists()     { [[ -f "$2" ]] && pass "$1" || fail "$1: file not found: $2"; }
assert_file_not_exists() { [[ ! -f "$2" ]] && pass "$1" || fail "$1: file should not exist: $2"; }

# ---------------------------------------------------------------------------
# Setup / teardown helpers
# ---------------------------------------------------------------------------

setup() {
  WORKDIR=$(mktemp -d)
  mkdir -p "$WORKDIR/skills"
  cp -r "$FIXTURES"/. "$WORKDIR/skills/"
}

teardown() {
  rm -rf "$WORKDIR"
}

run_sm() {
  (cd "$WORKDIR" && bash "$SCRIPT" "$@")
}

run_sm_input() {
  local input="$1"; shift
  (cd "$WORKDIR" && printf "%s\n" "$input" | bash "$SCRIPT" "$@")
}

# ---------------------------------------------------------------------------
# Tests
# ---------------------------------------------------------------------------

test_help() {
  echo "\nhelp / usage"
  local out
  out=$(run_sm help 2>&1) || true
  assert_contains "shows usage header"  "skill-manager" "$out"
  assert_contains "shows activate cmd"  "activate"      "$out"
  assert_contains "shows deactivate cmd" "deactivate"   "$out"
  assert_contains "shows list cmd"      "list"          "$out"
}

test_version() {
  echo "\nversion"
  local out
  out=$(run_sm version 2>&1)
  assert_contains "shows version number" "1.0.0" "$out"
}

test_list_first_run_asks_path() {
  echo "\nlist — first run asks for skills path"
  local out
  out=$(run_sm_input "skills" list 2>&1) || true
  assert_contains "prompts for path"       "relative path" "$out"
  assert_contains "saves config on list"   "config saved"  "$out"
}

test_list_shows_skills() {
  echo "\nlist — shows all skills after config"
  printf "skills\n" | (cd "$WORKDIR" && bash "$SCRIPT" list) > /dev/null 2>&1 || true
  local out
  out=$(run_sm list 2>&1)
  assert_contains "shows owasp-security"    "owasp-security"    "$out"
  assert_contains "shows clean-architecture" "clean-architecture" "$out"
  assert_contains "shows senior-architect"  "senior-architect"  "$out"
  assert_contains "shows skill count"       "(3)"               "$out"
}

test_config_saved_on_first_activate() {
  echo "\nactivate — saves config on first run"
  run_sm_input $'skills\n1' activate > /dev/null 2>&1 || true
  assert_file_exists "config file created" "$WORKDIR/.claude/.skill-manager.conf"
  local content
  content=$(cat "$WORKDIR/.claude/.skill-manager.conf")
  assert_contains "config has SKILLS_DIR" "SKILLS_DIR" "$content"
}

test_activate_installs_selected_skills() {
  echo "\nactivate — installs selected skills into .claude/commands/"
  # config already set from previous test, select skills 1 and 2
  run_sm_input "1 2" activate > /dev/null 2>&1
  assert_file_exists     "skill 1 installed" "$WORKDIR/.claude/commands/clean-architecture.md"
  assert_file_exists     "skill 2 installed" "$WORKDIR/.claude/commands/owasp-security.md"
  assert_file_not_exists "skill 3 not installed" "$WORKDIR/.claude/commands/senior-architect.md"
}

test_activate_strips_frontmatter() {
  echo "\nactivate — strips YAML frontmatter from installed skills"
  local content
  content=$(cat "$WORKDIR/.claude/commands/owasp-security.md")
  assert_not_contains "no frontmatter dashes"  "^---"         "$content"
  assert_not_contains "no name field"          "^name:"       "$content"
  assert_not_contains "no description field"   "^description:" "$content"
  assert_contains     "skill content present"  "OWASP"        "$content"
}

test_activate_concatenates_extra_files() {
  echo "\nactivate — appends extra .md files for skills that have them"
  local content
  content=$(cat "$WORKDIR/.claude/commands/clean-architecture.md")
  assert_contains "main content present"  "Clean Architecture"              "$content"
  assert_contains "extra file appended"   "Concrete implementation examples" "$content"
}

test_activate_concatenates_references() {
  echo "\nactivate — appends references/ for skills that have them"
  run_sm_input "3" activate > /dev/null 2>&1
  local content
  content=$(cat "$WORKDIR/.claude/commands/senior-architect.md")
  assert_contains "main content present"     "Senior Architect"          "$content"
  assert_contains "reference file appended"  "Architecture Patterns Reference" "$content"
}

test_activate_cleans_previous_session() {
  echo "\nactivate — cleans skills from previous session"
  # Previous activate installed senior-architect (skill 3)
  assert_file_exists "senior-architect present before" "$WORKDIR/.claude/commands/senior-architect.md"
  # New activate: select only skill 1
  run_sm_input "1" activate > /dev/null 2>&1
  assert_file_not_exists "senior-architect removed after new activate" \
    "$WORKDIR/.claude/commands/senior-architect.md"
  assert_file_exists "new selection installed" "$WORKDIR/.claude/commands/clean-architecture.md"
}

test_activate_shows_cleanup_message() {
  echo "\nactivate — shows cleanup message when clearing previous session"
  # There's already an active session from the previous test, activate again
  local out
  out=$(run_sm_input "1" activate 2>&1)
  assert_contains "shows cleared message" "cleared" "$out"
}

test_active_shows_installed_skills() {
  echo "\nactive — shows currently active skills"
  local out
  out=$(run_sm active 2>&1)
  assert_contains "shows active skill"   "clean-architecture" "$out"
  assert_contains "shows slash prefix"   "/"                  "$out"
}

test_active_no_skills() {
  echo "\nactive — reports no skills when manifest is empty"
  rm -f "$WORKDIR/.claude/.skill-manifest"
  local out
  out=$(run_sm active 2>&1)
  assert_contains "reports no skills" "No active skills" "$out"
}

test_manifest_tracks_installed_skills() {
  echo "\nmanifest — tracks only installed skills"
  run_sm_input "2 3" activate > /dev/null 2>&1
  local manifest
  manifest=$(cat "$WORKDIR/.claude/.skill-manifest")
  assert_contains     "manifest has owasp"    "owasp-security"    "$manifest"
  assert_contains     "manifest has senior"   "senior-architect"  "$manifest"
  assert_not_contains "manifest skips clean"  "clean-architecture" "$manifest"
}

test_config_show() {
  echo "\nconfig show — displays current config"
  local out
  out=$(run_sm config show 2>&1)
  assert_contains "shows SKILLS_DIR" "SKILLS_DIR" "$out"
  assert_contains "shows path value" "skills"     "$out"
}

test_config_reset() {
  echo "\nconfig reset — removes config file"
  run_sm config reset > /dev/null 2>&1
  assert_file_not_exists "config file removed" "$WORKDIR/.claude/.skill-manager.conf"
}

test_error_skills_dir_not_found() {
  echo "\nerror — skills dir not found"
  # Reset config to a bad path
  mkdir -p "$WORKDIR/.claude"
  echo 'SKILLS_DIR="nonexistent/path"' > "$WORKDIR/.claude/.skill-manager.conf"
  local out
  out=$(run_sm list 2>&1) || true
  assert_contains "shows error message" "error" "$out"
}

test_range_selection() {
  echo "\nactivate — range selection (e.g. 1-2)"
  mkdir -p "$WORKDIR/.claude"
  echo "SKILLS_DIR=\"skills\"" > "$WORKDIR/.claude/.skill-manager.conf"
  run_sm_input "1-2" activate > /dev/null 2>&1
  assert_file_exists "first in range installed"  "$WORKDIR/.claude/commands/clean-architecture.md"
  assert_file_exists "second in range installed" "$WORKDIR/.claude/commands/owasp-security.md"
}

test_all_selection() {
  echo "\nactivate — 'all' installs every skill"
  run_sm_input "all" activate > /dev/null 2>&1
  assert_file_exists "all: clean-architecture" "$WORKDIR/.claude/commands/clean-architecture.md"
  assert_file_exists "all: owasp-security"     "$WORKDIR/.claude/commands/owasp-security.md"
  assert_file_exists "all: senior-architect"   "$WORKDIR/.claude/commands/senior-architect.md"
}

# ---------------------------------------------------------------------------
# Runner
# ---------------------------------------------------------------------------

echo "skill-manager test suite"
echo "========================"

setup

test_help
test_version
test_list_first_run_asks_path

teardown; setup   # fresh workdir for remaining tests

test_list_shows_skills
test_config_saved_on_first_activate
test_activate_installs_selected_skills
test_activate_strips_frontmatter
test_activate_concatenates_extra_files
test_activate_concatenates_references
test_activate_cleans_previous_session
test_activate_shows_cleanup_message
test_active_shows_installed_skills
test_active_no_skills
test_manifest_tracks_installed_skills
test_config_show
test_config_reset
test_error_skills_dir_not_found
test_range_selection
test_all_selection

teardown

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------

echo "\n========================"
echo "Results: ${PASS} passed, ${FAIL} failed"

if [[ ${FAIL} -gt 0 ]]; then
  echo "\nFailed tests:"
  for err in "${ERRORS[@]}"; do
    echo "  ✗ $err"
  done
  exit 1
fi
