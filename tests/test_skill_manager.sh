#!/usr/bin/env bash
# Test suite for skill-manager
set -euo pipefail

SCRIPT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/skill-manager"
VALID_FIXTURES="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/fixtures/sample-skills"
INVALID_FIXTURES="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/fixtures/invalid-skills"

# ---------------------------------------------------------------------------
# Mini test framework
# ---------------------------------------------------------------------------

PASS=0
FAIL=0
ERRORS=()

pass() { PASS=$((PASS + 1)); echo "  ✓ $1"; }
fail() { FAIL=$((FAIL + 1)); ERRORS+=("$1"); echo "  ✗ $1"; }

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

assert_file_exists()      { [[ -f "$2" ]] && pass "$1" || fail "$1: file not found: $2"; }
assert_file_not_exists()  { [[ ! -f "$2" ]] && pass "$1" || fail "$1: file should not exist: $2"; }
assert_dir_exists()       { [[ -d "$2" ]] && pass "$1" || fail "$1: dir not found: $2"; }
assert_dir_not_exists()   { [[ ! -d "$2" ]] && pass "$1" || fail "$1: dir should not exist: $2"; }

# ---------------------------------------------------------------------------
# Setup / teardown
# ---------------------------------------------------------------------------

setup() {
  WORKDIR=$(mktemp -d)
  mkdir -p "$WORKDIR/skills"
  cp -r "$VALID_FIXTURES"/. "$WORKDIR/skills/"
}

setup_mixed() {
  WORKDIR=$(mktemp -d)
  mkdir -p "$WORKDIR/skills"
  cp -r "$VALID_FIXTURES"/. "$WORKDIR/skills/"
  cp -r "$INVALID_FIXTURES"/. "$WORKDIR/skills/"
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

set_config() {
  mkdir -p "$WORKDIR/.claude"
  echo 'SKILLS_DIR="skills"' > "$WORKDIR/.claude/.skill-manager.conf"
}

# ---------------------------------------------------------------------------
# Tests: basic commands
# ---------------------------------------------------------------------------

test_help() {
  echo "\nhelp / usage"
  local out
  out=$(run_sm help 2>&1) || true
  assert_contains "shows usage header"   "skill-manager" "$out"
  assert_contains "shows activate cmd"   "activate"      "$out"
  assert_contains "shows deactivate cmd" "deactivate"    "$out"
  assert_contains "shows list cmd"       "list"          "$out"
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
  assert_contains "prompts for path" "relative path" "$out"
  assert_contains "saves config"     "config saved"  "$out"
}

test_list_shows_skills() {
  echo "\nlist — shows all valid skills"
  set_config
  local out
  out=$(run_sm list 2>&1)
  assert_contains "shows owasp-security"     "owasp-security"     "$out"
  assert_contains "shows clean-architecture" "clean-architecture" "$out"
  assert_contains "shows senior-architect"   "senior-architect"   "$out"
  assert_contains "shows skill count"        "(3)"                "$out"
}

# ---------------------------------------------------------------------------
# Tests: validation
# ---------------------------------------------------------------------------

test_validate_rejects_bad_name() {
  echo "\nvalidation — rejects invalid name field"
  set_config
  local out
  out=$(run_sm_input "all" activate 2>&1) || true
  assert_contains "bad-name rejected"       "bad-name"    "$out"
  assert_contains "shows skipped message"   "skipped"     "$out"
  assert_dir_not_exists "bad-name not installed" "$WORKDIR/.claude/skills/bad-name"
}

test_validate_rejects_no_frontmatter() {
  echo "\nvalidation — rejects skill with no frontmatter"
  set_config
  local out
  out=$(run_sm_input "all" activate 2>&1) || true
  assert_contains "no-frontmatter rejected"  "no-frontmatter" "$out"
  assert_contains "shows skipped message"    "skipped"        "$out"
  assert_dir_not_exists "no-frontmatter not installed" "$WORKDIR/.claude/skills/no-frontmatter"
}

test_validate_rejects_bad_effort() {
  echo "\nvalidation — rejects invalid effort value"
  set_config
  local out
  out=$(run_sm_input "all" activate 2>&1) || true
  assert_contains "bad-effort rejected"     "bad-effort" "$out"
  assert_contains "shows skipped message"   "skipped"    "$out"
  assert_dir_not_exists "bad-effort not installed" "$WORKDIR/.claude/skills/bad-effort"
}

test_validate_rejects_bad_context() {
  echo "\nvalidation — rejects invalid context value"
  set_config
  local out
  out=$(run_sm_input "all" activate 2>&1) || true
  assert_contains "bad-context rejected"    "bad-context" "$out"
  assert_contains "shows skipped message"   "skipped"     "$out"
  assert_dir_not_exists "bad-context not installed" "$WORKDIR/.claude/skills/bad-context"
}

test_validate_warns_no_description() {
  echo "\nvalidation — warns but installs skill with no description"
  set_config
  local out
  out=$(run_sm_input "all" activate 2>&1) || true
  assert_contains     "shows warning"             "description"           "$out"
  assert_dir_exists   "no-description installed"  "$WORKDIR/.claude/skills/no-description"
}

test_validate_installs_valid_skips_invalid() {
  echo "\nvalidation — installs valid skills, skips invalid ones"
  set_config
  run_sm_input "all" activate > /dev/null 2>&1 || true
  assert_dir_exists     "valid skill installed"     "$WORKDIR/.claude/skills/owasp-security"
  assert_dir_exists     "valid skill installed"     "$WORKDIR/.claude/skills/clean-architecture"
  assert_dir_exists     "valid skill installed"     "$WORKDIR/.claude/skills/senior-architect"
  assert_dir_not_exists "invalid skill skipped"     "$WORKDIR/.claude/skills/bad-name"
  assert_dir_not_exists "invalid skill skipped"     "$WORKDIR/.claude/skills/no-frontmatter"
  assert_dir_not_exists "invalid skill skipped"     "$WORKDIR/.claude/skills/bad-effort"
  assert_dir_not_exists "invalid skill skipped"     "$WORKDIR/.claude/skills/bad-context"
}

test_validate_list_marks_invalid() {
  echo "\nvalidation — list marks invalid skills with ✗"
  set_config
  local out
  out=$(run_sm list 2>&1)
  assert_contains "marks bad-name as invalid"        "bad-name"        "$out"
  assert_contains "marks no-frontmatter as invalid"  "no-frontmatter"  "$out"
  assert_contains "marks bad-effort as invalid"      "bad-effort"      "$out"
  assert_contains "marks bad-context as invalid"     "bad-context"     "$out"
}

# ---------------------------------------------------------------------------
# Tests: install behavior
# ---------------------------------------------------------------------------

test_activate_installs_as_directory() {
  echo "\nactivate — installs skill as directory into .claude/skills/"
  set_config
  run_sm_input "1 2" activate > /dev/null 2>&1
  assert_dir_exists     "skill 1 installed as dir" "$WORKDIR/.claude/skills/clean-architecture"
  assert_dir_exists     "skill 2 installed as dir" "$WORKDIR/.claude/skills/owasp-security"
  assert_dir_not_exists "skill 3 not installed"    "$WORKDIR/.claude/skills/senior-architect"
}

test_activate_keeps_frontmatter() {
  echo "\nactivate — keeps YAML frontmatter intact"
  set_config
  run_sm_input "2" activate > /dev/null 2>&1
  local content
  content=$(cat "$WORKDIR/.claude/skills/owasp-security/SKILL.md")
  assert_contains "frontmatter present"   "^---"         "$content"
  assert_contains "name field preserved"  "^name:"       "$content"
  assert_contains "skill content present" "OWASP"        "$content"
}

test_activate_preserves_structure() {
  echo "\nactivate — preserves full directory structure"
  set_config
  run_sm_input "1 3" activate > /dev/null 2>&1
  assert_file_exists "SKILL.md present"         "$WORKDIR/.claude/skills/clean-architecture/SKILL.md"
  assert_file_exists "extra file preserved"     "$WORKDIR/.claude/skills/clean-architecture/examples.md"
  assert_file_exists "references preserved"     "$WORKDIR/.claude/skills/senior-architect/references/patterns.md"
}

test_activate_cleans_previous_session() {
  echo "\nactivate — cleans skills from previous session"
  set_config
  run_sm_input "3" activate > /dev/null 2>&1
  assert_dir_exists     "senior-architect present before" "$WORKDIR/.claude/skills/senior-architect"
  run_sm_input "1" activate > /dev/null 2>&1
  assert_dir_not_exists "senior-architect removed"        "$WORKDIR/.claude/skills/senior-architect"
  assert_dir_exists     "new selection installed"         "$WORKDIR/.claude/skills/clean-architecture"
}

test_activate_shows_cleanup_message() {
  echo "\nactivate — shows cleanup message when clearing previous session"
  set_config
  run_sm_input "1" activate > /dev/null 2>&1
  local out
  out=$(run_sm_input "2" activate 2>&1)
  assert_contains "shows cleared message" "cleared" "$out"
}

# ---------------------------------------------------------------------------
# Tests: active / manifest
# ---------------------------------------------------------------------------

test_active_shows_installed_skills() {
  echo "\nactive — shows currently active skills"
  set_config
  run_sm_input "1" activate > /dev/null 2>&1
  local out
  out=$(run_sm active 2>&1)
  assert_contains "shows active skill" "clean-architecture" "$out"
  assert_contains "shows slash prefix" "/"                  "$out"
}

test_active_no_skills() {
  echo "\nactive — reports no skills when manifest is empty"
  set_config
  rm -f "$WORKDIR/.claude/.skill-manifest"
  local out
  out=$(run_sm active 2>&1)
  assert_contains "reports no skills" "No active skills" "$out"
}

test_manifest_tracks_only_installed() {
  echo "\nmanifest — tracks only installed skills"
  set_config
  run_sm_input "2 3" activate > /dev/null 2>&1
  local manifest
  manifest=$(cat "$WORKDIR/.claude/.skill-manifest")
  assert_contains     "manifest has owasp"   "owasp-security"     "$manifest"
  assert_contains     "manifest has senior"  "senior-architect"   "$manifest"
  assert_not_contains "manifest skips clean" "clean-architecture" "$manifest"
}

# ---------------------------------------------------------------------------
# Tests: config
# ---------------------------------------------------------------------------

test_config_show() {
  echo "\nconfig show — displays current config"
  set_config
  local out
  out=$(run_sm config show 2>&1)
  assert_contains "shows SKILLS_DIR" "SKILLS_DIR" "$out"
}

test_config_reset() {
  echo "\nconfig reset — removes config file"
  set_config
  run_sm config reset > /dev/null 2>&1
  assert_file_not_exists "config file removed" "$WORKDIR/.claude/.skill-manager.conf"
}

test_error_skills_dir_not_found() {
  echo "\nerror — skills dir not found"
  mkdir -p "$WORKDIR/.claude"
  echo 'SKILLS_DIR="nonexistent/path"' > "$WORKDIR/.claude/.skill-manager.conf"
  local out
  out=$(run_sm list 2>&1) || true
  assert_contains "shows error message" "error" "$out"
}

# ---------------------------------------------------------------------------
# Tests: selection modes
# ---------------------------------------------------------------------------

test_range_selection() {
  echo "\nactivate — range selection (e.g. 1-2)"
  set_config
  run_sm_input "1-2" activate > /dev/null 2>&1
  assert_dir_exists "first in range installed"  "$WORKDIR/.claude/skills/clean-architecture"
  assert_dir_exists "second in range installed" "$WORKDIR/.claude/skills/owasp-security"
}

test_all_selection() {
  echo "\nactivate — 'all' installs every valid skill"
  set_config
  run_sm_input "all" activate > /dev/null 2>&1
  assert_dir_exists "all: clean-architecture" "$WORKDIR/.claude/skills/clean-architecture"
  assert_dir_exists "all: owasp-security"     "$WORKDIR/.claude/skills/owasp-security"
  assert_dir_exists "all: senior-architect"   "$WORKDIR/.claude/skills/senior-architect"
}

# ---------------------------------------------------------------------------
# Runner
# ---------------------------------------------------------------------------

echo "skill-manager test suite"
echo "========================"

# Basic commands — clean environment
setup
test_help
test_version
test_list_first_run_asks_path
teardown

# Valid skills only
setup
test_list_shows_skills
test_activate_installs_as_directory
test_activate_keeps_frontmatter
test_activate_preserves_structure
test_activate_cleans_previous_session
test_activate_shows_cleanup_message
test_active_shows_installed_skills
test_active_no_skills
test_manifest_tracks_only_installed
test_config_show
test_config_reset
test_error_skills_dir_not_found
test_range_selection
test_all_selection
teardown

# Mixed valid + invalid skills
setup_mixed
test_validate_rejects_bad_name
teardown; setup_mixed
test_validate_rejects_no_frontmatter
teardown; setup_mixed
test_validate_rejects_bad_effort
teardown; setup_mixed
test_validate_rejects_bad_context
teardown; setup_mixed
test_validate_warns_no_description
teardown; setup_mixed
test_validate_installs_valid_skips_invalid
teardown; setup_mixed
test_validate_list_marks_invalid
teardown

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------

echo "\n========================"
echo "Results: ${PASS} passed, ${FAIL} failed"

if [[ ${FAIL} -gt 0 ]]; then
  echo "\nFailed tests:"
  for e in "${ERRORS[@]}"; do
    echo "  ✗ $e"
  done
  exit 1
fi
