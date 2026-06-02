#!/usr/bin/env bash
set -u

ROOT_DIR=$(cd "$(dirname "$0")/.." && pwd)
SCRIPT="$ROOT_DIR/macos-setup"
TMP_DIR=$(mktemp -d "${TMPDIR:-/tmp}/macos-setup-test.XXXXXX")
trap 'rm -rf "$TMP_DIR"' EXIT

STUB_LOG="$TMP_DIR/stub.log"
mkdir -p "$TMP_DIR/bin"

cat >"$TMP_DIR/bin/osascript" <<'STUB'
#!/usr/bin/env bash
printf 'osascript %s\n' "$*" >>"$STUB_LOG"
exit 0
STUB

cat >"$TMP_DIR/bin/defaults" <<'STUB'
#!/usr/bin/env bash
printf 'defaults %s\n' "$*" >>"$STUB_LOG"
if [ "${1:-}" = "read" ]; then
  exit 1
fi
exit 0
STUB

chmod +x "$TMP_DIR/bin/osascript" "$TMP_DIR/bin/defaults"
export PATH="$TMP_DIR/bin:$PATH"
export STUB_LOG

fail() {
  printf 'FAIL: %s\n' "$1" >&2
  exit 1
}

assert_empty_log() {
  if [ -s "$STUB_LOG" ]; then
    printf 'stub log was not empty:\n' >&2
    cat "$STUB_LOG" >&2
    fail "$1"
  fi
}

run_capture() {
  name=$1
  shift
  : >"$STUB_LOG"
  set +e
  "$@" >"$TMP_DIR/$name.out" 2>"$TMP_DIR/$name.err"
  status=$?
  set -e
  printf '%s' "$status" >"$TMP_DIR/$name.status"
}

set -e

run_capture help "$SCRIPT" --help
[ "$(cat "$TMP_DIR/help.status")" = "0" ] || fail '--help should exit 0'
grep -q 'Usage: macos-setup' "$TMP_DIR/help.out" || fail '--help should print usage'
assert_empty_log '--help must not call osascript/defaults'

run_capture no_args "$SCRIPT"
[ "$(cat "$TMP_DIR/no_args.status")" = "2" ] || fail 'no args should exit 2'
grep -q 'choose an explicit mode' "$TMP_DIR/no_args.err" || fail 'no args should explain explicit mode requirement'
assert_empty_log 'no args must not call osascript/defaults'

run_capture two_modes "$SCRIPT" --list --check
[ "$(cat "$TMP_DIR/two_modes.status")" = "2" ] || fail 'two modes should exit 2'
grep -q 'only one mode' "$TMP_DIR/two_modes.err" || fail 'two modes should explain only one mode is allowed'
assert_empty_log 'invalid args must not call osascript/defaults'

run_capture missing_section "$SCRIPT" --section
[ "$(cat "$TMP_DIR/missing_section.status")" = "2" ] || fail 'missing --section value should exit 2'
grep -q -- '--section requires a value' "$TMP_DIR/missing_section.err" || fail 'missing section should explain requirement'
assert_empty_log 'missing section must not call osascript/defaults'

run_capture list "$SCRIPT" --list --section screen
[ "$(cat "$TMP_DIR/list.status")" = "0" ] || fail '--list should exit 0'
grep -q 'screen.*askForPassword.*int.*1' "$TMP_DIR/list.out" || fail '--list --section screen should list screen setting'
assert_empty_log '--list must not call osascript/defaults'

run_capture dry_run "$SCRIPT" --dry-run --section safari
[ "$(cat "$TMP_DIR/dry_run.status")" = "0" ] || fail '--dry-run should exit 0'
grep -q 'defaults write com.apple.Safari WarnAboutFraudulentWebsites -bool true' "$TMP_DIR/dry_run.out" || fail '--dry-run should render Safari defaults write command'
assert_empty_log '--dry-run must not execute osascript/defaults'

run_capture check "$SCRIPT" --check --section screen
[ "$(cat "$TMP_DIR/check.status")" = "1" ] || fail '--check should exit 1 when desired values are missing'
grep -q 'MISSING.*com.apple.screensaver.*askForPassword' "$TMP_DIR/check.out" || fail '--check should report missing screen default'
if grep -q '^osascript ' "$STUB_LOG"; then
  fail '--check must not call osascript'
fi
if grep -q '^defaults write' "$STUB_LOG"; then
  fail '--check must not write defaults'
fi

run_capture apply "$SCRIPT" --apply --section screen
[ "$(cat "$TMP_DIR/apply.status")" = "0" ] || fail '--apply should exit 0 for screen section with stubs'
grep -q 'Applying \[screen\]' "$TMP_DIR/apply.out" || fail '--apply should print applying messages'
grep -q '^osascript ' "$STUB_LOG" || fail '--apply should quit System Settings/Preferences through osascript'
grep -q '^defaults write com.apple.screensaver askForPassword -int 1' "$STUB_LOG" || fail '--apply should execute screen defaults write'

printf 'cli smoke tests passed\n'
