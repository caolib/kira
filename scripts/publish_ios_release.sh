#!/usr/bin/env bash
# Run from the repository root. This script never moves the fixed ios-build tag.
set -euo pipefail

ARTIFACT_DIR="${1:?Usage: publish_ios_release.sh <artifact-dir> <toolchain-file> <native-lock-report>}"
TOOLCHAIN_FILE="${2:?Usage: publish_ios_release.sh <artifact-dir> <toolchain-file> <native-lock-report>}"
NATIVE_LOCK_REPORT="${3:?Usage: publish_ios_release.sh <artifact-dir> <toolchain-file> <native-lock-report>}"
: "${GITHUB_REPOSITORY:?GITHUB_REPOSITORY is required}"
: "${GITHUB_SHA:?GITHUB_SHA is required}"
: "${GITHUB_RUN_ID:?GITHUB_RUN_ID is required}"
: "${GITHUB_RUN_ATTEMPT:?GITHUB_RUN_ATTEMPT is required}"
TAG=ios-build

test -s "$TOOLCHAIN_FILE"
test -s "$NATIVE_LOCK_REPORT"
# Reinspect the sealed IPA on Ubuntu, including real device Mach-O metadata and Unix modes.
VERSION=$(python3 -I scripts/package_ios.py verify-release \
  --artifact-dir "$ARTIFACT_DIR" --pubspec pubspec.yaml --print-version)
shopt -s nullglob
IPAS=("$ARTIFACT_DIR"/*.ipa)
CHECKSUMS=("$ARTIFACT_DIR"/*.sha256)
test "${#IPAS[@]}" -eq 1
test "${#CHECKSUMS[@]}" -eq 1

STAGING=$(mktemp -d)
trap 'rm -rf "$STAGING"' EXIT
NOTES_FILE="$STAGING/release-notes.md"
# NOTE stays data in the environment. It is never interpolated into shell source or evaluated.
python3 -I scripts/ios_ci.py notes --version "$VERSION" \
  --toolchain "$TOOLCHAIN_FILE" --native-lock "$NATIVE_LOCK_REPORT" --output "$NOTES_FILE"
TITLE="kira $VERSION — iOS unsigned"

# gh release view's generic nonzero status cannot distinguish a missing release from network/auth failure.
# Use the HTTP response instead: only the explicit 404 path may create a new release.
if gh api --include --method GET \
  "repos/$GITHUB_REPOSITORY/releases/tags/$TAG" > "$STAGING/view.http" 2> "$STAGING/view.err"; then
  gh release upload "$TAG" "${IPAS[0]}" "${CHECKSUMS[0]}" \
    --repo="$GITHUB_REPOSITORY" \
    --clobber

  # Change metadata only after every asset upload has succeeded; keep different-version historical assets.
  gh release edit "$TAG" \
    --repo="$GITHUB_REPOSITORY" \
    --title="$TITLE" \
    --notes-file "$NOTES_FILE" \
    --prerelease \
    --latest=false
else
  STATUS=''
  while IFS= read -r line; do
    if [[ "$line" =~ ^HTTP/[0-9.]+[[:space:]]+([0-9]{3})([[:space:]]|$) ]]; then
      STATUS="${BASH_REMATCH[1]}"
    fi
  done < "$STAGING/view.http"
  if [ "$STATUS" != 404 ]; then
    printf 'Release lookup failed (HTTP %s); refusing to create ios-build.\n' "${STATUS:-unknown}" >&2
    while IFS= read -r line; do
      printf '%s\n' "$line" >&2
    done < "$STAGING/view.err"
    exit 1
  fi

  gh release create "$TAG" "${IPAS[0]}" "${CHECKSUMS[0]}" \
    --repo="$GITHUB_REPOSITORY" \
    --target="$GITHUB_SHA" \
    --title="$TITLE" \
    --notes-file "$NOTES_FILE" \
    --prerelease \
    --latest=false
fi
