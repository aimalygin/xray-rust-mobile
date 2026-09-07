#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/_common.sh"

require_command gh
[[ -n "${GITHUB_REPOSITORY:-}" ]] || die "GITHUB_REPOSITORY is required"
[[ "$APPLE_ARTIFACT_RUN_ID" =~ ^[1-9][0-9]*$ ]] ||
  die "prepared Apple workflow artifact run id is required"

run="$({
  gh api "repos/$GITHUB_REPOSITORY/actions/runs/$APPLE_ARTIFACT_RUN_ID" \
    --jq '[.head_sha, .head_commit.tree_id, .path, .event, .head_branch, .status] | @tsv'
})"
expected_run="$APPLE_ARTIFACT_SOURCE_COMMIT"$'\t'"$APPLE_ARTIFACT_SOURCE_TREE"$'\t'\
'.github/workflows/prepare-release.yml'$'\tworkflow_dispatch\tmain\tcompleted'
[[ "$run" == "$expected_run" ]] ||
  die "Apple artifact run provenance differs from release/artifacts.env"

job="$({
  gh api "repos/$GITHUB_REPOSITORY/actions/runs/$APPLE_ARTIFACT_RUN_ID/jobs?per_page=100" \
    --jq '.jobs[] | select(.name == "apple-artifact") | [.conclusion, .head_sha] | @tsv'
})"
[[ "$job" == $'success\t'"$APPLE_ARTIFACT_SOURCE_COMMIT" ]] ||
  die "Apple artifact producer job did not succeed at the locked source commit"

artifact="$({
  gh api "repos/$GITHUB_REPOSITORY/actions/runs/$APPLE_ARTIFACT_RUN_ID/artifacts?per_page=100" \
    --jq ".artifacts[] | select(.name == \"$APPLE_ARTIFACT_NAME\" and .expired == false) | [.name, .workflow_run.head_sha] | @tsv"
})"
[[ "$artifact" == "$APPLE_ARTIFACT_NAME"$'\t'"$APPLE_ARTIFACT_SOURCE_COMMIT" ]] ||
  die "locked Apple workflow artifact is missing, expired, or bound to another commit"

echo "verified Apple artifact workflow provenance: $APPLE_ARTIFACT_RUN_ID"
