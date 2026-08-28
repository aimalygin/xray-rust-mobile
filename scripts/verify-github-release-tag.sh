#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/_common.sh"

tag="${1:-}"
expected_tag_object="${2:-}"
expected_commit="${3:-}"
[[ "$#" -eq 3 ]] ||
  die "usage: $0 <tag> <annotated-tag-object> <commit>"
[[ "$tag" == "v$XRAY_MOBILE_VERSION" ]] ||
  die "release tag $tag does not match v$XRAY_MOBILE_VERSION"
[[ "$expected_tag_object" =~ ^[0-9a-f]{40}$ ]] ||
  die "invalid expected annotated tag object: $expected_tag_object"
[[ "$expected_commit" =~ ^[0-9a-f]{40}$ ]] ||
  die "invalid expected release commit: $expected_commit"
[[ -n "${GITHUB_REPOSITORY:-}" ]] ||
  die "GITHUB_REPOSITORY is required"
require_command gh

read -r ref_type live_tag_object <<<"$(
  gh api \
    "repos/$GITHUB_REPOSITORY/git/ref/tags/$tag" \
    --jq '[.object.type, .object.sha] | @tsv'
)"
[[ "$ref_type" == "tag" ]] ||
  die "release ref refs/tags/$tag is not annotated"
[[ "$live_tag_object" == "$expected_tag_object" ]] ||
  die "release tag object moved: $live_tag_object, expected $expected_tag_object"

read -r target_type live_commit <<<"$(
  gh api \
    "repos/$GITHUB_REPOSITORY/git/tags/$live_tag_object" \
    --jq '[.object.type, .object.sha] | @tsv'
)"
[[ "$target_type" == "commit" ]] ||
  die "annotated release tag does not point directly to a commit"
[[ "$live_commit" == "$expected_commit" ]] ||
  die "release tag commit moved: $live_commit, expected $expected_commit"

echo "verified live annotated release tag $tag at $expected_commit"
