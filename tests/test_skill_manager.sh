#!/usr/bin/env bash
set -euo pipefail

SCRIPT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/skill-manager"
VALID_FIXTURES="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/fixtures/sample-skills"
INVALID_FIXTURES="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/fixtures/invalid-skills"

# ---------------------------------------------------------------------------
# Mini test framework
# ---------------------------------------------------------------------------

PASS=0; FAIL=0; ERRORS=()

pass() { PASS=$((PASS + 1)); echo "  ✓ $1"; }
fail() { FAIL=$((FAIL + 1)); ERRORS+=("$1"); echo "  ✗ $1"; }

assert_contains()     { echo "$3" | grep -q "$2" && pass "$1" || fail "$1: expected '$2'"; }
assert_not_contains() { ! echo "$3" | grep -q "$2" && pass "$1" || fail "$1: did not expect '$2'"; }
assert_file_exists()      { [[ -f "$2" ]] && pass "$1" || fail "$1: file not found: $2"; }
assert_file_not_exists()  { [[ ! -f "$2" ]] && pass "$1" || fail "$1: should not exist: $2"; }
assert_dir_exists()       { [[ -d "$2" ]] && pass "$1" || fail "$1: dir not found: $2"; }
assert_dir_not_exists()   { [[ ! -d "$2" ]] && pass "$1" || fail "$1: should not exist: $2"; }

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

teardown() { rm -rf "$WORKDIR"; }

run_sm()       { (cd "$WORKDIR" && bash "$SCRIPT" "$@"); }
run_sm_input() { local i="$1"; shift; (cd "$WORKDIR" && printf "%s\n" "$i" | bash "$SCRIPT" "$@"); }

set_config() {
  mkdir -p "$WORKDIR/.claude"
  echo 'SKILLS_DIR="skills"' > "$WORKDIR/.claude/.skill-manager.conf"
}

set_global_config() {
  echo "GLOBAL_SKILLS_DIR=\"$1\"" > "$WORKDIR/.skill-manager-global.conf"
  # override global conf path via env not possible; use a separate global dir fixture instead
  # For global tests we use HOME override trick
}

# ---------------------------------------------------------------------------
# Tests: basic commands
# ---------------------------------------------------------------------------

test_help() {
  echo "\nhelp / usage"
  local out; out=$(run_sm help 2>&1) || true
  assert_contains "shows start cmd"   "start"   "$out"
  assert_contains "shows resume cmd"  "resume"  "$out"
  assert_contains "shows stop cmd"    "stop"    "$out"
  assert_contains "shows list cmd"    "list"    "$out"
}

test_version() {
  echo "\nversion"
  local out; out=$(run_sm version 2>&1)
  assert_contains "shows version" "1.0.0" "$out"
}

test_list_first_run_asks_path() {
  echo "\nlist — first run asks for skills path"
  local out; out=$(run_sm_input "skills" list 2>&1) || true
  assert_contains "prompts for path" "relative path" "$out"
  assert_contains "saves config"     "config saved"  "$out"
}

test_list_shows_skills() {
  echo "\nlist — shows skills with repo section header"
  set_config
  local out; out=$(run_sm list 2>&1)
  assert_contains "shows repo header"         "repo"               "$out"
  assert_contains "shows owasp-security"      "owasp-security"     "$out"
  assert_contains "shows clean-architecture"  "clean-architecture" "$out"
  assert_contains "shows senior-architect"    "senior-architect"   "$out"
}

# ---------------------------------------------------------------------------
# Tests: start
# ---------------------------------------------------------------------------

test_start_asks_path_first_time() {
  echo "\nstart — asks for skills path on first run"
  local out; out=$(run_sm_input $'skills\n1' start 2>&1) || true
  assert_contains "prompts for path" "relative path" "$out"
  assert_file_exists "config created" "$WORKDIR/.claude/.skill-manager.conf"
}

test_start_clears_previous_and_installs() {
  echo "\nstart — clears previous session and installs selected"
  set_config
  run_sm_input "3" start > /dev/null 2>&1 || true
  assert_dir_exists "senior-architect active" "$WORKDIR/.claude/skills/senior-architect"
  run_sm_input "1" start > /dev/null 2>&1 || true
  assert_dir_not_exists "senior-architect cleared" "$WORKDIR/.claude/skills/senior-architect"
  assert_dir_exists     "new skill installed"      "$WORKDIR/.claude/skills/clean-architecture"
}

test_start_shows_cleared_message() {
  echo "\nstart — shows cleared message on second run"
  set_config
  run_sm_input "1" start > /dev/null 2>&1
  local out; out=$(run_sm_input "2" start 2>&1)
  assert_contains "shows cleared message" "cleared" "$out"
}

test_start_installs_as_directory() {
  echo "\nstart — installs skill as full directory"
  set_config
  run_sm_input "1 2" start > /dev/null 2>&1
  assert_dir_exists     "skill 1 installed" "$WORKDIR/.claude/skills/clean-architecture"
  assert_dir_exists     "skill 2 installed" "$WORKDIR/.claude/skills/owasp-security"
  assert_dir_not_exists "skill 3 not selected" "$WORKDIR/.claude/skills/senior-architect"
}

test_start_keeps_frontmatter() {
  echo "\nstart — keeps YAML frontmatter intact"
  set_config
  run_sm_input "2" start > /dev/null 2>&1
  local content; content=$(cat "$WORKDIR/.claude/skills/owasp-security/SKILL.md")
  assert_contains "frontmatter present"  "^---"   "$content"
  assert_contains "name field present"   "^name:" "$content"
  assert_contains "content present"      "OWASP"  "$content"
}

test_start_preserves_structure() {
  echo "\nstart — preserves full directory structure"
  set_config
  run_sm_input "1 3" start > /dev/null 2>&1
  assert_file_exists "SKILL.md present"       "$WORKDIR/.claude/skills/clean-architecture/SKILL.md"
  assert_file_exists "extra file preserved"   "$WORKDIR/.claude/skills/clean-architecture/examples.md"
  assert_file_exists "references preserved"   "$WORKDIR/.claude/skills/senior-architect/references/patterns.md"
}

test_start_range_selection() {
  echo "\nstart — range selection (1-2)"
  set_config
  run_sm_input "1-2" start > /dev/null 2>&1
  assert_dir_exists "first in range"  "$WORKDIR/.claude/skills/clean-architecture"
  assert_dir_exists "second in range" "$WORKDIR/.claude/skills/owasp-security"
}

test_start_all_selection() {
  echo "\nstart — 'all' installs every valid skill"
  set_config
  run_sm_input "all" start > /dev/null 2>&1
  assert_dir_exists "clean-architecture" "$WORKDIR/.claude/skills/clean-architecture"
  assert_dir_exists "owasp-security"     "$WORKDIR/.claude/skills/owasp-security"
  assert_dir_exists "senior-architect"   "$WORKDIR/.claude/skills/senior-architect"
}

# ---------------------------------------------------------------------------
# Tests: resume
# ---------------------------------------------------------------------------

test_resume_no_active_skills() {
  echo "\nresume — warns when no active skills"
  set_config
  local out; out=$(run_sm resume 2>&1) || true
  assert_contains "suggests start" "start" "$out"
}

test_resume_shows_active_skills() {
  echo "\nresume — shows currently active skills"
  set_config
  run_sm_input "1" start > /dev/null 2>&1
  local out; out=$(run_sm_input "" resume 2>&1) || true
  assert_contains "shows active skill"  "clean-architecture" "$out"
  assert_contains "shows Active header" "Active skills"      "$out"
}

test_resume_shows_only_non_active() {
  echo "\nresume — shows only non-active skills in add menu"
  set_config
  run_sm_input "1" start > /dev/null 2>&1 || true
  local out; out=$(run_sm_input "" resume 2>&1) || true
  assert_contains "shows non-active skill"  "owasp-security"   "$out"
  assert_contains "shows available to add"  "Available to add"  "$out"
}

test_resume_adds_without_clearing() {
  echo "\nresume — adds new skills without removing active ones"
  set_config
  run_sm_input "1" start > /dev/null 2>&1 || true
  assert_dir_exists "skill 1 active before resume" "$WORKDIR/.claude/skills/clean-architecture"
  run_sm_input "1" resume > /dev/null 2>&1 || true
  assert_dir_exists "skill 1 still active after resume" "$WORKDIR/.claude/skills/clean-architecture"
  assert_dir_exists "skill 2 added by resume"           "$WORKDIR/.claude/skills/owasp-security"
}

test_resume_all_active_reports_done() {
  echo "\nresume — reports all skills active when nothing left to add"
  set_config
  run_sm_input "all" start > /dev/null 2>&1
  local out; out=$(run_sm resume 2>&1) || true
  assert_contains "reports all active" "already active" "$out"
}

# ---------------------------------------------------------------------------
# Tests: stop
# ---------------------------------------------------------------------------

test_stop_removes_all_skills() {
  echo "\nstop — removes all active skills"
  set_config
  run_sm_input "1 2" start > /dev/null 2>&1 || true
  assert_dir_exists "skill present before stop" "$WORKDIR/.claude/skills/clean-architecture"
  run_sm stop > /dev/null 2>&1 || true
  assert_dir_not_exists "skill removed after stop" "$WORKDIR/.claude/skills/clean-architecture"
  assert_dir_not_exists "skill removed after stop" "$WORKDIR/.claude/skills/owasp-security"
}

test_stop_removes_manifest() {
  echo "\nstop — removes manifest file"
  set_config
  run_sm_input "1" start > /dev/null 2>&1 || true
  run_sm stop > /dev/null 2>&1 || true
  assert_file_not_exists "manifest removed" "$WORKDIR/.claude/.skill-manifest"
}

test_stop_no_skills() {
  echo "\nstop — reports nothing to remove when no active skills"
  set_config
  local out; out=$(run_sm stop 2>&1)
  assert_contains "reports nothing" "No active" "$out"
}

# ---------------------------------------------------------------------------
# Tests: active command
# ---------------------------------------------------------------------------

test_active_shows_skills() {
  echo "\nactive — shows currently active skills"
  set_config
  run_sm_input "1" start > /dev/null 2>&1
  local out; out=$(run_sm active 2>&1)
  assert_contains "shows skill"  "clean-architecture" "$out"
  assert_contains "shows slash"  "/"                  "$out"
}

test_active_no_skills() {
  echo "\nactive — reports no active skills"
  set_config
  rm -f "$WORKDIR/.claude/.skill-manifest"
  local out; out=$(run_sm active 2>&1)
  assert_contains "reports none" "No active skills" "$out"
}

# ---------------------------------------------------------------------------
# Tests: validation
# ---------------------------------------------------------------------------

test_validate_rejects_bad_name() {
  echo "\nvalidation — rejects invalid name"
  set_config
  local out; out=$(run_sm_input "all" start 2>&1) || true
  assert_contains     "bad-name reported"    "bad-name"    "$out"
  assert_contains     "skipped shown"        "skipped"     "$out"
  assert_dir_not_exists "bad-name not installed" "$WORKDIR/.claude/skills/bad-name"
}

test_validate_rejects_no_frontmatter() {
  echo "\nvalidation — rejects missing frontmatter"
  set_config
  run_sm_input "all" start > /dev/null 2>&1 || true
  assert_dir_not_exists "no-frontmatter not installed" "$WORKDIR/.claude/skills/no-frontmatter"
}

test_validate_rejects_bad_effort() {
  echo "\nvalidation — rejects invalid effort value"
  set_config
  run_sm_input "all" start > /dev/null 2>&1 || true
  assert_dir_not_exists "bad-effort not installed" "$WORKDIR/.claude/skills/bad-effort"
}

test_validate_rejects_bad_context() {
  echo "\nvalidation — rejects invalid context value"
  set_config
  run_sm_input "all" start > /dev/null 2>&1 || true
  assert_dir_not_exists "bad-context not installed" "$WORKDIR/.claude/skills/bad-context"
}

test_validate_warns_no_description() {
  echo "\nvalidation — warns but installs skill with no description"
  set_config
  local out; out=$(run_sm_input "all" start 2>&1) || true
  assert_contains   "warning shown"             "description"          "$out"
  assert_dir_exists "no-description installed"  "$WORKDIR/.claude/skills/no-description"
}

test_validate_installs_valid_skips_invalid() {
  echo "\nvalidation — installs valid, skips invalid"
  set_config
  run_sm_input "all" start > /dev/null 2>&1 || true
  assert_dir_exists     "owasp installed"          "$WORKDIR/.claude/skills/owasp-security"
  assert_dir_exists     "clean-arch installed"     "$WORKDIR/.claude/skills/clean-architecture"
  assert_dir_not_exists "bad-name skipped"         "$WORKDIR/.claude/skills/bad-name"
  assert_dir_not_exists "no-frontmatter skipped"   "$WORKDIR/.claude/skills/no-frontmatter"
  assert_dir_not_exists "bad-effort skipped"       "$WORKDIR/.claude/skills/bad-effort"
  assert_dir_not_exists "bad-context skipped"      "$WORKDIR/.claude/skills/bad-context"
}

test_validate_list_marks_invalid() {
  echo "\nvalidation — list marks invalid skills"
  set_config
  local out; out=$(run_sm list 2>&1)
  assert_contains "bad-name shown"       "bad-name"       "$out"
  assert_contains "no-frontmatter shown" "no-frontmatter" "$out"
  assert_contains "bad-effort shown"     "bad-effort"     "$out"
  assert_contains "bad-context shown"    "bad-context"    "$out"
}

# ---------------------------------------------------------------------------
# Tests: config
# ---------------------------------------------------------------------------

test_config_show() {
  echo "\nconfig — show displays repo and global config"
  set_config
  local out; out=$(run_sm config show 2>&1)
  assert_contains "shows SKILLS_DIR"     "SKILLS_DIR"   "$out"
  assert_contains "shows global section" "Global config" "$out"
}

test_config_reset() {
  echo "\nconfig — reset removes repo config"
  set_config
  run_sm config reset > /dev/null 2>&1
  assert_file_not_exists "config removed" "$WORKDIR/.claude/.skill-manager.conf"
}

test_error_skills_dir_not_found() {
  echo "\nerror — skills dir not found"
  mkdir -p "$WORKDIR/.claude"
  echo 'SKILLS_DIR="nonexistent"' > "$WORKDIR/.claude/.skill-manager.conf"
  local out; out=$(run_sm list 2>&1) || true
  assert_contains "shows error" "error" "$out"
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
teardown

setup
test_list_shows_skills
teardown; setup
test_start_asks_path_first_time
teardown; setup
test_start_clears_previous_and_installs
teardown; setup
test_start_shows_cleared_message
teardown; setup
test_start_installs_as_directory
teardown; setup
test_start_keeps_frontmatter
teardown; setup
test_start_preserves_structure
teardown; setup
test_start_range_selection
teardown; setup
test_start_all_selection
teardown; setup
test_resume_no_active_skills
teardown; setup
test_resume_shows_active_skills
teardown; setup
test_resume_shows_only_non_active
teardown; setup
test_resume_adds_without_clearing
teardown; setup
test_resume_all_active_reports_done
teardown; setup
test_stop_removes_all_skills
teardown; setup
test_stop_removes_manifest
teardown; setup
test_stop_no_skills
teardown; setup
test_active_shows_skills
teardown; setup
test_active_no_skills
teardown; setup
test_config_show
teardown; setup
test_config_reset
teardown; setup
test_error_skills_dir_not_found
teardown

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

echo "\n========================"
echo "Results: ${PASS} passed, ${FAIL} failed"

if [[ ${FAIL} -gt 0 ]]; then
  echo "\nFailed tests:"
  for e in "${ERRORS[@]}"; do echo "  ✗ $e"; done
  exit 1
fi
