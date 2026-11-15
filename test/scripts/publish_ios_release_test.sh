#!/usr/bin/env bash
# Run from the repository root: bash test/scripts/publish_ios_release_test.sh
set -euo pipefail

TEST_ROOT=$(mktemp -d)
trap 'rm -rf "$TEST_ROOT"' EXIT
export GITHUB_REPOSITORY=test/repo
export GITHUB_SHA=0123456789abcdef0123456789abcdef01234567
export GITHUB_RUN_ID=12345 GITHUB_RUN_ATTEMPT=2
export VERIFY_ANALYSIS=success VERIFY_SCRIPTS=success
export FLUTTER_TESTS=success SIMULATOR_TEST=success SKIP_TESTS=false
export TEST_PUBSPEC_VERSION
TEST_PUBSPEC_VERSION=$(python3 -I -c '
import importlib.util
from pathlib import Path
spec = importlib.util.spec_from_file_location("package_ios", Path("scripts/package_ios.py").resolve())
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)
print(module.pubspec_version("pubspec.yaml"))
')
export IPA_NAME="kira-$TEST_PUBSPEC_VERSION-ios-unsigned.ipa"

# Only GitHub is mocked. The real Python IPA/hash validation and notes generator still execute.
gh() {
  printf '%s\n' "$*" >> "$TEST_DIR/gh.log"
  case "$1 $2" in
    'api --include')
      if [ "$MOCK_STATUS" = network ]; then
        printf 'network connection failed\n' >&2
        return 1
      fi
      printf 'HTTP/2 %s Mock\r\nContent-Type: application/json\r\n\r\n{}\n' "$MOCK_STATUS"
      [ "$MOCK_STATUS" = 200 ]
      ;;
    'release upload'|'release create')
      test "$3" = ios-build
      test "${4##*/}" = "$IPA_NAME"
      test "${5##*/}" = "$IPA_NAME.sha256"
      test "$MOCK_UPLOAD_EXIT" -eq 0 || return "$MOCK_UPLOAD_EXIT"
      cp "$4" "$TEST_DIR/uploaded.ipa"
      test "$MOCK_SECOND_UPLOAD_EXIT" -eq 0 || return "$MOCK_SECOND_UPLOAD_EXIT"
      cp "$5" "$TEST_DIR/uploaded.sha256"
      if [ "$2" = create ]; then
        capture_notes "$@"
      fi
      ;;
    'release edit')
      test "$3" = ios-build
      capture_notes "$@"
      ;;
    *) return 99 ;;
  esac
}

capture_notes() {
  local previous='' value
  for value in "$@"; do
    if [ "$previous" = --notes-file ]; then
      cp "$value" "$TEST_DIR/published-notes.md"
    fi
    previous="$value"
  done
  test -s "$TEST_DIR/published-notes.md"
}
export -f gh capture_notes

setup_case() {
  TEST_DIR=$(mktemp -d "$TEST_ROOT/case.XXXXXX")
  export TEST_DIR MOCK_STATUS=200 MOCK_UPLOAD_EXIT=0 MOCK_SECOND_UPLOAD_EXIT=0
  export VERIFY_ANALYSIS=success VERIFY_SCRIPTS=success
  export FLUTTER_TESTS=success SIMULATOR_TEST=success SKIP_TESTS=false
  mkdir "$TEST_DIR/artifacts"
  : > "$TEST_DIR/gh.log"
  export NOTE='$(touch "'"$TEST_DIR"'/injected"); `uname`; "quoted"; single '\''quote'\''
中文说明，不执行代码'
  printf 'Runner: macos-15\nFlutter 3.44.2\nXcode 26.3\nCocoaPods 1.16.2\n' > "$TEST_DIR/toolchain.txt"
  printf 'Native dependency lock: generated on this run; not yet locked in source control\nOrderedSet resolved dependencies: OrderedSet (6.0.3)\n' > "$TEST_DIR/native-lock.txt"
  python3 -I -c '
import importlib.util, os
from pathlib import Path
spec = importlib.util.spec_from_file_location("ios_test_support", Path("test/scripts/ios_test_support.py").resolve())
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)
module.write_ipa(Path(os.environ["TEST_DIR"]) / "artifacts" / os.environ["IPA_NAME"], version=os.environ["TEST_PUBSPEC_VERSION"])
'
}

run_publish() {
  bash scripts/publish_ios_release.sh "$TEST_DIR/artifacts" "$TEST_DIR/toolchain.txt" "$TEST_DIR/native-lock.txt"
}

expect_asset_failure() {
  if run_publish > "$TEST_DIR/error.log" 2>&1; then
    printf 'Expected validation failure: %s\n' "$1" >&2
    exit 1
  fi
  [[ "$(< "$TEST_DIR/error.log")" == *"$1"* ]]
  test ! -s "$TEST_DIR/gh.log"
}

verify_notes() {
  test ! -e "$TEST_DIR/injected"
  local notes
  notes=$(< "$TEST_DIR/published-notes.md")
  [[ "$notes" == *"$NOTE"* ]]
  [[ "$notes" == *"$GITHUB_SHA"* ]]
  [[ "$notes" == *"https://github.com/test/repo/actions/runs/$GITHUB_RUN_ID"* ]]
  [[ "$notes" == *'Flutter 3.44.2'*'Xcode 26.3'* ]]
  [[ "$notes" == *'未签名'*'不能直接安装'*'重签'* ]]
  [[ "$notes" == *'OrderedSet (6.0.3)'* ]]
}

setup_case
run_publish
cmp "$TEST_DIR/artifacts/$IPA_NAME" "$TEST_DIR/uploaded.ipa"
cmp "$TEST_DIR/artifacts/$IPA_NAME.sha256" "$TEST_DIR/uploaded.sha256"
CALLS=$(< "$TEST_DIR/gh.log")
[[ "$CALLS" == *'release upload ios-build '*'--clobber'*$'\nrelease edit ios-build '* ]]
[[ "$CALLS" == *'--prerelease --latest=false'* ]]
[[ "$CALLS" != *'release create'* ]]
[[ "$CALLS" != *'release delete'* ]]
verify_notes
run_publish
cmp "$TEST_DIR/artifacts/$IPA_NAME" "$TEST_DIR/uploaded.ipa"
printf 'PASS: existing ios-build uploads both assets before notes, retries safely, preserves historical versions\n'

setup_case
MOCK_STATUS=404
run_publish
CALLS=$(< "$TEST_DIR/gh.log")
[[ "$CALLS" == *'release create ios-build '*"--target=$GITHUB_SHA"*'--prerelease --latest=false'* ]]
[[ "$CALLS" != *'release edit'* ]]
verify_notes
printf 'PASS: explicit HTTP 404 creates fixed prerelease against full source SHA\n'

for status in network 401 403 429 500; do
  setup_case
  MOCK_STATUS="$status"
  if run_publish > "$TEST_DIR/error.log" 2>&1; then
    printf 'Expected lookup failure for %s\n' "$status" >&2
    exit 1
  fi
  CALLS=$(< "$TEST_DIR/gh.log")
  [[ "$CALLS" != *'release create'* ]]
  [[ "$CALLS" != *'release upload'* ]]
  [[ "$CALLS" != *'release edit'* ]]
done
printf 'PASS: network/auth/rate/server failures are never mistaken for a missing release\n'

for second in false true; do
  setup_case
  if [ "$second" = true ]; then
    MOCK_SECOND_UPLOAD_EXIT=8
  else
    MOCK_UPLOAD_EXIT=7
  fi
  if run_publish > "$TEST_DIR/error.log" 2>&1; then
    printf 'Expected upload failure to propagate\n' >&2
    exit 1
  fi
  CALLS=$(< "$TEST_DIR/gh.log")
  [[ "$CALLS" == *'release upload ios-build '* ]]
  [[ "$CALLS" != *'release edit'* ]]
  [[ "$CALLS" != *'release create'* ]]
done
printf 'PASS: first or second asset upload failure never edits release metadata\n'

setup_case
MOCK_STATUS=404 MOCK_UPLOAD_EXIT=9
if run_publish > "$TEST_DIR/error.log" 2>&1; then
  printf 'Expected creation failure to propagate\n' >&2
  exit 1
fi
printf 'PASS: release creation failures propagate\n'

setup_case
rm "$TEST_DIR/artifacts/$IPA_NAME"
expect_asset_failure 'Expected exactly one IPA, found 0'
setup_case
cp "$TEST_DIR/artifacts/$IPA_NAME" "$TEST_DIR/artifacts/kira-99.0.0+1-ios-unsigned.ipa"
expect_asset_failure 'Expected exactly one IPA, found 2'
setup_case
rm "$TEST_DIR/artifacts/$IPA_NAME.sha256"
expect_asset_failure 'matching SHA-256'
setup_case
printf '%064d  %s\n' 0 "$IPA_NAME" > "$TEST_DIR/artifacts/$IPA_NAME.sha256"
expect_asset_failure 'SHA-256 mismatch'
printf 'PASS: missing/ambiguous IPA and missing/bad checksum fail before any GitHub call\n'

setup_case
SKIP_TESTS=true FLUTTER_TESTS=skipped SIMULATOR_TEST=skipped
run_publish
verify_notes
NOTES=$(< "$TEST_DIR/published-notes.md")
[[ "$NOTES" == *'未执行，不代表通过'* ]]
[[ "$NOTES" != *'全量 Flutter 测试：通过'* ]]
[[ "$NOTES" != *'iOS 模拟器烟测：通过'* ]]
printf 'PASS: skipped Flutter and simulator tests are explicitly not reported as passed\n'

setup_case
SIMULATOR_TEST=failure
expect_asset_failure 'Unexpected iOS simulator test status'
printf 'PASS: failed test status cannot publish a passing release description\n'
