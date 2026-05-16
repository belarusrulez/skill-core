#!/bin/sh
# Test harness for sc:search + sc:crud.
#
# Each test is a function `t_NN()` returning 0 on pass, non-zero on fail.
# State: every test gets a fresh sandboxed $SC_HOME and $AGENT_SKILLS_DIR via
#   t_setup; teardown is implicit at next setup. Test output is captured to
#   $OUT/$ERR and exit status to $RC.
#
# Usage:
#   sh test/run-tests.sh                # run all
#   sh test/run-tests.sh T-01 T-02 T-30 # run specific tests by name
#   sh test/run-tests.sh -v T-01        # verbose (echo actual vs expected on fail)

set -u

# ----- locate scripts (relative to this file) -----
HERE=$(cd "$(dirname "$0")" && pwd)
ROOT=$(cd "$HERE/.." && pwd)
SEARCH="$ROOT/sc/search/action"
SKILL="$ROOT/sc/crud/action"
FIX="$ROOT/test/skills"

# ----- output helpers (no colors — keep portable) -----
VERBOSE=0
PASS_N=0
FAIL_N=0
SKIP_N=0
FAIL_LIST=""

note()  { printf '%s\n' "$*" >&2; }
pass()  { PASS_N=$((PASS_N + 1)); printf '  PASS %s\n' "$1"; }
fail()  {
  FAIL_N=$((FAIL_N + 1))
  FAIL_LIST="$FAIL_LIST $1"
  printf '  FAIL %s — %s\n' "$1" "$2"
  if [ "$VERBOSE" = 1 ]; then
    printf '       rc=%s\n' "$RC"
    printf '       stdout:\n'
    sed 's/^/         /' "$OUT" 2>/dev/null
    printf '       stderr:\n'
    sed 's/^/         /' "$ERR" 2>/dev/null
  fi
}
skip()  { SKIP_N=$((SKIP_N + 1)); printf '  SKIP %s — %s\n' "$1" "$2"; }

# ----- per-test sandbox -----
t_setup() {
  TDIR=$(mktemp -d -t sc-test.XXXXXX)
  export SC_HOME="$TDIR/sc"
  mkdir -p "$SC_HOME" "$AGENT_SKILLS_DIR"
  OUT="$TDIR/out"
  ERR="$TDIR/err"
  : > "$OUT"
  : > "$ERR"
  RC=0
}

# Write a repos.patterns line "<root>\t<pattern>".
t_patterns() {
  printf "%s\t%s\n" "$1" "${2:-*}" >> "$SC_HOME/repos.patterns"
}

# Run a command, capture stdout/stderr/exit-code.
run() {
  "$@" > "$OUT" 2> "$ERR"
  RC=$?
}
run_sh() {
  # for shell-quoted commands
  sh -c "$1" > "$OUT" 2> "$ERR"
  RC=$?
}

# Assertions — emit PASS or FAIL. Each test calls a series; if any fails,
# the test returns non-zero.
assert_rc() {
  if [ "$RC" = "$1" ]; then return 0; fi
  fail "$TNAME" "expected exit $1, got $RC"; return 1
}
assert_stdout_contains() {
  if grep -q -- "$1" "$OUT"; then return 0; fi
  fail "$TNAME" "stdout missing: $1"; return 1
}
assert_stdout_not_contains() {
  if ! grep -q -- "$1" "$OUT"; then return 0; fi
  fail "$TNAME" "stdout unexpectedly contained: $1"; return 1
}
assert_stderr_contains() {
  if grep -q -- "$1" "$ERR"; then return 0; fi
  fail "$TNAME" "stderr missing: $1"; return 1
}
assert_stderr_not_contains() {
  if ! grep -q -- "$1" "$ERR"; then return 0; fi
  fail "$TNAME" "stderr unexpectedly contained: $1"; return 1
}
assert_stdout_empty() {
  if [ ! -s "$OUT" ]; then return 0; fi
  fail "$TNAME" "stdout was not empty"; return 1
}
assert_stderr_empty() {
  if [ ! -s "$ERR" ]; then return 0; fi
  fail "$TNAME" "stderr was not empty"; return 1
}
assert_file_exists() {
  if [ -f "$1" ]; then return 0; fi
  fail "$TNAME" "expected file: $1"; return 1
}
assert_eq() {
  if [ "$1" = "$2" ]; then return 0; fi
  fail "$TNAME" "expected '$2', got '$1'"; return 1
}

# Common preconditions for tests that need an index built off $FIX.
t_with_fixtures() {
  t_setup
  t_patterns "$FIX"
  "$SEARCH" reindex > "$OUT.reindex" 2>&1 || return 1
}

# ============================================================================
# Section 1: sc:search — argument / flag tests (T-01..T-14)
# ============================================================================

t_T_01() {
  TNAME=T-01
  t_setup; t_patterns "$FIX"; "$SEARCH" reindex >/dev/null 2>&1
  run "$SEARCH" search
  assert_rc 2 || return 1
  assert_stderr_contains "search requires at least one query string" || return 1
  pass "$TNAME"
}

t_T_02() {
  TNAME=T-02
  t_with_fixtures || { fail "$TNAME" "reindex setup failed"; return 1; }
  run "$SEARCH" search rebase
  assert_rc 0 || return 1
  assert_stderr_contains "fewer than 3 queries" || return 1
  assert_stdout_contains "## Convergence" || return 1
  assert_stdout_contains "## Single-axis hits" || return 1
  pass "$TNAME"
}

t_T_03() {
  TNAME=T-03
  t_with_fixtures || { fail "$TNAME" "reindex setup failed"; return 1; }
  run "$SEARCH" search rebase "branch rewrite"
  assert_rc 0 || return 1
  assert_stderr_contains "fewer than 3 queries" || return 1
  pass "$TNAME"
}

t_T_04() {
  TNAME=T-04
  t_with_fixtures || { fail "$TNAME" "reindex setup failed"; return 1; }
  run "$SEARCH" search rebase "branch rewrite" "fixup commits"
  assert_rc 0 || return 1
  assert_stderr_not_contains "fewer than 3 queries" || return 1
  pass "$TNAME"
}

t_T_05() {
  TNAME=T-05
  t_with_fixtures || { fail "$TNAME" "reindex setup failed"; return 1; }
  run "$SEARCH" search a b c d e
  assert_rc 0 || true   # could be 0 or 1 depending on whether anything matches
  assert_stderr_not_contains "fewer than 3 queries" || return 1
  pass "$TNAME"
}

t_T_06() {
  TNAME=T-06
  t_with_fixtures || { fail "$TNAME" "reindex setup failed"; return 1; }
  run "$SEARCH" search git rebase commit
  cp "$OUT" "$TDIR/out.subcommand"
  run "$SEARCH" git rebase commit
  cp "$OUT" "$TDIR/out.bare"
  if diff -q "$TDIR/out.subcommand" "$TDIR/out.bare" >/dev/null 2>&1; then
    pass "$TNAME"
    return 0
  fi
  fail "$TNAME" "bare invocation differs from explicit 'search'"; return 1
}

t_T_07() {
  TNAME=T-07
  t_with_fixtures || { fail "$TNAME" "reindex setup failed"; return 1; }
  run "$SEARCH" --limit 3 git rebase commit
  assert_rc 0 || return 1
  # Count rows in both sections (skip header lines and blank lines).
  # Convergence + Single-axis rows are lines starting with "  " followed by
  # either '*' or ' ' then a name; the only marker we can rely on is "axes=".
  rows=$(grep -c "axes=" "$OUT" || true)
  if [ "$rows" -le 3 ]; then
    pass "$TNAME"
    return 0
  fi
  fail "$TNAME" "expected <=3 rows total, got $rows"; return 1
}

t_T_08() {
  TNAME=T-08
  t_with_fixtures || { fail "$TNAME" "reindex setup failed"; return 1; }
  run "$SEARCH" --format tsv git rebase commit
  assert_rc 0 || return 1
  assert_stdout_not_contains "## Convergence" || return 1
  # Every non-empty line should have exactly 6 tabs (7 fields).
  bad=0
  while IFS= read -r line; do
    [ -n "$line" ] || continue
    n=$(printf "%s" "$line" | awk -F'\t' '{print NF}')
    [ "$n" = "7" ] || { bad=$((bad + 1)); break; }
  done < "$OUT"
  if [ "$bad" = "0" ]; then pass "$TNAME"; return 0; fi
  fail "$TNAME" "tsv row had != 7 tab-separated fields"; return 1
}

t_T_09() {
  TNAME=T-09
  t_with_fixtures || { fail "$TNAME" "reindex setup failed"; return 1; }
  run "$SEARCH" --format json git rebase commit
  assert_rc 0 || return 1
  # Validate via sqlite3's json_valid() — POSIX-stock and stronger than the
  # brace-balance heuristic. readfile() returns 0 if json is malformed, 1 if OK.
  valid=$(printf "select json_valid(readfile('%s'));\n" "$OUT" | sqlite3)
  if [ "$valid" = "1" ]; then pass "$TNAME"; return 0; fi
  fail "$TNAME" "sqlite3 json_valid returned $valid (expected 1) for $OUT"; return 1
}

t_T_10() {
  TNAME=T-10
  t_with_fixtures || { fail "$TNAME" "reindex setup failed"; return 1; }
  run "$SEARCH" search -- --weird-query
  # Exit may be 0 or 1 (no hits). Critical: must NOT be 2 (unknown-flag error).
  if [ "$RC" = "2" ]; then
    fail "$TNAME" "'-- --weird-query' was misinterpreted as unknown flag"
    return 1
  fi
  assert_stderr_not_contains "unknown flag" || return 1
  pass "$TNAME"
}

t_T_11() {
  TNAME=T-11
  t_with_fixtures || { fail "$TNAME" "reindex setup failed"; return 1; }
  run "$SEARCH" search --nope foo
  assert_rc 2 || return 1
  assert_stderr_contains "unknown flag: --nope" || return 1
  pass "$TNAME"
}

t_T_12() {
  TNAME=T-12
  t_with_fixtures || { fail "$TNAME" "reindex setup failed"; return 1; }
  run "$SEARCH" search --format xml a b c
  assert_rc 2 || return 1
  assert_stderr_contains "unknown format: xml" || return 1
  pass "$TNAME"
}

t_T_13() {
  TNAME=T-13
  t_with_fixtures || { fail "$TNAME" "reindex setup failed"; return 1; }
  run "$SEARCH" --limit 5 git rebase commit
  assert_rc 0 || return 1
  # Same query with explicit `search` for comparison: identical stdout
  cp "$OUT" "$TDIR/out.leading-flag"
  run "$SEARCH" search --limit 5 git rebase commit
  cp "$OUT" "$TDIR/out.explicit"
  if diff -q "$TDIR/out.leading-flag" "$TDIR/out.explicit" >/dev/null 2>&1; then
    pass "$TNAME"; return 0
  fi
  fail "$TNAME" "leading --flag doesn't route to search identically"; return 1
}

t_T_14() {
  TNAME=T-14
  # Deferred per dev/QA exchange (--repo for search is intentionally NOT implemented).
  skip "$TNAME" "--repo for sc:search search is not in spec (deferred)"
}

# ============================================================================
# Section 2: sc:search — subcommand & exit-code tests (T-20..T-33)
# ============================================================================

t_T_20() {
  TNAME=T-20
  t_setup; t_patterns "$FIX"
  run "$SEARCH" list-roots
  assert_rc 0 || return 1
  expected="$FIX"
  actual=$(cat "$OUT")
  assert_eq "$actual" "$expected" || return 1
  pass "$TNAME"
}

t_T_21() {
  TNAME=T-21
  t_setup
  run "$SEARCH" list-roots
  assert_rc 2 || return 1
  assert_stderr_contains "no .*/repos.patterns" || return 1
  pass "$TNAME"
}

t_T_22() {
  TNAME=T-22
  t_setup; t_patterns "$FIX"
  run "$SEARCH" reindex
  assert_rc 0 || return 1
  assert_stdout_contains "indexed 25 skill(s)" || return 1
  assert_file_exists "$SC_HOME/search/index.db" || return 1
  # Re-run with --full as a no-op flag.
  run "$SEARCH" reindex --full
  assert_rc 0 || return 1
  pass "$TNAME"
}

t_T_22b() {
  TNAME=T-22b
  # reindex --full = no-op alias of reindex; reindex --bogus = exit 1.
  t_setup; t_patterns "$FIX"
  "$SEARCH" reindex > "$TDIR/out.bare" 2>&1
  "$SEARCH" reindex --full > "$TDIR/out.full" 2>&1
  # Both should report "indexed 25 skill(s)" — they target the same index.db.
  if ! grep -q "indexed 25 skill" "$TDIR/out.bare"; then
    fail "$TNAME" "bare reindex didn't emit 'indexed 25 skill'"; return 1
  fi
  if ! grep -q "indexed 25 skill" "$TDIR/out.full"; then
    fail "$TNAME" "reindex --full didn't emit 'indexed 25 skill'"; return 1
  fi
  # Unknown flag → exit 1 (NOT 2).
  run "$SEARCH" reindex --bogus
  assert_rc 1 || return 1
  assert_stderr_contains "unknown reindex flag: --bogus" || return 1
  pass "$TNAME"
}

t_T_23() {
  TNAME=T-23
  t_setup
  EMPTY_ROOT="$TDIR/empty-root"
  mkdir -p "$EMPTY_ROOT"
  t_patterns "$EMPTY_ROOT"
  run "$SEARCH" reindex
  assert_rc 3 || return 1
  assert_stderr_contains "tmp index is empty" || return 1
  pass "$TNAME"
}

t_T_24() {
  TNAME=T-24
  t_setup
  run "$SEARCH" doctor --write-sample
  assert_rc 0 || return 1
  assert_stdout_contains "wrote sample" || return 1
  assert_file_exists "$SC_HOME/repos.patterns" || return 1
  pass "$TNAME"
}

t_T_25() {
  TNAME=T-25
  t_setup
  printf "# pre-existing custom content\n%s\t*\n" "$FIX" > "$SC_HOME/repos.patterns"
  before=$(cat "$SC_HOME/repos.patterns")
  run "$SEARCH" doctor --write-sample
  assert_rc 0 || return 1
  assert_stdout_contains "exists:" || return 1
  assert_stdout_contains "not overwriting" || return 1
  after=$(cat "$SC_HOME/repos.patterns")
  if [ "$before" = "$after" ]; then pass "$TNAME"; return 0; fi
  fail "$TNAME" "patterns file was modified despite 'not overwriting' message"; return 1
}

t_T_26() {
  TNAME=T-26
  t_setup
  t_patterns "$AGENT_SKILLS_DIR"
  run "$SEARCH" doctor
  assert_rc 2 || return 1
  assert_stderr_contains "root may not be the agent skill-registration dir" || return 1
  pass "$TNAME"
}

t_T_27() {
  TNAME=T-27
  t_setup
  t_patterns "/no/such/dir-$$"
  run "$SEARCH" doctor
  # Exit 0 (warn-only), stderr WARN.
  assert_rc 0 || return 1
  assert_stderr_contains "root does not exist" || return 1
  pass "$TNAME"
}

t_T_28() {
  TNAME=T-28
  t_setup
  t_patterns "$FIX"
  t_patterns "$FIX"
  run "$SEARCH" doctor
  assert_rc 0 || return 1
  assert_stderr_contains "duplicate root" || return 1
  pass "$TNAME"
}

t_T_29() {
  TNAME=T-29
  t_with_fixtures || { fail "$TNAME" "reindex setup failed"; return 1; }
  run "$SEARCH" search zzzzzz_nomatch qqqqq_nope xxxx_void
  assert_rc 1 || return 1
  assert_stdout_contains "no skills matched" || return 1
  pass "$TNAME"
}

t_T_30() {
  TNAME=T-30
  t_setup; t_patterns "$FIX"
  rm -f "$SC_HOME/search/index.db"
  run "$SEARCH" search git foo bar
  # Exit may be 0 (hits) or 1 (no hits). What we check: the index.db now exists
  # AND stderr shows the auto-rebuild line.
  if [ "$RC" != "0" ] && [ "$RC" != "1" ]; then
    fail "$TNAME" "expected exit 0 or 1, got $RC"; return 1
  fi
  assert_stderr_contains "indexed " || return 1
  assert_file_exists "$SC_HOME/search/index.db" || return 1
  pass "$TNAME"
}

t_T_31() {
  TNAME=T-31
  # A corrupt index.db is self-healed by the hash-based auto-reindex that
  # runs on every invocation: the on-disk hash won't match the live skill
  # set, so reindex fires and atomically replaces the bad file.
  t_setup; t_patterns "$FIX"
  mkdir -p "$SC_HOME/search"
  printf "not-a-db\n" > "$SC_HOME/search/index.db"
  run "$SEARCH" search git foo bar
  if [ "$RC" != "0" ] && [ "$RC" != "1" ]; then
    fail "$TNAME" "expected exit 0 or 1 (self-heal), got $RC"; return 1
  fi
  assert_stderr_contains "indexed " || return 1
  pass "$TNAME"
}

t_T_32() {
  TNAME=T-32
  t_setup
  run "$SEARCH"
  assert_rc 2 || return 1
  assert_stdout_contains "usage:" || return 1
  pass "$TNAME"
}

t_T_33() {
  TNAME=T-33
  t_setup
  run "$SEARCH" --help
  assert_rc 0 || return 1
  assert_stdout_contains "usage:" || return 1
  pass "$TNAME"
}

t_T_34() {
  TNAME=T-34
  # Symlink dispatch: invoking the action via a symlink (e.g. ~/.sc/search/action
  # → /Users/coding/.../sc/search/action) must still resolve the sibling
  # ../lib/discover.sh — verified by running list-roots through a /tmp symlink.
  t_setup
  t_patterns "$FIX"
  alias_path="$TDIR/sc-alias-$$"
  ln -sf "$SEARCH" "$alias_path"
  # Direct invocation baseline
  "$SEARCH" list-roots > "$TDIR/out.direct" 2>"$TDIR/err.direct"
  rc_direct=$?
  # Via symlink
  "$alias_path" list-roots > "$TDIR/out.alias" 2>"$TDIR/err.alias"
  rc_alias=$?
  rm -f "$alias_path"
  if [ "$rc_direct" != "$rc_alias" ]; then
    fail "$TNAME" "exit codes differ (direct=$rc_direct vs alias=$rc_alias)"; return 1
  fi
  if ! diff -q "$TDIR/out.direct" "$TDIR/out.alias" >/dev/null 2>&1; then
    fail "$TNAME" "stdout differs between direct and symlink invocation"; return 1
  fi
  # Symlink invocation must NOT emit the 'missing helper library' fatal.
  if grep -q "missing helper library" "$TDIR/err.alias"; then
    fail "$TNAME" "symlink invocation failed to resolve helper library"; return 1
  fi
  pass "$TNAME"
}

# ============================================================================
# Section 3: sc:crud lifecycle tests (T-40..T-66)
# ============================================================================
#
# Most lifecycle tests need a WRITABLE repo (separate from $FIX) so create/delete
# don't mutate the fixtures. Convention:
#   $FIX = read-only 25-fixture root
#   $WR  = writable second root, registered alongside $FIX
# t_with_writable_repo registers both and sets $WR as default_repo. After this,
# any create that doesn't specify --repo lands in $WR.

t_with_writable_repo() {
  t_setup
  WR="$TDIR/writable/skills"
  mkdir -p "$WR"
  t_patterns "$FIX"
  t_patterns "$WR"
  printf "%s\n" "$WR" > "$SC_HOME/default_repo"
}

t_T_40() {
  TNAME=T-40
  t_with_writable_repo
  run "$SKILL" list
  assert_rc 0 || return 1
  rows=$(wc -l < "$OUT" | tr -d ' ')
  if [ "$rows" -lt 25 ]; then
    fail "$TNAME" "expected >=25 rows, got $rows"; return 1
  fi
  # Format check: first line should have 3 tabs (4 fields)
  first=$(head -n 1 "$OUT")
  n=$(printf "%s" "$first" | awk -F'\t' '{print NF}')
  if [ "$n" != "4" ]; then
    fail "$TNAME" "first row has $n tab-separated fields, expected 4"; return 1
  fi
  pass "$TNAME"
}

t_T_41() {
  TNAME=T-41
  t_with_writable_repo
  run "$SKILL" repos
  assert_rc 0 || return 1
  assert_stdout_contains "$FIX" || return 1
  assert_stdout_contains "$WR" || return 1
  pass "$TNAME"
}

t_T_42() {
  TNAME=T-42
  t_with_writable_repo
  run "$SKILL" path git-rebase
  assert_rc 0 || return 1
  expected="$FIX/git-rebase"
  actual=$(cat "$OUT")
  assert_eq "$actual" "$expected" || return 1
  pass "$TNAME"
}

t_T_43() {
  TNAME=T-43
  t_with_writable_repo
  run "$SKILL" path nosuch-skill
  assert_rc 1 || return 1
  assert_stderr_contains "no such skill: nosuch-skill" || return 1
  pass "$TNAME"
}

t_T_44() {
  TNAME=T-44
  t_with_writable_repo
  run "$SKILL" create my-test --repo "$WR"
  assert_rc 0 || return 1
  assert_file_exists "$WR/my-test/SKILL.md" || return 1
  assert_file_exists "$WR/my-test/skill.sh" || return 1
  # tag_cloud.txt removed per user pivot — should NOT exist
  if [ -f "$WR/my-test/tag_cloud.txt" ]; then
    fail "$TNAME" "tag_cloud.txt unexpectedly created (should be dropped post-pivot)"
    return 1
  fi
  # Registration symlink
  if [ ! -L "$AGENT_SKILLS_DIR/my-test/SKILL.md" ]; then
    fail "$TNAME" "registration symlink missing"; return 1
  fi
  # Frontmatter `name:` field
  name_line=$(grep '^name:' "$WR/my-test/SKILL.md" | head -n 1)
  if [ "$name_line" != "name: my:test" ]; then
    fail "$TNAME" "expected 'name: my:test', got: $name_line"; return 1
  fi
  pass "$TNAME"
}

t_T_45() {
  TNAME=T-45
  t_with_writable_repo
  run "$SKILL" create git-bisect-helper --repo "$WR"
  assert_rc 0 || return 1
  name_line=$(grep '^name:' "$WR/git-bisect-helper/SKILL.md" | head -n 1)
  if [ "$name_line" != "name: git:bisect-helper" ]; then
    fail "$TNAME" "expected 'name: git:bisect-helper', got: $name_line"; return 1
  fi
  pass "$TNAME"
}

t_T_46() {
  TNAME=T-46
  t_with_writable_repo
  run "$SKILL" create foo --repo "$WR"
  assert_rc 0 || return 1
  name_line=$(grep '^name:' "$WR/foo/SKILL.md" | head -n 1)
  if [ "$name_line" != "name: foo" ]; then
    fail "$TNAME" "expected 'name: foo', got: $name_line"; return 1
  fi
  pass "$TNAME"
}

t_T_47() {
  TNAME=T-47
  t_with_writable_repo
  # git-rebase exists in $FIX; creating in $WR should collide globally.
  run "$SKILL" create git-rebase --repo "$WR"
  assert_rc 3 || return 1
  assert_stderr_contains "already exists in another repo" || return 1
  pass "$TNAME"
}

t_T_48() {
  TNAME=T-48
  # Two registered roots, no default → ambiguous
  t_setup
  WR="$TDIR/writable/skills"
  mkdir -p "$WR"
  t_patterns "$FIX"
  t_patterns "$WR"
  # No default_repo file
  run "$SKILL" create foo
  assert_rc 2 || return 1
  assert_stderr_contains "no --repo given" || return 1
  pass "$TNAME"
}

t_T_49() {
  TNAME=T-49
  t_with_writable_repo
  # default_repo is set by t_with_writable_repo to $WR
  run "$SKILL" create dflt-skill
  assert_rc 0 || return 1
  assert_file_exists "$WR/dflt-skill/SKILL.md" || return 1
  pass "$TNAME"
}

t_T_50() {
  TNAME=T-50
  t_with_writable_repo
  run "$SKILL" create "bad name!"
  assert_rc 1 || return 1
  assert_stderr_contains "invalid name" || return 1
  pass "$TNAME"
}

t_T_51() {
  TNAME=T-51
  t_with_writable_repo
  "$SKILL" create my-test --repo "$WR" >/dev/null 2>&1 || true
  run "$SKILL" delete --force my-test
  assert_rc 0 || return 1
  # Source gone
  if [ -d "$WR/my-test" ]; then
    fail "$TNAME" "source dir still exists after delete"; return 1
  fi
  # Trash entry created
  trash_count=$(find "$SC_HOME/trash" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | wc -l | tr -d ' ')
  if [ "$trash_count" != "1" ]; then
    fail "$TNAME" "expected 1 trash entry, got $trash_count"; return 1
  fi
  meta=$(find "$SC_HOME/trash" -mindepth 2 -maxdepth 2 -name '.sc-trash-meta.json' 2>/dev/null | head -n 1)
  if [ -z "$meta" ] || [ ! -f "$meta" ]; then
    fail "$TNAME" "no .sc-trash-meta.json in trash entry"; return 1
  fi
  if ! grep -q '"orig_path"' "$meta"; then
    fail "$TNAME" "meta missing orig_path"; return 1
  fi
  pass "$TNAME"
}

t_T_52() {
  TNAME=T-52
  t_with_writable_repo
  "$SKILL" create my-test --repo "$WR" >/dev/null 2>&1 || true
  "$SKILL" delete --force my-test >/dev/null 2>&1 || true
  meta=$(find "$SC_HOME/trash" -mindepth 2 -maxdepth 2 -name '.sc-trash-meta.json' 2>/dev/null | head -n 1)
  if [ -z "$meta" ]; then fail "$TNAME" "no meta file found"; return 1; fi
  for key in '"name"' '"orig_path"' '"deleted_at"'; do
    if ! grep -q -- "$key" "$meta"; then
      fail "$TNAME" "meta missing $key"; return 1
    fi
  done
  # ISO-Z deleted_at: 2026-05-15T20:27:12Z pattern
  if ! grep -E -q '"deleted_at": "[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z"' "$meta"; then
    fail "$TNAME" "deleted_at not ISO-Z format"; return 1
  fi
  # JSON shape: opens with { closes with }; balanced braces
  first=$(head -c 1 "$meta")
  if [ "$first" != "{" ]; then fail "$TNAME" "meta doesn't start with {"; return 1; fi
  opens=$(tr -cd '{' < "$meta" | wc -c | tr -d ' ')
  closes=$(tr -cd '}' < "$meta" | wc -c | tr -d ' ')
  if [ "$opens" != "$closes" ]; then
    fail "$TNAME" "meta brace count mismatch ($opens vs $closes)"; return 1
  fi
  pass "$TNAME"
}

t_T_53() {
  TNAME=T-53
  t_with_writable_repo
  run "$SKILL" delete --force nosuch-skill
  assert_rc 1 || return 1
  assert_stderr_contains "no such skill: nosuch-skill" || return 1
  pass "$TNAME"
}

t_T_54() {
  TNAME=T-54
  t_with_writable_repo
  "$SKILL" create my-test --repo "$WR" >/dev/null 2>&1 || true
  "$SKILL" delete --force my-test >/dev/null 2>&1 || true
  trash_id=$(find "$SC_HOME/trash" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | head -n 1 | xargs basename)
  if [ -z "$trash_id" ]; then fail "$TNAME" "no trash entry found"; return 1; fi
  run "$SKILL" restore "$trash_id"
  assert_rc 0 || return 1
  # Orig path restored
  assert_file_exists "$WR/my-test/SKILL.md" || return 1
  # Symlink recreated
  if [ ! -L "$AGENT_SKILLS_DIR/my-test/SKILL.md" ]; then
    fail "$TNAME" "registration symlink not recreated"; return 1
  fi
  # Meta file deleted inside restored dir
  if [ -f "$WR/my-test/.sc-trash-meta.json" ]; then
    fail "$TNAME" "trash meta file left inside restored dir"; return 1
  fi
  pass "$TNAME"
}

t_T_55() {
  TNAME=T-55
  t_with_writable_repo
  "$SKILL" create my-test --repo "$WR" >/dev/null 2>&1 || true
  "$SKILL" delete --force my-test >/dev/null 2>&1 || true
  trash_id=$(find "$SC_HOME/trash" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | head -n 1 | xargs basename)
  # Re-occupy the orig path
  mkdir -p "$WR/my-test"
  : > "$WR/my-test/SKILL.md"
  run "$SKILL" restore "$trash_id"
  assert_rc 3 || return 1
  assert_stderr_contains "orig_path already exists" || return 1
  pass "$TNAME"
}

t_T_56() {
  TNAME=T-56
  t_with_writable_repo
  "$SKILL" create to-purge --repo "$WR" >/dev/null 2>&1 || true
  run "$SKILL" delete --force --purge to-purge
  assert_rc 0 || return 1
  # Source gone
  if [ -d "$WR/to-purge" ]; then
    fail "$TNAME" "source still exists after purge"; return 1
  fi
  # No trash entry
  trash_count=$(find "$SC_HOME/trash" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | wc -l | tr -d ' ')
  if [ "$trash_count" != "0" ]; then
    fail "$TNAME" "purge created trash entry (count=$trash_count)"; return 1
  fi
  pass "$TNAME"
}

t_T_57() {
  TNAME=T-57
  t_with_writable_repo
  # Pre-relink so existing fixtures all have symlinks
  "$SKILL" relink >/dev/null 2>&1 || true
  run "$SKILL" validate
  assert_rc 0 || return 1
  # No FAIL rows in stdout
  if grep -q '^  FAIL' "$OUT"; then
    fail "$TNAME" "validate emitted FAIL rows for clean fixtures"; return 1
  fi
  pass "$TNAME"
}

# T-58 dropped — tag_cloud.txt removed by user pivot; no longer required.
t_T_58() {
  TNAME=T-58
  skip "$TNAME" "tag_cloud.txt removed by user pivot; no longer required by validate"
}

t_T_59() {
  TNAME=T-59
  t_with_writable_repo
  "$SKILL" relink >/dev/null 2>&1 || true
  # Pick one fixture and replace its SKILL.md with body-only (no frontmatter).
  target_dir="$FIX/git-rebase"
  backup="$TDIR/git-rebase.SKILL.md.backup"
  cp "$target_dir/SKILL.md" "$backup"
  printf "# body only — no frontmatter block\n" > "$target_dir/SKILL.md"
  run "$SKILL" validate git-rebase
  rc_save=$RC
  # Restore before we evaluate, so a failed assert doesn't leak state.
  cp "$backup" "$target_dir/SKILL.md"
  RC=$rc_save
  assert_rc 1 || return 1
  assert_stdout_contains "no frontmatter" || return 1
  pass "$TNAME"
}

t_T_60() {
  TNAME=T-60
  t_with_writable_repo
  "$SKILL" relink >/dev/null 2>&1 || true
  target_dir="$FIX/git-rebase"
  backup="$TDIR/git-rebase.SKILL.md.backup"
  cp "$target_dir/SKILL.md" "$backup"
  # Write a SKILL.md with frontmatter but no description.
  cat > "$target_dir/SKILL.md" <<EOF
---
name: git:rebase
---

body
EOF
  run "$SKILL" validate git-rebase
  rc_save=$RC
  cp "$backup" "$target_dir/SKILL.md"
  RC=$rc_save
  assert_rc 1 || return 1
  assert_stdout_contains "missing description: field" || return 1
  pass "$TNAME"
}

t_T_61() {
  TNAME=T-61
  t_with_writable_repo
  run "$SKILL" validate nosuch-skill
  assert_rc 1 || return 1
  assert_stderr_contains "no such skill: nosuch-skill" || return 1
  pass "$TNAME"
}

t_T_62() {
  TNAME=T-62
  t_with_writable_repo
  rm -rf "$AGENT_SKILLS_DIR"
  mkdir -p "$AGENT_SKILLS_DIR"
  run "$SKILL" relink
  assert_rc 0 || return 1
  # Every fixture under $FIX should now have a symlink
  miss=0
  for d in "$FIX"/*/; do
    [ -d "$d" ] || continue
    [ -f "$d/SKILL.md" ] || continue
    dn=$(basename "$d")
    link="$AGENT_SKILLS_DIR/$dn/SKILL.md"
    if [ ! -L "$link" ]; then
      miss=$((miss + 1))
    fi
  done
  if [ "$miss" != "0" ]; then
    fail "$TNAME" "$miss fixtures missing relinked symlinks"; return 1
  fi
  pass "$TNAME"
}

t_T_63() {
  TNAME=T-63
  t_with_writable_repo
  "$SKILL" relink >/dev/null 2>&1 || true
  # Second run — should produce no relinked: output for entries already correct.
  run "$SKILL" relink
  assert_rc 0 || return 1
  # Stdout should NOT contain "relinked:" since everything is already correct.
  if grep -q "relinked:" "$OUT"; then
    n=$(grep -c "relinked:" "$OUT")
    fail "$TNAME" "second relink unexpectedly produced $n 'relinked:' lines"; return 1
  fi
  pass "$TNAME"
}

t_T_64() {
  TNAME=T-64
  t_setup
  # no repos.patterns at all
  run "$SKILL" repos
  assert_rc 2 || return 1
  assert_stderr_contains "no .*/repos.patterns" || return 1
  pass "$TNAME"
}

t_T_65() {
  TNAME=T-65
  t_with_writable_repo
  run "$SKILL" doctor --set-default-repo /no/such/repo-$$
  assert_rc 2 || return 1
  assert_stderr_contains "is not a registered root" || return 1
  pass "$TNAME"
}

t_T_66() {
  TNAME=T-66
  t_setup
  t_patterns "$FIX"
  run "$SKILL" doctor --set-default-repo "$FIX"
  assert_rc 0 || return 1
  if [ ! -f "$SC_HOME/default_repo" ]; then
    fail "$TNAME" "default_repo file not written"; return 1
  fi
  actual=$(cat "$SC_HOME/default_repo")
  assert_eq "$actual" "$FIX" || return 1
  pass "$TNAME"
}

# ============================================================================
# Section 4: RRF search quality tests (T-80..T-89)
# ============================================================================
#
# These tests verify that Reciprocal Rank Fusion (k=10, per-query top-5 cap,
# OR-joined tokens) delivers the promised "convergence > single-axis" behavior.
# Baselines calibrated against the 25 fixtures at $FIX with the post-pivot
# search/action.
#
# Helper: extract result rows by section. Each row matches "axes=" and is
# preceded by either "  * " (installed) or "    " (uninstalled).
#
# Parse helpers — both return tab-separated `<name>\t<axes>\t<score>` rows.

# rows_in_section <stdout-file> <section-name>: extract all "axes=N score=F.FFFF name" rows.
# Section is "Convergence" or "Single-axis".
rrf_rows() {
  awk -v sec="$1" '
    BEGIN { in_sec = 0 }
    /^## Convergence/ { in_sec = (sec == "Convergence") ? 1 : 0; next }
    /^## Single-axis/ { in_sec = (sec == "Single-axis") ? 1 : 0; next }
    /^## / { in_sec = 0; next }
    in_sec && /axes=/ {
      # Strip leading "  * " or "    " then capture name + axes + score
      line = $0
      sub(/^[[:space:]]*\*?[[:space:]]*/, "", line)
      # line: name<spaces>axes=N score=F.FFFF  <desc>
      n = $0
      # Use match() instead.
      if (match($0, /[a-zA-Z][a-zA-Z0-9_:-]+/)) {
        nm = substr($0, RSTART, RLENGTH)
      } else { nm = "" }
      if (match($0, /axes=[0-9]+/)) {
        ax = substr($0, RSTART + 5, RLENGTH - 5)
      } else { ax = "" }
      if (match($0, /score=[0-9.]+/)) {
        sc = substr($0, RSTART + 6, RLENGTH - 6)
      } else { sc = "" }
      printf "%s\t%s\t%s\n", nm, ax, sc
    }
  ' "$2"
}

# Per-section helpers extracted for readability.
conv_rows()   { rrf_rows Convergence "$1"; }
single_rows() { rrf_rows Single-axis "$1"; }

# t_with_quality_fixtures: SC_HOME pointed at $FIX only, fresh reindex.
t_with_quality_fixtures() {
  t_setup
  t_patterns "$FIX"
  "$SEARCH" reindex > "$TDIR/reindex.out" 2>&1 || return 1
}

t_T_80() {
  TNAME=T-80
  # Single-domain literal: top-3 are all git-* fixtures.
  t_with_quality_fixtures || { fail "$TNAME" "reindex setup failed"; return 1; }
  run "$SEARCH" "git rebase" "branch history rewrite" "fixup commits"
  assert_rc 0 || return 1
  # Combine convergence + single-axis, take top 3 by stdout order.
  top3=$( (conv_rows "$OUT"; single_rows "$OUT") | head -n 3 | awk -F'\t' '{print $1}')
  bad=0
  for nm in $top3; do
    case "$nm" in
      git:*) ;;
      *) bad=$((bad + 1)) ;;
    esac
  done
  if [ "$bad" -ne 0 ]; then
    fail "$TNAME" "top-3 not all git-* (got: $(printf "%s " $top3))"; return 1
  fi
  # At least 2 in convergence.
  cn=$(conv_rows "$OUT" | wc -l | tr -d ' ')
  if [ "$cn" -lt 2 ]; then
    fail "$TNAME" "expected >=2 convergence rows, got $cn"; return 1
  fi
  pass "$TNAME"
}

t_T_81() {
  TNAME=T-81
  # Cross-domain intent: cloud fixtures dominate top-3.
  t_with_quality_fixtures || { fail "$TNAME" "reindex setup failed"; return 1; }
  run "$SEARCH" "deploy" "ship to production" "release to prod"
  assert_rc 0 || return 1
  top3=$( (conv_rows "$OUT"; single_rows "$OUT") | head -n 3 | awk -F'\t' '{print $1}')
  cloud_n=0
  for nm in $top3; do
    case "$nm" in
      aws:*|gcp:*|k8s:*|terraform:*|docker:*) cloud_n=$((cloud_n + 1)) ;;
    esac
  done
  if [ "$cloud_n" -lt 1 ]; then
    fail "$TNAME" "no cloud fixtures in top-3 (got: $(printf "%s " $top3))"; return 1
  fi
  cn=$(conv_rows "$OUT" | wc -l | tr -d ' ')
  if [ "$cn" -lt 1 ]; then
    fail "$TNAME" "convergence section empty"; return 1
  fi
  pass "$TNAME"
}

t_T_82() {
  TNAME=T-82
  # Synonym-rich: regex:test surfaces in top-3 even from synonym terms.
  t_with_quality_fixtures || { fail "$TNAME" "reindex setup failed"; return 1; }
  run "$SEARCH" "regex" "pattern match" "find text by rule"
  assert_rc 0 || return 1
  top3=$( (conv_rows "$OUT"; single_rows "$OUT") | head -n 3 | awk -F'\t' '{print $1}')
  hit=0
  for nm in $top3; do
    [ "$nm" = "regex:test" ] && hit=1
  done
  if [ "$hit" -ne 1 ]; then
    fail "$TNAME" "regex:test not in top-3 (got: $(printf "%s " $top3))"; return 1
  fi
  pass "$TNAME"
}

t_T_83() {
  TNAME=T-83
  # Convergence dominance: skill matching 3 axes (cherry-pick via body cross-refs)
  # outranks skill matching only 1 axis strongly (format:prettier matches "format"-ish
  # only in this query set).
  t_with_quality_fixtures || { fail "$TNAME" "reindex setup failed"; return 1; }
  run "$SEARCH" "rebase" "git" "commit"
  assert_rc 0 || return 1
  # All convergence hits must outrank any single-axis hit by RRF score.
  worst_conv=$(conv_rows "$OUT" | awk -F'\t' '{print $3}' | sort -n | head -n 1)
  best_single=$(single_rows "$OUT" | awk -F'\t' '{print $3}' | sort -rn | head -n 1)
  if [ -z "$worst_conv" ]; then
    fail "$TNAME" "convergence section empty — RRF can't demonstrate dominance"; return 1
  fi
  if [ -z "$best_single" ]; then
    # No single-axis competition; that's also a valid demonstration but weaker.
    pass "$TNAME"; return 0
  fi
  # Compare floats via awk.
  outcome=$(awk -v w="$worst_conv" -v b="$best_single" 'BEGIN{ print (w > b) ? "ok" : "fail" }')
  if [ "$outcome" = "ok" ]; then
    pass "$TNAME"; return 0
  fi
  fail "$TNAME" "worst convergence score ($worst_conv) <= best single-axis ($best_single)"; return 1
}

t_T_83b() {
  TNAME=T-83b
  # Three-axis convergence smoke (per QA spec).
  # Setup: repos.patterns → $FIX (fixtures already include git-rebase).
  # Invocation:  $SEARCH "git rebase" "rewrite commit history" "clean up commits"
  # Asserts:
  #   - exit 0
  #   - ## Convergence section present
  #   - first convergence row is git:rebase
  #   - first convergence row has axes=3
  #   - first convergence row score > 0.20
  #   - git:rebase appears BEFORE any ## Single-axis row in stdout
  # Baseline (post-retune k=10, top-K=5, bm25 10/8/5/4): score=0.2727.
  t_with_quality_fixtures || { fail "$TNAME" "reindex setup failed"; return 1; }
  run "$SEARCH" "git rebase" "rewrite commit history" "clean up commits"
  assert_rc 0 || return 1
  assert_stdout_contains "^## Convergence" || return 1

  first_line=$(conv_rows "$OUT" | head -n 1)
  if [ -z "$first_line" ]; then
    fail "$TNAME" "convergence section is empty"; return 1
  fi
  first_name=$(printf "%s" "$first_line" | awk -F'\t' '{print $1}')
  first_axes=$(printf "%s" "$first_line" | awk -F'\t' '{print $2}')
  first_score=$(printf "%s" "$first_line" | awk -F'\t' '{print $3}')

  if [ "$first_name" != "git:rebase" ]; then
    fail "$TNAME" "first convergence row was '$first_name', expected 'git:rebase'"; return 1
  fi
  if [ "$first_axes" != "3" ]; then
    fail "$TNAME" "first convergence row axes=$first_axes, expected 3"; return 1
  fi
  # Score floats — compare via awk.
  ok=$(awk -v s="$first_score" 'BEGIN{ print (s > 0.20) ? "ok" : "fail" }')
  if [ "$ok" != "ok" ]; then
    fail "$TNAME" "first convergence row score=$first_score, expected > 0.20"; return 1
  fi
  # Ordering: in raw stdout, the git:rebase line must precede the Single-axis section header.
  git_line=$(grep -n 'git:rebase' "$OUT" | head -n 1 | awk -F: '{print $1}')
  single_line=$(grep -n '^## Single-axis' "$OUT" | head -n 1 | awk -F: '{print $1}')
  if [ -z "$git_line" ] || [ -z "$single_line" ]; then
    fail "$TNAME" "couldn't locate both git:rebase and Single-axis section in stdout"; return 1
  fi
  if [ "$git_line" -ge "$single_line" ]; then
    fail "$TNAME" "git:rebase (line $git_line) does not precede Single-axis section (line $single_line)"; return 1
  fi
  pass "$TNAME"
}

t_T_84() {
  TNAME=T-84
  t_with_quality_fixtures || { fail "$TNAME" "reindex setup failed"; return 1; }
  run "$SEARCH" search zzzzzz_nomatch qqqqq_nope xxxx_void
  assert_rc 1 || return 1
  assert_stdout_contains "no skills matched" || return 1
  pass "$TNAME"
}

t_T_85() {
  TNAME=T-85
  # One axis matches nothing; two productive axes still surface convergence.
  t_with_quality_fixtures || { fail "$TNAME" "reindex setup failed"; return 1; }
  run "$SEARCH" "git rebase" "branch rewrite" "zzzzzznomatch_unique_xyz"
  assert_rc 0 || return 1
  cn=$(conv_rows "$OUT" | wc -l | tr -d ' ')
  if [ "$cn" -lt 1 ]; then
    fail "$TNAME" "convergence section empty despite 2 productive axes"; return 1
  fi
  # Convergence rows should have axes=2 (not 3).
  has_2=$(conv_rows "$OUT" | awk -F'\t' '$2 == 2' | wc -l | tr -d ' ')
  if [ "$has_2" -lt 1 ]; then
    fail "$TNAME" "no axes=2 rows in convergence"; return 1
  fi
  pass "$TNAME"
}

t_T_86() {
  TNAME=T-86
  # Identical queries × 3 → every match shows axes=3, no crash.
  t_with_quality_fixtures || { fail "$TNAME" "reindex setup failed"; return 1; }
  run "$SEARCH" regex regex regex
  assert_rc 0 || return 1
  # All hits should be in convergence with axes=3
  conv=$(conv_rows "$OUT")
  if [ -z "$conv" ]; then
    fail "$TNAME" "convergence section empty"; return 1
  fi
  bad=$(printf "%s\n" "$conv" | awk -F'\t' '$2 != 3' | wc -l | tr -d ' ')
  if [ "$bad" -ne 0 ]; then
    fail "$TNAME" "convergence has non-axes=3 rows when all 3 queries are identical"; return 1
  fi
  # Single-axis section must be (none) or empty.
  single=$(single_rows "$OUT")
  if [ -n "$single" ]; then
    fail "$TNAME" "expected empty single-axis section, got rows"; return 1
  fi
  pass "$TNAME"
}

t_T_87() {
  TNAME=T-87
  # Quoting / special chars must not crash sqlite.
  t_with_quality_fixtures || { fail "$TNAME" "reindex setup failed"; return 1; }
  run "$SEARCH" 'git "rebase"' 'foo OR bar' 'a'"'"'b'
  # Exit 0 or 1 is acceptable; what we check is no exit 3 (index/sql error).
  if [ "$RC" = "3" ]; then
    fail "$TNAME" "sqlite query crashed on special chars"; return 1
  fi
  assert_stderr_not_contains "sqlite query failed" || return 1
  # Run with literal apostrophe alone
  run "$SEARCH" "'"
  # WARN expected (1 query), exit 1 (no match). Just verify no crash.
  if [ "$RC" = "3" ]; then
    fail "$TNAME" "sqlite query crashed on single-quote query"; return 1
  fi
  pass "$TNAME"
}

t_T_88() {
  TNAME=T-88
  # Determinism — same queries run twice produce identical output.
  t_with_quality_fixtures || { fail "$TNAME" "reindex setup failed"; return 1; }
  "$SEARCH" "git rebase" "branch history rewrite" "fixup commits" > "$TDIR/run1" 2>/dev/null
  "$SEARCH" "git rebase" "branch history rewrite" "fixup commits" > "$TDIR/run2" 2>/dev/null
  if diff -q "$TDIR/run1" "$TDIR/run2" >/dev/null 2>&1; then
    pass "$TNAME"; return 0
  fi
  fail "$TNAME" "two identical query runs produced different output"; return 1
}

t_T_89() {
  TNAME=T-89
  # Convergence formatting: exactly one "## Convergence" + one "## Single-axis"
  # marker, with "  (none)" placeholder when empty.
  t_with_quality_fixtures || { fail "$TNAME" "reindex setup failed"; return 1; }
  # Case A: non-empty single-axis section
  "$SEARCH" "rebase" > "$TDIR/case-a" 2>/dev/null
  conv_n=$(grep -c "^## Convergence" "$TDIR/case-a")
  single_n=$(grep -c "^## Single-axis" "$TDIR/case-a")
  if [ "$conv_n" != "1" ] || [ "$single_n" != "1" ]; then
    fail "$TNAME" "case A: expected 1 convergence + 1 single-axis section, got $conv_n / $single_n"; return 1
  fi
  # Convergence should be (none) since only 1 query — no axes>=2 possible.
  if ! grep -q '  (none)' "$TDIR/case-a"; then
    fail "$TNAME" "case A: expected '  (none)' placeholder in empty convergence"; return 1
  fi
  # Case B: identical-queries-x3 → empty single-axis section.
  "$SEARCH" regex regex regex > "$TDIR/case-b" 2>/dev/null
  # Find the "## Single-axis hits" section, check the next line is "  (none)"
  if ! awk '/^## Single-axis hits/{ getline; print }' "$TDIR/case-b" | grep -q '  (none)'; then
    fail "$TNAME" "case B: expected '  (none)' under Single-axis when all hits converge"; return 1
  fi
  pass "$TNAME"
}

# ============================================================================
# Section 5: integration tests (T-100..T-111)
# ============================================================================

t_T_100() {
  TNAME=T-100
  # End-to-end fresh: bootstrap → reindex → query → only git domain in top-3.
  t_setup
  run "$SEARCH" doctor --write-sample
  assert_rc 0 || return 1
  # Replace sample defaults with $FIX-only so reindex only sees fixtures.
  printf "%s\t*\n" "$FIX" > "$SC_HOME/repos.patterns"
  run "$SEARCH" reindex
  assert_rc 0 || return 1
  run "$SEARCH" "git" "version control" "rebase"
  assert_rc 0 || return 1
  top3=$( (conv_rows "$OUT"; single_rows "$OUT") | head -n 3 | awk -F'\t' '{print $1}')
  bad=0
  for nm in $top3; do
    case "$nm" in
      git:*|merge:*) ;;   # merge:conflict-resolver is git-adjacent
      *) bad=$((bad + 1)) ;;
    esac
  done
  if [ "$bad" -ne 0 ]; then
    fail "$TNAME" "non-git fixtures in top-3 (got: $(printf "%s " $top3))"; return 1
  fi
  pass "$TNAME"
}

t_T_101() {
  TNAME=T-101
  # Multi-repo discovery: $FIX + an extra skills root → count is sum.
  # Set SC_EXTRA_SKILLS_ROOT to enable this test; otherwise it skips.
  t_setup
  t_patterns "$FIX"
  EXTRA="${SC_EXTRA_SKILLS_ROOT:-}"
  if [ -z "$EXTRA" ] || [ ! -d "$EXTRA" ]; then
    skip "$TNAME" "SC_EXTRA_SKILLS_ROOT not set or missing"
    return 0
  fi
  t_patterns "$EXTRA"
  run "$SEARCH" reindex
  assert_rc 0 || return 1
  cnt=$(sqlite3 "$SC_HOME/search/index.db" "SELECT COUNT(*) FROM skills;" 2>/dev/null)
  fix_n=25
  extra_n=$(find "$EXTRA" -maxdepth 2 -name SKILL.md -type f 2>/dev/null | wc -l | tr -d ' ')
  expected=$((fix_n + extra_n))
  if [ "$cnt" != "$expected" ]; then
    fail "$TNAME" "expected $expected skills (= $fix_n fix + $extra_n extra), got $cnt"; return 1
  fi
  pass "$TNAME"
}

t_T_102() {
  TNAME=T-102
  # Reindex idempotence: two reindexes produce identical row data.
  t_with_quality_fixtures || { fail "$TNAME" "reindex setup failed"; return 1; }
  q="SELECT path,name,dirname,installed,description,content FROM skills ORDER BY path"
  before=$(sqlite3 "$SC_HOME/search/index.db" "$q")
  run "$SEARCH" reindex
  assert_rc 0 || return 1
  after=$(sqlite3 "$SC_HOME/search/index.db" "$q")
  if [ "$before" = "$after" ]; then pass "$TNAME"; return 0; fi
  fail "$TNAME" "row contents differ across reindex runs"; return 1
}

t_T_103() {
  TNAME=T-103
  # Concurrent reindex atomicity: race two reindexes; final DB must be a
  # valid FTS5 index with the correct row count. The two writers currently
  # share index.db.tmp (known mild race; tracked separately). Test does NOT
  # assert anything about which writer wins, only that the final state is
  # valid and queryable.
  t_with_quality_fixtures || { fail "$TNAME" "reindex setup failed"; return 1; }
  "$SEARCH" reindex >"$TDIR/r1.out" 2>"$TDIR/r1.err" &
  pid1=$!
  "$SEARCH" reindex >"$TDIR/r2.out" 2>"$TDIR/r2.err" &
  pid2=$!
  wait "$pid1" 2>/dev/null || true
  wait "$pid2" 2>/dev/null || true
  if [ ! -f "$SC_HOME/search/index.db" ]; then
    fail "$TNAME" "final index.db missing after concurrent reindex"; return 1
  fi
  cnt=$(sqlite3 "$SC_HOME/search/index.db" "SELECT COUNT(*) FROM skills;" 2>/dev/null)
  if [ "$cnt" != "25" ]; then
    fail "$TNAME" "final index has $cnt rows, expected 25"; return 1
  fi
  if [ -f "$SC_HOME/search/index.db.tmp" ]; then
    fail "$TNAME" "index.db.tmp left behind after concurrent reindex"; return 1
  fi
  pass "$TNAME"
}

t_T_104() {
  TNAME=T-104
  # `re:` regex pattern — only git-prefixed fixtures indexed.
  t_setup
  printf "%s\tre:^git-.*$\n" "$FIX" > "$SC_HOME/repos.patterns"
  run "$SEARCH" reindex
  assert_rc 0 || return 1
  cnt=$(sqlite3 "$SC_HOME/search/index.db" "SELECT COUNT(*) FROM skills;" 2>/dev/null)
  if [ "$cnt" != "4" ]; then
    fail "$TNAME" "regex re:^git-.*\$ should match 4 fixtures, got $cnt"; return 1
  fi
  bad=$(sqlite3 "$SC_HOME/search/index.db" "SELECT dirname FROM skills WHERE dirname NOT LIKE 'git-%';" 2>/dev/null | wc -l | tr -d ' ')
  if [ "$bad" != "0" ]; then
    fail "$TNAME" "regex pattern matched non-git dirs"; return 1
  fi
  pass "$TNAME"
}

t_T_105() {
  TNAME=T-105
  # Glob pattern — `git-*` should match same set as re:^git-.*$
  t_setup
  printf "%s\tgit-*\n" "$FIX" > "$SC_HOME/repos.patterns"
  run "$SEARCH" reindex
  assert_rc 0 || return 1
  cnt=$(sqlite3 "$SC_HOME/search/index.db" "SELECT COUNT(*) FROM skills;" 2>/dev/null)
  if [ "$cnt" != "4" ]; then
    fail "$TNAME" "glob git-* should match 4 fixtures, got $cnt"; return 1
  fi
  pass "$TNAME"
}

# T-106 dropped — tag_cloud.txt removed by user pivot; tags are no longer
# indexed at all, so this test has no behavior to verify.
t_T_106() {
  TNAME=T-106
  skip "$TNAME" "tag_cloud.txt removed by user pivot; tags no longer indexed"
}

t_T_107() {
  TNAME=T-107
  # Installed marker — relink first, then verify text output has `*` prefix
  # for fixtures with a registration symlink.
  t_with_quality_fixtures || { fail "$TNAME" "reindex setup failed"; return 1; }
  "$SKILL" relink >/dev/null 2>&1 || true
  # Reindex AFTER relink so installed=1 is captured in the FTS rows.
  run "$SEARCH" reindex
  assert_rc 0 || return 1
  run "$SEARCH" "git rebase" "branch history rewrite" "fixup commits"
  assert_rc 0 || return 1
  if ! grep -q '^  \* ' "$OUT"; then
    fail "$TNAME" "no '*' (installed) marker in text output after relink"; return 1
  fi
  pass "$TNAME"
}

t_T_108() {
  TNAME=T-108
  # TSV column shape: exactly 7 tab-separated fields per row, types correct.
  t_with_quality_fixtures || { fail "$TNAME" "reindex setup failed"; return 1; }
  run "$SEARCH" --format tsv "git rebase" "branch history rewrite" "fixup commits"
  assert_rc 0 || return 1
  bad=0
  while IFS= read -r line; do
    [ -n "$line" ] || continue
    n=$(printf "%s" "$line" | awk -F'\t' '{print NF}')
    [ "$n" = "7" ] || { bad=$((bad + 1)); break; }
    installed=$(printf "%s" "$line" | awk -F'\t' '{print $5}')
    case "$installed" in
      0|1) ;;
      *) bad=$((bad + 1)); break ;;
    esac
    score=$(printf "%s" "$line" | awk -F'\t' '{print $6}')
    case "$score" in
      [0-9]*.[0-9]*|[0-9]*) ;;
      *) bad=$((bad + 1)); break ;;
    esac
    axes=$(printf "%s" "$line" | awk -F'\t' '{print $7}')
    case "$axes" in
      [1-9]|[1-9][0-9]) ;;
      *) bad=$((bad + 1)); break ;;
    esac
  done < "$OUT"
  if [ "$bad" = "0" ]; then pass "$TNAME"; return 0; fi
  fail "$TNAME" "tsv row had unexpected shape (bad row found)"; return 1
}

t_T_109() {
  TNAME=T-109
  # JSON output structure: {"results":[ {object with required keys}, ... ]}
  t_with_quality_fixtures || { fail "$TNAME" "reindex setup failed"; return 1; }
  run "$SEARCH" --format json "git rebase" "branch history rewrite" "fixup commits"
  assert_rc 0 || return 1
  first=$(head -c 12 "$OUT")
  case "$first" in
    '{"results":'*) ;;
    *) fail "$TNAME" "json doesn't start with {\"results\":"; return 1 ;;
  esac
  for key in '"path"' '"name"' '"dirname"' '"description"' '"installed"' '"score"' '"axes"'; do
    if ! grep -q -- "$key" "$OUT"; then
      fail "$TNAME" "json missing key: $key"; return 1
    fi
  done
  opens=$(tr -cd '{' < "$OUT" | wc -c | tr -d ' ')
  closes=$(tr -cd '}' < "$OUT" | wc -c | tr -d ' ')
  if [ "$opens" != "$closes" ]; then
    fail "$TNAME" "json brace count mismatch ($opens vs $closes)"; return 1
  fi
  pass "$TNAME"
}

t_T_110() {
  TNAME=T-110
  # Create → reindex → search round-trip: new skill is findable.
  t_with_writable_repo
  "$SKILL" create qa-roundtrip-xyzzy --repo "$WR" >/dev/null 2>&1
  # Replace TODO description with a distinctive phrase that won't collide with
  # any fixture wording.
  sed -i.bak 's/^description: .*/description: A unique qa roundtrip xyzzy probe phrase for integration testing./' "$WR/qa-roundtrip-xyzzy/SKILL.md"
  rm -f "$WR/qa-roundtrip-xyzzy/SKILL.md.bak"
  "$SEARCH" reindex >/dev/null 2>&1
  run "$SEARCH" "xyzzy" "qa roundtrip" "integration testing probe"
  assert_rc 0 || return 1
  top=$( (conv_rows "$OUT"; single_rows "$OUT") | head -n 1 | awk -F'\t' '{print $1}')
  if [ "$top" != "qa:roundtrip-xyzzy" ]; then
    fail "$TNAME" "new skill not #1 after create+reindex+search (top was: $top)"; return 1
  fi
  pass "$TNAME"
}

t_T_111() {
  TNAME=T-111
  # Delete → reindex → search round-trip: deleted skill is no longer findable.
  t_with_writable_repo
  "$SKILL" create qa-gone-xyzzy --repo "$WR" >/dev/null 2>&1
  sed -i.bak 's/^description: .*/description: A unique qa gone xyzzy probe phrase before deletion./' "$WR/qa-gone-xyzzy/SKILL.md"
  rm -f "$WR/qa-gone-xyzzy/SKILL.md.bak"
  "$SEARCH" reindex >/dev/null 2>&1
  "$SKILL" delete --force qa-gone-xyzzy >/dev/null 2>&1
  "$SEARCH" reindex >/dev/null 2>&1
  run "$SEARCH" "xyzzy" "qa gone" "probe phrase"
  if grep -q "qa:gone-xyzzy" "$OUT"; then
    fail "$TNAME" "deleted skill still findable after delete+reindex"; return 1
  fi
  pass "$TNAME"
}

# ============================================================================
# Section 6: hash refresh & auto-reindex tests (T-120..T-127)
# ============================================================================
#
# Verifies the SHA-256-based change detection: every action invocation
# computes a hash over <path>+<content> of every discovered SKILL.md and
# reindexes only when it differs from $SC_HOME/search/.index_hash.

# Helper: write a minimal synthetic SKILL.md under $dir/$dirname so we can
# add/modify/remove without touching the read-only $FIX fixtures.
t_write_synthetic_skill() {
  dir="$1"; dirname="$2"; desc="$3"
  mkdir -p "$dir/$dirname"
  # Derive frontmatter name: first '-' → ':' (sc:crud convention).
  name=$(printf "%s" "$dirname" | awk '{
    i = index($0, "-")
    if (i == 0) print $0
    else        printf "%s:%s\n", substr($0, 1, i-1), substr($0, i+1)
  }')
  cat > "$dir/$dirname/SKILL.md" <<EOF
---
name: $name
description: $desc
user_invocable: true
---

# $name

Synthetic SKILL.md for hash-drift testing.
EOF
}

t_T_120() {
  TNAME=T-120
  # First invocation populates .index_hash with a 64-char SHA-256.
  t_setup; t_patterns "$FIX"
  run "$SEARCH" list-roots
  assert_rc 0 || return 1
  assert_file_exists "$SC_HOME/search/.index_hash" || return 1
  h=$(cat "$SC_HOME/search/.index_hash" 2>/dev/null)
  n=$(printf "%s" "$h" | wc -c | tr -d ' ')
  if [ "$n" != "64" ]; then
    fail "$TNAME" "expected 64-char hash, got len=$n"; return 1
  fi
  pass "$TNAME"
}

t_T_121() {
  TNAME=T-121
  # Stable skill set → second invocation is silent (no auto-reindex).
  t_setup; t_patterns "$FIX"
  "$SEARCH" list-roots >/dev/null 2>&1
  h1=$(cat "$SC_HOME/search/.index_hash")
  run "$SEARCH" list-roots
  assert_rc 0 || return 1
  assert_stderr_not_contains "indexed " || return 1
  h2=$(cat "$SC_HOME/search/.index_hash")
  assert_eq "$h2" "$h1" || return 1
  pass "$TNAME"
}

t_T_122() {
  TNAME=T-122
  # Modified SKILL.md content → hash differs → auto-reindex.
  t_with_writable_repo
  t_write_synthetic_skill "$WR" "drift-modify" "Initial drift modify probe."
  "$SEARCH" list-roots >/dev/null 2>&1
  h1=$(cat "$SC_HOME/search/.index_hash")

  printf "\nMutated body line for drift test.\n" >> "$WR/drift-modify/SKILL.md"

  run "$SEARCH" list-roots
  assert_rc 0 || return 1
  assert_stderr_contains "indexed " || return 1
  h2=$(cat "$SC_HOME/search/.index_hash")
  if [ "$h1" = "$h2" ]; then
    fail "$TNAME" "hash unchanged after SKILL.md mutation"; return 1
  fi
  pass "$TNAME"
}

t_T_123() {
  TNAME=T-123
  # Adding a new SKILL.md triggers auto-reindex.
  t_with_writable_repo
  "$SEARCH" list-roots >/dev/null 2>&1   # warm with FIX only
  h1=$(cat "$SC_HOME/search/.index_hash")

  t_write_synthetic_skill "$WR" "drift-add" "Added drift skill probe."

  run "$SEARCH" list-roots
  assert_rc 0 || return 1
  assert_stderr_contains "indexed " || return 1
  h2=$(cat "$SC_HOME/search/.index_hash")
  if [ "$h1" = "$h2" ]; then
    fail "$TNAME" "hash unchanged after adding a SKILL.md"; return 1
  fi
  pass "$TNAME"
}

t_T_124() {
  TNAME=T-124
  # Removing a SKILL.md triggers auto-reindex.
  t_with_writable_repo
  t_write_synthetic_skill "$WR" "drift-remove" "Removable drift skill probe."
  "$SEARCH" list-roots >/dev/null 2>&1   # warm
  h1=$(cat "$SC_HOME/search/.index_hash")

  rm -rf "$WR/drift-remove"

  run "$SEARCH" list-roots
  assert_rc 0 || return 1
  assert_stderr_contains "indexed " || return 1
  h2=$(cat "$SC_HOME/search/.index_hash")
  if [ "$h1" = "$h2" ]; then
    fail "$TNAME" "hash unchanged after removing a SKILL.md"; return 1
  fi
  pass "$TNAME"
}

t_T_125() {
  TNAME=T-125
  # Missing index.db forces a reindex even when the hash still matches.
  t_setup; t_patterns "$FIX"
  "$SEARCH" list-roots >/dev/null 2>&1
  rm -f "$SC_HOME/search/index.db"
  run "$SEARCH" list-roots
  assert_rc 0 || return 1
  assert_stderr_contains "indexed " || return 1
  assert_file_exists "$SC_HOME/search/index.db" || return 1
  pass "$TNAME"
}

t_T_126() {
  TNAME=T-126
  # Explicit reindex always writes/refreshes the hash file.
  t_setup; t_patterns "$FIX"
  run "$SEARCH" reindex
  assert_rc 0 || return 1
  assert_file_exists "$SC_HOME/search/.index_hash" || return 1
  h=$(cat "$SC_HOME/search/.index_hash")
  n=$(printf "%s" "$h" | wc -c | tr -d ' ')
  if [ "$n" != "64" ]; then
    fail "$TNAME" "expected 64-char hash after explicit reindex, got len=$n"; return 1
  fi
  pass "$TNAME"
}

t_T_127() {
  TNAME=T-127
  # Empty discovery (root with zero SKILL.md files) → auto-reindex skips
  # silently. No .index_hash is created; the subcommand still runs cleanly.
  t_setup
  mkdir -p "$TDIR/empty-root"
  t_patterns "$TDIR/empty-root"
  run "$SEARCH" doctor
  assert_rc 0 || return 1
  if [ -f "$SC_HOME/search/.index_hash" ]; then
    fail "$TNAME" ".index_hash unexpectedly created on empty discovery"; return 1
  fi
  pass "$TNAME"
}

# ============================================================================
# Runner
# ============================================================================

ALL_TESTS="T-01 T-02 T-03 T-04 T-05 T-06 T-07 T-08 T-09 T-10 T-11 T-12 T-13 T-14
T-20 T-21 T-22 T-22b T-23 T-24 T-25 T-26 T-27 T-28 T-29 T-30 T-31 T-32 T-33 T-34
T-40 T-41 T-42 T-43 T-44 T-45 T-46 T-47 T-48 T-49 T-50 T-51 T-52 T-53 T-54
T-55 T-56 T-57 T-58 T-59 T-60 T-61 T-62 T-63 T-64 T-65 T-66
T-80 T-81 T-82 T-83 T-83b T-84 T-85 T-86 T-87 T-88 T-89
T-100 T-101 T-102 T-103 T-104 T-105 T-106 T-107 T-108 T-109 T-110 T-111
T-120 T-121 T-122 T-123 T-124 T-125 T-126 T-127"

# Parse flags
while [ "$#" -gt 0 ]; do
  case "$1" in
    -v|--verbose) VERBOSE=1; shift ;;
    -h|--help) printf "usage: %s [-v] [T-NN...]\n" "$0"; exit 0 ;;
    --) shift; break ;;
    -*) printf "unknown flag: %s\n" "$1" >&2; exit 2 ;;
    *) break ;;
  esac
done

# Determine which tests to run
if [ "$#" -eq 0 ]; then
  TESTS="$ALL_TESTS"
else
  TESTS="$*"
fi

# Sanity check: fixtures present
if [ ! -d "$FIX" ]; then
  printf "FATAL: fixtures missing at %s\n" "$FIX" >&2
  exit 2
fi
fc=$(find "$FIX" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | wc -l | tr -d ' ')
if [ "$fc" -lt 25 ]; then
  printf "WARN: expected 25 fixtures at %s, found %s\n" "$FIX" "$fc" >&2
fi

printf "running tests from %s\n" "$ROOT"
printf "  search:   %s\n" "$SEARCH"
printf "  skill:    %s\n" "$SKILL"
printf "  fixtures: %s (%s skills)\n" "$FIX" "$fc"
printf "\n"

for t in $TESTS; do
  fn="t_$(printf "%s" "$t" | tr -- '-' '_')"
  if ! command -v "$fn" >/dev/null 2>&1; then
    skip "$t" "no such test"
    continue
  fi
  "$fn" || true
done

printf "\n"
printf "passed: %s\n" "$PASS_N"
printf "failed: %s%s\n" "$FAIL_N" "$( [ -n "$FAIL_LIST" ] && printf ' (%s)' "$FAIL_LIST" )"
printf "skipped: %s\n" "$SKIP_N"

if [ "$FAIL_N" -gt 0 ]; then exit 1; fi
exit 0
