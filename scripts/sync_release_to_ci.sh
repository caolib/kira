#!/usr/bin/env bash
set -euo pipefail

ARTIFACT_DIR="${1:?Usage: sync_release_to_ci.sh <artifact-dir> <notes-file>}"
NOTES_FILE="${2:?Usage: sync_release_to_ci.sh <artifact-dir> <notes-file>}"
: "${RELEASE_TAG:?RELEASE_TAG is required}"
: "${GITHUB_REPOSITORY:?GITHUB_REPOSITORY is required}"
: "${GITHUB_SHA:?GITHUB_SHA is required}"
test -s "$NOTES_FILE"

shopt -s nullglob
APKS=("$ARTIFACT_DIR"/kira-*-arm64-v8a.apk)
if [ "${#APKS[@]}" -ne 1 ]; then
  printf 'Expected exactly one arm64 APK, found %s\n' "${#APKS[@]}" >&2
  exit 1
fi

APK_NAME="${APKS[0]##*/}"
# build_apk.ps1 产物为 kira-vX.Y.Z-BUILD-arm64-v8a.apk；预览渠道只解析 X.Y.Z+BUILD。
if [[ ! "$APK_NAME" =~ ^kira-v([0-9]+\.[0-9]+\.[0-9]+)-([0-9]+)-arm64-v8a\.apk$ ]]; then
  printf 'Unexpected release APK filename: %s\n' "$APK_NAME" >&2
  exit 1
fi
CI_APK_NAME="kira-${BASH_REMATCH[1]}+${BASH_REMATCH[2]}-arm64-v8a.apk"

# 仅复制和改名，复用正式版签名包，不修改原产物或重新构建。
STAGING_DIR=$(mktemp -d)
trap 'rm -rf "$STAGING_DIR"' EXIT
CI_APK="$STAGING_DIR/$CI_APK_NAME"
cp "${APKS[0]}" "$CI_APK"

if gh release view CI --repo="$GITHUB_REPOSITORY" > /dev/null 2>&1; then
  # 同 build 重试可覆盖同名包，其余历史包保留；上传成功后再更新说明。
  gh release upload CI "$CI_APK" \
    --repo="$GITHUB_REPOSITORY" \
    --clobber

  gh release edit CI \
    --repo="$GITHUB_REPOSITORY" \
    --title="$RELEASE_TAG" \
    --notes-file "$NOTES_FILE" \
    --prerelease \
    --latest=false
else
  gh release create CI "$CI_APK" \
    --repo="$GITHUB_REPOSITORY" \
    --target="$GITHUB_SHA" \
    --title="$RELEASE_TAG" \
    --notes-file "$NOTES_FILE" \
    --prerelease \
    --latest=false
fi
