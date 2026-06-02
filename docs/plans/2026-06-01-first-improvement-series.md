# First macOS Setup Improvement Series Implementation Plan

> **For Hermes:** Use subagent-driven-development skill to implement this plan task-by-task.

**Goal:** Turn the current monolithic `macos-setup` Bash script into a safer, inspectable macOS defaults utility without changing the current effective desired-state settings in the first series.

**Architecture:** Keep the project Bash-first and dependency-light. Introduce a small command-line interface, a setting declaration registry, and helper functions that can list, dry-run, check, and apply selected settings. The first series should preserve the existing active settings while making future expansion safer.

**Tech Stack:** Bash 3.2-compatible shell script for macOS compatibility, built-in macOS commands (`defaults`, `sw_vers`, `osascript`), ShellCheck, GitHub Actions.

---

## Current Baseline

Repository: `~/Projects/pjbeyer/macOS-setup`

Current production/stable reference remains: `~/.config/macos/`

Current code shape:

- `macos-setup` is a single executable Bash script.
- `README.md` documents only direct execution: `./macos-setup`.
- `.github/workflows/scorecard.yml` exists; there is no lint/validation CI for the script.
- `bash -n macos-setup` passes.
- `shellcheck macos-setup` passes.
- Active settings currently written by the script are concentrated in:
  - Screen/security: screensaver password settings.
  - Safari security/privacy legacy settings.
  - Terminal secure keyboard entry.
  - Software Update / commerce update settings.
  - Opening/closing System Settings and final status message.

Important constraints:

- Do **not** execute `./macos-setup` during development verification unless explicitly requested; it mutates live macOS preferences.
- First series should not introduce sudo/admin/destructive settings.
- First series should not turn currently commented historical Mathias settings into active behavior.
- Prefer XDG-compatible installation guidance: symlink into `$XDG_BIN_HOME` or `~/.local/bin` rather than encouraging root-level dotfiles only.
- The repo uses Beads for work tracking. Use Beads issues for follow-up implementation, not markdown TODOs.

---

## Target Behavior for First Series

After the first series, the utility should support:

```bash
./macos-setup --help
./macos-setup --list
./macos-setup --dry-run
./macos-setup --check
./macos-setup --apply
./macos-setup --section screen --check
./macos-setup --section safari --dry-run
```

Expected safety model:

- Running with no arguments should **not** silently expand behavior.
- Prefer making `--apply` the explicit mutating command.
- If preserving legacy no-argument apply behavior is desired for compatibility, it must print a deprecation warning and be documented. The recommended default for this repo is explicit `--apply`.
- `--list`, `--dry-run`, and `--check` must not write preferences or quit apps.
- `--check` may read preferences with `defaults read` / `defaults export`-equivalent commands but must not call `defaults write`.
- `--apply` should be the only path that runs `defaults write` or app lifecycle actions.

---

## Proposed Setting Registry Model

Implement a Bash-native registry with one declaration per active setting. Keep it simple enough for Bash 3.2.

Suggested declaration function shape:

```bash
setting \
  "screen" \
  "Require password after sleep or screen saver begins" \
  "com.apple.screensaver" \
  "askForPassword" \
  "int" \
  "1" \
  "none"
```

Field order:

1. `section` — stable machine-readable section (`screen`, `safari`, `terminal`, `software-update`).
2. `label` — human-readable description.
3. `domain` — defaults domain, e.g. `com.apple.screensaver`.
4. `key` — defaults key.
5. `type` — one of `bool`, `int`, `float`, `string` for first series.
6. `value` — desired value as a string.
7. `restart` — one of `none`, `logout`, `restart`, or app/process name for future documentation.

Store registry rows in a global Bash array as delimited strings. Because values in this first series are simple and do not contain tabs, tab-delimited rows are adequate.

Example internal row:

```bash
SETTINGS+=("screen	Require password after sleep or screen saver begins	com.apple.screensaver	askForPassword	int	1	none")
```

Future series can add more action types (`plistbuddy`, `pmset`, `systemsetup`, `currentHost`, admin/destructive flags), but do not add them in the first series unless necessary.

---

## Task 1: Add CLI parser and safe mode dispatch

**Objective:** Add `--help`, mode flags, and section filtering without changing settings behavior yet.

**Files:**

- Modify: `macos-setup`
- Modify: `README.md`

**Step 1: Create a branch**

```bash
git switch -c feat/cli-modes
```

Expected: branch created from `main`.

**Step 2: Add parser helpers near the top of `macos-setup`**

Add after the introductory comments and before any command with side effects:

```bash
MODE=""
SECTION_FILTER=""

usage() {
  cat <<'EOF'
Usage: macos-setup [MODE] [OPTIONS]

Modes:
  --list              List configured settings without reading or writing macOS preferences.
  --dry-run           Show commands that would be applied, without writing preferences.
  --check             Compare current macOS preferences to desired values, without writing.
  --apply             Apply desired macOS preferences.

Options:
  --section NAME      Limit mode to a section, e.g. screen, safari, terminal, software-update.
  -h, --help          Show this help text.

Safety:
  Only --apply mutates macOS preferences. Read-only modes do not quit System Settings.
EOF
}

parse_args() {
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --list|--dry-run|--check|--apply)
        if [ -n "$MODE" ]; then
          printf 'error: only one mode may be specified\n' >&2
          exit 2
        fi
        MODE="${1#--}"
        ;;
      --section)
        shift
        if [ "$#" -eq 0 ]; then
          printf 'error: --section requires a value\n' >&2
          exit 2
        fi
        SECTION_FILTER="$1"
        ;;
      -h|--help)
        usage
        exit 0
        ;;
      *)
        printf 'error: unknown argument: %s\n' "$1" >&2
        usage >&2
        exit 2
        ;;
    esac
    shift
  done

  if [ -z "$MODE" ]; then
    usage >&2
    printf '\nerror: choose an explicit mode; use --apply to write settings\n' >&2
    exit 2
  fi
}
```

**Step 3: Temporarily call parser and exit**

For this first task only, call `parse_args "$@"` and dispatch basic no-op output before the existing imperative body. This verifies argument handling before refactoring setting writes.

**Step 4: Verify parser behavior**

Run:

```bash
bash -n macos-setup
shellcheck macos-setup
./macos-setup --help
./macos-setup
./macos-setup --list --check
./macos-setup --section
```

Expected:

- `bash -n`: pass.
- `shellcheck`: pass.
- `--help`: exit 0 and print usage.
- no arguments: exit 2 with explicit-mode error.
- two modes: exit 2.
- missing section value: exit 2.

**Step 5: Update README with new mode summary**

Update the Usage section to show explicit modes and safety note.

**Step 6: Commit**

```bash
git add macos-setup README.md
git commit -m "feat(cli): require explicit macos setup modes"
```

---

## Task 2: Introduce setting registry and `--list`

**Objective:** Represent current active settings as metadata and make `--list` useful without writing preferences.

**Files:**

- Modify: `macos-setup`
- Modify: `README.md`

**Step 1: Add registry storage and declaration function**

Add:

```bash
SETTINGS=()

setting() {
  SETTINGS+=("$1	$2	$3	$4	$5	$6	$7")
}
```

**Step 2: Declare only currently active `defaults write` settings**

Start with these active settings from current `macos-setup`:

```bash
setting "screen" "Require password after sleep or screen saver begins" "com.apple.screensaver" "askForPassword" "int" "1" "none"
setting "screen" "Require password immediately after sleep or screen saver begins" "com.apple.screensaver" "askForPasswordDelay" "int" "0" "none"
setting "safari" "Warn about fraudulent websites" "com.apple.Safari" "WarnAboutFraudulentWebsites" "bool" "true" "Safari"
setting "safari" "Disable Java in Safari WebKit" "com.apple.Safari" "WebKitJavaEnabled" "bool" "false" "Safari"
setting "safari" "Disable Java in Safari WebKit2 content pages" "com.apple.Safari" "com.apple.Safari.ContentPageGroupIdentifier.WebKit2JavaEnabled" "bool" "false" "Safari"
setting "safari" "Disable Java for local files in Safari WebKit2" "com.apple.Safari" "com.apple.Safari.ContentPageGroupIdentifier.WebKit2JavaEnabledForLocalFiles" "bool" "false" "Safari"
setting "safari" "Send Do Not Track HTTP header" "com.apple.Safari" "SendDoNotTrackHTTPHeader" "bool" "true" "Safari"
setting "safari" "Install Safari extension updates automatically" "com.apple.Safari" "InstallExtensionUpdatesAutomatically" "bool" "true" "Safari"
setting "terminal" "Enable Secure Keyboard Entry in Terminal" "com.apple.terminal" "SecureKeyboardEntry" "bool" "true" "Terminal"
setting "software-update" "Enable automatic software update checks" "com.apple.SoftwareUpdate" "AutomaticCheckEnabled" "bool" "true" "none"
setting "software-update" "Check for software updates daily" "com.apple.SoftwareUpdate" "ScheduleFrequency" "int" "1" "none"
setting "software-update" "Download newly available updates in background" "com.apple.SoftwareUpdate" "AutomaticDownload" "int" "1" "none"
setting "software-update" "Install system data files and security updates" "com.apple.SoftwareUpdate" "CriticalUpdateInstall" "int" "1" "none"
setting "software-update" "Turn on App Store app auto-update" "com.apple.commerce" "AutoUpdate" "bool" "true" "none"
```

Do not include the `osascript` quit command or final `echo` as settings; handle app lifecycle separately in later tasks.

**Step 3: Add row parsing helper**

Because Bash 3.2 on macOS does not support associative arrays, use tab-delimited rows and `IFS`.

```bash
for_each_setting() {
  for row in "${SETTINGS[@]}"; do
    IFS='    ' read -r section label domain key type value restart <<EOF
$row
EOF
    if [ -n "$SECTION_FILTER" ] && [ "$SECTION_FILTER" != "$section" ]; then
      continue
    fi
    "$@" "$section" "$label" "$domain" "$key" "$type" "$value" "$restart"
  done
}
```

Use a literal tab in the `IFS` assignment, or use a safer separator such as ASCII unit separator via `printf` if desired. Verify with ShellCheck.

**Step 4: Implement `list_setting`**

```bash
list_setting() {
  section=$1 label=$2 domain=$3 key=$4 type=$5 value=$6 restart=$7
  printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "$section" "$label" "$domain" "$key" "$type" "$value" "$restart"
}
```

Dispatch:

```bash
case "$MODE" in
  list) for_each_setting list_setting ;;
  ...
esac
```

**Step 5: Verify `--list`**

Run:

```bash
bash -n macos-setup
shellcheck macos-setup
./macos-setup --list
./macos-setup --list --section safari
./macos-setup --list --section does-not-exist
```

Expected:

- All validation passes.
- `--list` prints the declared active settings.
- Section filter works.
- Unknown section prints no settings and exits 0 for now.

**Step 6: Commit**

```bash
git add macos-setup README.md
git commit -m "feat(settings): list declared macos defaults"
```

---

## Task 3: Implement `--dry-run`

**Objective:** Print the exact `defaults write` commands that `--apply` would run, without mutating preferences.

**Files:**

- Modify: `macos-setup`
- Modify: `README.md`

**Step 1: Add command rendering helper**

```bash
render_defaults_write() {
  domain=$1 key=$2 type=$3 value=$4
  case "$type" in
    bool) printf 'defaults write %s %s -bool %s\n' "$domain" "$key" "$value" ;;
    int) printf 'defaults write %s %s -int %s\n' "$domain" "$key" "$value" ;;
    float) printf 'defaults write %s %s -float %s\n' "$domain" "$key" "$value" ;;
    string) printf 'defaults write %s %s -string %s\n' "$domain" "$key" "$(quote_shell "$value")" ;;
    *) printf 'error: unsupported type: %s\n' "$type" >&2; return 1 ;;
  esac
}
```

If implementing `quote_shell` in pure Bash is too much for the first series, avoid `string` declarations for now and leave an explicit error path.

**Step 2: Add dry-run action**

```bash
dry_run_setting() {
  _section=$1 _label=$2 domain=$3 key=$4 type=$5 value=$6 _restart=$7
  render_defaults_write "$domain" "$key" "$type" "$value"
}
```

Dispatch `dry-run` to `for_each_setting dry_run_setting`.

**Step 3: Verify dry-run does not mutate**

Run:

```bash
bash -n macos-setup
shellcheck macos-setup
./macos-setup --dry-run
./macos-setup --dry-run --section screen
```

Expected: output consists only of `defaults write ...` command text. No `osascript`, no app quit, no `defaults write` execution.

**Step 4: Commit**

```bash
git add macos-setup README.md
git commit -m "feat(cli): add dry run output"
```

---

## Task 4: Implement `--check` drift detection

**Objective:** Read current values and report PASS/FAIL/MISSING without writing preferences.

**Files:**

- Modify: `macos-setup`
- Modify: `README.md`

**Step 1: Add read helper**

```bash
read_default() {
  domain=$1 key=$2
  defaults read "$domain" "$key" 2>/dev/null
}
```

**Step 2: Normalize values**

For first series, support bool and int normalization only.

```bash
normalize_value() {
  type=$1 raw=$2
  case "$type" in
    bool)
      case "$raw" in
        1|true|TRUE|True|YES|Yes|yes) printf 'true' ;;
        0|false|FALSE|False|NO|No|no) printf 'false' ;;
        *) printf '%s' "$raw" ;;
      esac
      ;;
    int) printf '%s' "$raw" ;;
    float|string) printf '%s' "$raw" ;;
    *) printf '%s' "$raw" ;;
  esac
}
```

**Step 3: Add check action**

```bash
check_setting() {
  section=$1 label=$2 domain=$3 key=$4 type=$5 expected=$6 _restart=$7
  raw=$(read_default "$domain" "$key") || {
    printf 'MISSING\t%s\t%s\t%s\texpected=%s\t%s\n' "$section" "$domain" "$key" "$expected" "$label"
    return 0
  }
  actual=$(normalize_value "$type" "$raw")
  expected_norm=$(normalize_value "$type" "$expected")
  if [ "$actual" = "$expected_norm" ]; then
    printf 'PASS\t%s\t%s\t%s\t%s\t%s\n' "$section" "$domain" "$key" "$actual" "$label"
  else
    printf 'FAIL\t%s\t%s\t%s\texpected=%s\tactual=%s\t%s\n' "$section" "$domain" "$key" "$expected_norm" "$actual" "$label"
    CHECK_FAILED=1
  fi
}
```

Initialize `CHECK_FAILED=0` before dispatch. Exit `1` when failures exist; exit `0` for all pass. Missing values should count as failure if desired. Recommended: set `CHECK_FAILED=1` for both `FAIL` and `MISSING` because desired state is not present.

**Step 4: Verify without applying**

Run:

```bash
bash -n macos-setup
shellcheck macos-setup
./macos-setup --check --section screen
./macos-setup --check --section safari
```

Expected: PASS/FAIL/MISSING rows. No writes. Exit status may be 1 if current machine drifts from desired state.

**Step 5: Commit**

```bash
git add macos-setup README.md
git commit -m "feat(check): report macos defaults drift"
```

---

## Task 5: Implement explicit `--apply`

**Objective:** Move current active `defaults write` behavior behind explicit `--apply` using registry data.

**Files:**

- Modify: `macos-setup`
- Modify: `README.md`

**Step 1: Add apply helper**

```bash
apply_setting() {
  section=$1 label=$2 domain=$3 key=$4 type=$5 value=$6 _restart=$7
  printf 'Applying [%s] %s...\n' "$section" "$label"
  case "$type" in
    bool) defaults write "$domain" "$key" -bool "$value" ;;
    int) defaults write "$domain" "$key" -int "$value" ;;
    float) defaults write "$domain" "$key" -float "$value" ;;
    string) defaults write "$domain" "$key" -string "$value" ;;
    *) printf 'error: unsupported type: %s\n' "$type" >&2; return 1 ;;
  esac
}
```

**Step 2: Move System Settings quit into apply-only path**

Only `--apply` should run:

```bash
osascript -e 'tell application "System Preferences" to quit' 2>/dev/null || true
osascript -e 'tell application "System Settings" to quit' 2>/dev/null || true
```

Use both app names for compatibility. Do not call either in read-only modes.

**Step 3: Remove or comment duplicate imperative active `defaults write` lines**

Once `--apply` uses the registry, remove the old active lines or turn them into comments in an "Historical commented settings" section. Avoid duplicate writes.

**Step 4: Verify syntax and dry modes**

Run:

```bash
bash -n macos-setup
shellcheck macos-setup
./macos-setup --list
./macos-setup --dry-run
./macos-setup --check --section screen
```

Do **not** run `./macos-setup --apply` as part of automated verification unless explicitly approved, because it mutates live preferences.

**Step 5: Optional supervised apply smoke test**

If a human approves live mutation, run a narrow safe section:

```bash
./macos-setup --apply --section screen
./macos-setup --check --section screen
```

Expected: screen section passes.

**Step 6: Commit**

```bash
git add macos-setup README.md
git commit -m "feat(apply): require explicit macos defaults writes"
```

---

## Task 6: Add GitHub Actions validation CI

**Objective:** Validate script syntax and ShellCheck on pull requests and pushes.

**Files:**

- Create: `.github/workflows/validate.yml`
- Modify: `README.md`

**Step 1: Add workflow**

```yaml
name: Validate

on:
  pull_request:
  push:
    branches: [main]

permissions:
  contents: read

jobs:
  shell:
    name: Shell validation
    runs-on: macos-latest
    steps:
      - name: Checkout
        uses: actions/checkout@v4
        with:
          submodules: false

      - name: Bash syntax
        run: bash -n macos-setup

      - name: Install ShellCheck
        run: brew install shellcheck

      - name: ShellCheck
        run: shellcheck macos-setup

      - name: CLI smoke tests
        run: |
          ./macos-setup --help
          ./macos-setup --list
          ./macos-setup --dry-run
```

Do not run `--check` in CI at first because macOS runner defaults may vary and could produce noisy failure exits. Do not run `--apply` in CI.

**Step 2: Update README**

Mention validation commands:

```bash
bash -n macos-setup
shellcheck macos-setup
./macos-setup --dry-run
```

**Step 3: Verify locally**

Run:

```bash
bash -n macos-setup
shellcheck macos-setup
./macos-setup --help
./macos-setup --list
./macos-setup --dry-run
```

**Step 4: Commit**

```bash
git add .github/workflows/validate.yml README.md
git commit -m "ci: validate macos setup script"
```

---

## Task 7: Update project documentation and close first series

**Objective:** Make the new workflow understandable for humans and bootstrap tools.

**Files:**

- Modify: `README.md`
- Optionally Modify: `AGENTS.md` if agent-specific safety notes are needed.

**Step 1: Update README sections**

Recommended headings:

- Rationale
- Safety model
- Usage
- Sections
- Validation
- Compatibility
- Development workflow

Usage should include:

```bash
./macos-setup --list
./macos-setup --dry-run
./macos-setup --check
./macos-setup --apply
./macos-setup --section screen --check
```

**Step 2: Add explicit warning**

Document:

- `--apply` changes live macOS preferences.
- `--check` is read-only.
- `--dry-run` prints commands only.
- Admin/destructive settings are intentionally out of scope for the first series.

**Step 3: Verify final state**

Run:

```bash
git diff --check
bash -n macos-setup
shellcheck macos-setup
./macos-setup --help
./macos-setup --list
./macos-setup --dry-run
./macos-setup --check --section screen || true
```

Expected: all validation passes except `--check` may exit nonzero if current machine drifts.

**Step 4: Commit**

```bash
git add README.md AGENTS.md macos-setup
git commit -m "docs: document explicit macos setup workflow"
```

---

## Follow-up Series Candidates

Do not implement these in the first series unless explicitly requested:

1. **Admin/destructive action classes**
   - `sudo defaults`, `pmset`, `systemsetup`, `mdutil`, Dock DB resets.
   - Require `--include-admin` / `--include-destructive` flags.

2. **Current-host settings**
   - `defaults -currentHost` support.

3. **PlistBuddy actions**
   - Finder icon view settings.

4. **App restart orchestration**
   - Controlled `killall` only for affected apps, behind `--restart-apps`.

5. **Generated docs**
   - `./macos-setup --docs` to produce settings tables.

6. **Machine/profile data**
   - Support host/profile-specific desired state without hardcoding local identifiers.

7. **Compatibility audit against current macOS**
   - Validate legacy Safari Java keys and Software Update keys on modern macOS.

---

## Acceptance Criteria

The first improvement series is complete when:

- `./macos-setup --help` explains modes and safety.
- `./macos-setup --list` lists current active desired-state settings.
- `./macos-setup --dry-run` prints commands without writing preferences.
- `./macos-setup --check` reports drift without writing preferences.
- `./macos-setup --apply` is the only path that writes preferences.
- Existing active desired-state settings are preserved unless explicitly removed with rationale.
- `bash -n macos-setup` passes.
- `shellcheck macos-setup` passes.
- CI validates syntax, ShellCheck, and read-only CLI smoke tests.
- README documents the new explicit workflow.
- Follow-up Beads issues exist for any deferred admin/destructive/profile/app-restart behavior.

---

## Suggested Beads Breakdown

Create implementation issues in this order:

1. `feat(cli): add explicit modes and parser`
2. `feat(settings): add setting registry and list mode`
3. `feat(cli): add dry-run mode`
4. `feat(check): add read-only drift detection`
5. `feat(apply): move writes behind explicit apply mode`
6. `ci: add shell validation workflow`
7. `docs: document explicit macOS setup workflow`

The existing Beads sync issue should remain separate from this utility improvement series:

- `macos-dd9`: Repair Beads Dolt sync and macOS pre-push timeout behavior
