#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/_common.sh"

require_command gh
require_tagged_core
evidence_profile="$("$SCRIPT_DIR/release-evidence-profile.sh" "$XRAY_MOBILE_VERSION")"

core_repository="${XRAY_RUST_REPOSITORY#https://github.com/}"
core_repository="${core_repository%.git}"
[[ "$core_repository" =~ ^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$ ]] ||
  die "unsupported core GitHub repository URL: $XRAY_RUST_REPOSITORY"
[[ "$XRAY_RUST_COMMIT" =~ ^[0-9a-f]{40}$ ]] || die "invalid locked core commit"
[[ "$XRAY_RUST_TREE" =~ ^[0-9a-f]{40}$ ]] || die "invalid locked core tree"

workflow="$({
  gh api "repos/$core_repository/actions/workflows/$evidence_profile-release-evidence.yml" \
    --jq '[.id, .path, .state] | @tsv'
})"
IFS=$'\t' read -r workflow_id workflow_path workflow_state <<<"$workflow"
[[ "$workflow_id" =~ ^[1-9][0-9]*$ ]] || die "core evidence workflow id is invalid"
[[ "$workflow_path" == ".github/workflows/$evidence_profile-release-evidence.yml" ]] ||
  die "core evidence workflow path differs"
[[ "$workflow_state" == "active" ]] || die "core evidence workflow is not active"

run_id="$({
  gh api \
    "repos/$core_repository/actions/workflows/$evidence_profile-release-evidence.yml/runs?event=workflow_dispatch&status=success&head_sha=$XRAY_RUST_COMMIT&per_page=100" \
    --jq ".workflow_runs | map(select(.head_sha == \"$XRAY_RUST_COMMIT\")) | sort_by(.created_at) | last | .id // empty"
})"
[[ "$run_id" =~ ^[1-9][0-9]*$ ]] ||
  die "no successful core $evidence_profile evidence run exists for $XRAY_RUST_COMMIT"

run="$({
  gh api "repos/$core_repository/actions/runs/$run_id" \
    --jq '[.workflow_id, .head_sha, .head_commit.tree_id, .head_repository.full_name, .event, .status, .conclusion] | @tsv'
})"
expected_run="$workflow_id"$'\t'"$XRAY_RUST_COMMIT"$'\t'"$XRAY_RUST_TREE"$'\t'\
"$core_repository"$'\tworkflow_dispatch\tcompleted\tsuccess'
[[ "$run" == "$expected_run" ]] ||
  die "core $evidence_profile evidence run is not bound to the locked commit and tree"

artifact="$({
  gh api "repos/$core_repository/actions/runs/$run_id/artifacts?per_page=100" \
    --jq ".artifacts[] | select(.name == \"$evidence_profile-release-evidence-$XRAY_RUST_COMMIT\" and .expired == false) | [.name, .workflow_run.head_sha] | @tsv"
})"
expected_artifact="$evidence_profile-release-evidence-$XRAY_RUST_COMMIT"$'\t'"$XRAY_RUST_COMMIT"
[[ "$artifact" == "$expected_artifact" ]] ||
  die "validated core $evidence_profile evidence artifact is missing, expired, duplicated, or bound to another commit"

echo "verified core $evidence_profile release evidence run: $run_id"
