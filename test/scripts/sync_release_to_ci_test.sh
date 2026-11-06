#!/usr/bin/env bash
# 在仓库根目录执行：bash test/scripts/sync_release_to_ci_test.sh
set -euo pipefail

TEST_ROOT=$(mktemp -d)
trap 'rm -rf "$TEST_ROOT"' EXIT
export RELEASE_TAG=v1.7.5
export GITHUB_REPOSITORY=test/repo
export GITHUB_SHA=0123456789abcdef

# 只模拟 gh，不访问 GitHub；保存实际上传内容以验证仅改文件名。
gh() {
  printf '%s\n' "$*" >> "$TEST_DIR/gh.log"
  case "$1 $2" in
    'release view') return "$MOCK_VIEW_EXIT" ;;
    'release upload'|'release create')
      if [ "$MOCK_UPLOAD_EXIT" -ne 0 ]; then
        return "$MOCK_UPLOAD_EXIT"
      fi
      test "${4##*/}" = 'kira-1.7.5+625-arm64-v8a.apk'
      cp "$4" "$TEST_DIR/uploaded.apk"
      ;;
    'release edit') return 0 ;;
    *) return 99 ;;
  esac
}
export -f gh

setup_case() {
  TEST_DIR=$(mktemp -d "$TEST_ROOT/case.XXXXXX")
  export TEST_DIR MOCK_VIEW_EXIT=0 MOCK_UPLOAD_EXIT=0
  mkdir "$TEST_DIR/artifacts"
  printf 'signed arm64 apk\n' > "$TEST_DIR/artifacts/kira-v1.7.5-625-arm64-v8a.apk"
  printf 'other architecture\n' > "$TEST_DIR/artifacts/kira-v1.7.5-625-x86_64.apk"
  printf 'release notes\n' > "$TEST_DIR/notes.md"
  : > "$TEST_DIR/gh.log"
}

run_sync() {
  bash scripts/sync_release_to_ci.sh "$TEST_DIR/artifacts" "$TEST_DIR/notes.md"
}

expect_failure() {
  if run_sync > "$TEST_DIR/error.log" 2>&1; then
    printf 'Expected synchronization to fail\n' >&2
    exit 1
  fi
  [[ "$(< "$TEST_DIR/error.log")" == *"$1"* ]]
  test ! -s "$TEST_DIR/gh.log"
}

setup_case
run_sync
cmp "$TEST_DIR/artifacts/kira-v1.7.5-625-arm64-v8a.apk" "$TEST_DIR/uploaded.apk"
CALLS=$(< "$TEST_DIR/gh.log")
[[ "$CALLS" == *'release upload CI '*'--clobber'*$'\nrelease edit CI '* ]]
[[ "$CALLS" == *'--title=v1.7.5'* ]]
[[ "$CALLS" == *"--notes-file $TEST_DIR/notes.md"* ]]
[[ "$CALLS" == *'--prerelease --latest=false'* ]]
[[ "$CALLS" != *'release create'* ]]
# 同版本重试仍上传相同文件，并带覆盖标记。
run_sync
cmp "$TEST_DIR/artifacts/kira-v1.7.5-625-arm64-v8a.apk" "$TEST_DIR/uploaded.apk"
printf 'PASS: existing CI, exact APK copy, notes, prerelease flags and retry\n'

setup_case
MOCK_VIEW_EXIT=1
run_sync
cmp "$TEST_DIR/artifacts/kira-v1.7.5-625-arm64-v8a.apk" "$TEST_DIR/uploaded.apk"
CALLS=$(< "$TEST_DIR/gh.log")
[[ "$CALLS" == *'release create CI '* ]]
[[ "$CALLS" == *'--target=0123456789abcdef'* ]]
[[ "$CALLS" == *'--title=v1.7.5'* ]]
[[ "$CALLS" == *"--notes-file $TEST_DIR/notes.md"* ]]
[[ "$CALLS" == *'--prerelease --latest=false'* ]]
[[ "$CALLS" != *'release edit'* ]]
printf 'PASS: create missing CI with APK and release notes\n'

setup_case
rm "$TEST_DIR/artifacts/kira-v1.7.5-625-arm64-v8a.apk"
expect_failure 'Expected exactly one arm64 APK, found 0'
printf 'PASS: reject missing arm64 APK before publishing\n'

setup_case
cp "$TEST_DIR/artifacts/kira-v1.7.5-625-arm64-v8a.apk" \
  "$TEST_DIR/artifacts/kira-v1.7.5-626-arm64-v8a.apk"
expect_failure 'Expected exactly one arm64 APK, found 2'
printf 'PASS: reject ambiguous arm64 APKs before publishing\n'

setup_case
mv "$TEST_DIR/artifacts/kira-v1.7.5-625-arm64-v8a.apk" \
  "$TEST_DIR/artifacts/kira-v1.7.5-arm64-v8a.apk"
expect_failure 'Unexpected release APK filename'
printf 'PASS: reject missing build number before publishing\n'

setup_case
MOCK_UPLOAD_EXIT=1
if run_sync; then
  printf 'Expected upload failure to propagate\n' >&2
  exit 1
fi
CALLS=$(< "$TEST_DIR/gh.log")
[[ "$CALLS" == *'release upload CI '* ]]
[[ "$CALLS" != *'release edit'* ]]
[[ "$CALLS" != *'release create'* ]]
printf 'PASS: upload failure does not replace release notes\n'

setup_case
MOCK_VIEW_EXIT=1
MOCK_UPLOAD_EXIT=1
if run_sync; then
  printf 'Expected creation failure to propagate\n' >&2
  exit 1
fi
printf 'PASS: creation failure propagates\n'
