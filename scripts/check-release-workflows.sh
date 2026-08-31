#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/_common.sh"

require_text() {
  local file="$1"
  local text="$2"
  local message="$3"
  grep -Fq -- "$text" "$file" || die "$message"
}

extract_job() {
  local file="$1"
  local job="$2"
  awk -v header="  $job:" '
    $0 == header { capture = 1 }
    capture && $0 ~ /^  [A-Za-z0-9_-]+:$/ && $0 != header { exit }
    capture { print }
  ' "$file"
}

require_block_text() {
  local block="$1"
  local text="$2"
  local message="$3"
  grep -Fq -- "$text" <<<"$block" || die "$message"
}

reject_block_text() {
  local block="$1"
  local text="$2"
  local message="$3"
  if grep -Fq -- "$text" <<<"$block"; then
    die "$message"
  fi
}

require_block_order() {
  local block="$1"
  local first="$2"
  local second="$3"
  local message="$4"
  local first_line second_line
  first_line="$(grep -nF -- "$first" <<<"$block" | head -n 1 | cut -d: -f1 || true)"
  second_line="$(grep -nF -- "$second" <<<"$block" | head -n 1 | cut -d: -f1 || true)"
  [[ -n "$first_line" && -n "$second_line" && "$first_line" -lt "$second_line" ]] ||
    die "$message"
}

expect_channel() {
  local expected="$1"
  local value="$2"
  local actual
  actual="$("$SCRIPT_DIR/release-channel.sh" "$value")"
  [[ "$actual" == "$expected" ]] ||
    die "release channel for $value is $actual, expected $expected"
}

expect_rejected() {
  local value="$1"
  if "$SCRIPT_DIR/release-channel.sh" "$value" >/dev/null 2>&1; then
    die "release version should be rejected: $value"
  fi
}

expect_channel stable 0.4.1
expect_channel stable v1.0.0
expect_channel prerelease 0.4.1-rc.1
expect_channel prerelease v0.4.1-rc.12
expect_rejected 00.4.1
expect_rejected 0.04.1
expect_rejected 0.4.01
expect_rejected 0.4.1-rc.01
expect_rejected 0.4.1-rc.0
expect_rejected 0.4.1-rc
expect_rejected 0.4.1-beta.1
expect_rejected 0.4.1+build.1
expect_rejected vv0.4.1
if "$SCRIPT_DIR/release-channel.sh" --require-stable v0.4.1-rc.1 >/dev/null 2>&1; then
  die "stable-only publication guard accepted an RC tag"
fi

release_workflow="$MOBILE_ROOT/.github/workflows/release.yml"
prepare_workflow="$MOBILE_ROOT/.github/workflows/prepare-release.yml"
central_workflow="$MOBILE_ROOT/.github/workflows/publish-maven-central.yml"
manifest_script="$MOBILE_ROOT/scripts/write-release-manifest.sh"
prepare_script="$MOBILE_ROOT/scripts/prepare-release.sh"
tag_verifier="$MOBILE_ROOT/scripts/verify-github-release-tag.sh"

require_text "$release_workflow" \
  "release_channel: \${{ steps.release.outputs.release_channel }}" \
  "release workflow does not export the release channel"
require_text "$release_workflow" \
  'verified_tag_object: ${{ steps.release.outputs.verified_tag_object }}' \
  "release workflow does not export the verified annotated tag object"
require_text "$release_workflow" \
  'verified_commit: ${{ steps.release.outputs.verified_commit }}' \
  "release workflow does not export the verified release commit"
require_text "$release_workflow" \
  $'  maven-publish:\n    needs: [metadata, draft-release]\n    if: needs.metadata.outputs.release_channel == \'stable\'' \
  "GitHub Packages publication is not restricted to stable releases"
require_text "$release_workflow" \
  "scripts/package-android.sh --standalone-only" \
  "prerelease Android packaging can still create a Maven archive"
require_text "$release_workflow" \
  'cp LICENSE "$dist/"' \
  "prerelease release assets omit the raw project license"
require_text "$release_workflow" \
  'cp THIRD_PARTY_NOTICES.md "$dist/"' \
  "prerelease release assets omit third-party notices"
require_text "$release_workflow" \
  '"$dist/LICENSE"' \
  "prerelease GitHub asset set omits the raw project license"
require_text "$manifest_script" \
  '"LICENSE": "%s"' \
  "prerelease manifest omits the raw project license checksum"
require_text "$manifest_script" \
  '      LICENSE' \
  "prerelease SHA256SUMS omits the raw project license"
require_text "$prepare_script" \
  'cp "$MOBILE_ROOT/LICENSE"' \
  "local prerelease preparation omits the raw project license"
require_text "$release_workflow" \
  "--prerelease" \
  "GitHub prereleases are not marked as prereleases"
require_text "$release_workflow" \
  "--latest=false" \
  "GitHub prereleases can be marked as the latest stable release"
require_text "$release_workflow" \
  "needs.maven-publish.result == 'skipped'" \
  "prerelease finalization does not require Maven publication to be skipped"

metadata_job="$(extract_job "$release_workflow" metadata)"
require_block_text "$metadata_job" \
  'ref: ${{ env.XRAY_RELEASE_TAG }}' \
  "release metadata does not check out the input tag"
require_block_text "$metadata_job" \
  'verified_tag_object="$(git rev-parse "$tag_ref^{tag}")"' \
  "release metadata does not record the annotated tag object"
require_block_text "$metadata_job" \
  'verified_commit="$(git rev-parse "$tag_ref^{commit}")"' \
  "release metadata does not record the peeled tag commit"

for job in apple-source apple-asset android-build draft-release maven-publish finalize-release; do
  block="$(extract_job "$release_workflow" "$job")"
  require_block_text "$block" \
    'ref: ${{ needs.metadata.outputs.verified_commit }}' \
    "$job does not check out the verified release commit"
  reject_block_text "$block" \
    'ref: ${{ env.XRAY_RELEASE_TAG }}' \
    "$job still checks out the mutable release tag"
done

draft_job="$(extract_job "$release_workflow" draft-release)"
require_block_order "$draft_job" \
  'scripts/verify-github-release-tag.sh' \
  'gh release create "$XRAY_RELEASE_TAG"' \
  "draft release mutation is not preceded by live tag validation"

maven_job="$(extract_job "$release_workflow" maven-publish)"
require_block_order "$maven_job" \
  'scripts/verify-github-release-tag.sh' \
  ':xraymobile:publishReleasePublicationToGitHubPackagesRepository' \
  "GitHub Packages publication is not preceded by live tag validation"

finalize_job="$(extract_job "$release_workflow" finalize-release)"
require_block_order "$finalize_job" \
  'scripts/verify-github-release-tag.sh' \
  'gh release edit "$XRAY_RELEASE_TAG"' \
  "release finalization is not preceded by live tag validation"

checksum_pr_job="$(extract_job "$prepare_workflow" checksum-pr)"
require_block_order "$checksum_pr_job" \
  'git push origin "$branch"' \
  'gh pr create' \
  "checksum PR creation is attempted before its recovery branch is pushed"
require_block_text "$checksum_pr_job" \
  'Allow GitHub Actions to create and approve pull requests' \
  "checksum PR failure does not name the required repository setting"
require_block_text "$checksum_pr_job" \
  'Branch $branch was pushed.' \
  "checksum PR failure does not print the pushed recovery branch"
require_block_text "$checksum_pr_job" \
  'open a pull request from $branch to $GITHUB_REF_NAME manually' \
  "checksum PR failure does not provide the manual recovery path"
require_block_text "$checksum_pr_job" \
  'exit 1' \
  "checksum PR failure is not fatal after printing recovery guidance"

require_text "$tag_verifier" \
  '"repos/$GITHUB_REPOSITORY/git/ref/tags/$tag"' \
  "live tag verifier does not resolve the current GitHub tag ref"
require_text "$tag_verifier" \
  '"repos/$GITHUB_REPOSITORY/git/tags/$live_tag_object"' \
  "live tag verifier does not peel the annotated GitHub tag object"
require_text "$tag_verifier" \
  '[[ "$ref_type" == "tag" ]]' \
  "live tag verifier accepts lightweight tags"
require_text "$tag_verifier" \
  '[[ "$live_commit" == "$expected_commit" ]]' \
  "live tag verifier does not compare the peeled commit"

require_text "$central_workflow" \
  "validate-stable-tag:" \
  "Maven Central workflow has no secret-free stable-tag preflight"
require_text "$central_workflow" \
  $'  publish:\n    needs: validate-stable-tag' \
  "Maven Central publication does not depend on stable-tag validation"
require_text "$central_workflow" \
  'scripts/release-channel.sh --require-stable "$XRAY_RELEASE_TAG"' \
  "Maven Central workflow has no stable-only release-channel guard"
require_text "$central_workflow" \
  'ref: refs/tags/${{ inputs.tag }}' \
  "Maven Central preflight does not check out the exact input tag"
require_text "$central_workflow" \
  'scripts/check-release.sh "$XRAY_RELEASE_TAG"' \
  "Maven Central preflight does not validate release locks"
require_text "$central_workflow" \
  'git merge-base --is-ancestor HEAD refs/remotes/origin/main' \
  "Maven Central preflight does not require a main-branch release commit"
require_text "$central_workflow" \
  '[[ "$tag_commit" == "$(git rev-parse HEAD)" ]]' \
  "Maven Central preflight does not re-check the annotated tag target after validation"
require_text "$central_workflow" \
  'verified_commit: ${{ steps.release.outputs.verified_commit }}' \
  "Maven Central preflight does not export the verified commit"
require_text "$central_workflow" \
  'verified_tag_object: ${{ steps.release.outputs.verified_tag_object }}' \
  "Maven Central preflight does not export the annotated tag object"
require_text "$central_workflow" \
  '[[ "$(git rev-parse HEAD)" == "$VERIFIED_COMMIT" ]]' \
  "Maven Central publication does not re-check the verified commit"
require_text "$central_workflow" \
  '.draft == false and .prerelease == false and .immutable == true' \
  "Maven Central publication does not require an immutable finalized stable release"
require_text "$central_workflow" \
  'asset_digest() {' \
  "Maven Central publication does not verify GitHub asset digests"
require_text "$central_workflow" \
  'verify_checksum_entry "$archive_name"' \
  "Maven Central publication does not bind the Maven archive to SHA256SUMS"
require_text "$central_workflow" \
  'verify_checksum_entry release-manifest.json' \
  "Maven Central publication does not bind the release manifest to SHA256SUMS"
require_text "$central_workflow" \
  '.mobileVersion == $version and .artifacts[$archive] == $archive_sha' \
  "Maven Central publication does not bind the archive to release-manifest.json"

central_preflight_job="$(extract_job "$central_workflow" validate-stable-tag)"
require_block_text "$central_preflight_job" \
  'ref: refs/tags/${{ inputs.tag }}' \
  "Maven Central preflight does not check out the exact input tag"
require_block_text "$central_preflight_job" \
  'verified_tag_object="$(git rev-parse "$tag_ref^{tag}")"' \
  "Maven Central preflight does not record the annotated tag object"

central_publish_job="$(extract_job "$central_workflow" publish)"
require_block_text "$central_publish_job" \
  'ref: ${{ needs.validate-stable-tag.outputs.verified_commit }}' \
  "Maven Central publish job does not check out the verified commit"
reject_block_text "$central_publish_job" \
  'ref: refs/tags/${{ inputs.tag }}' \
  "Maven Central publish job still checks out the mutable tag"
require_block_order "$central_publish_job" \
  'scripts/verify-github-release-tag.sh' \
  'https://central.sonatype.com/api/v1/publisher/upload' \
  "Maven Central upload is not preceded by live tag validation"

preflight_job="$(
  awk '
    /^  validate-stable-tag:/ { capture = 1 }
    /^  publish:/ { exit }
    capture { print }
  ' "$central_workflow"
)"
if grep -Eq '\$\{\{[[:space:]]*secrets\.|MAVEN_(CENTRAL|SIGNING)_' <<<"$preflight_job"; then
  die "Maven Central preflight can access publication or signing secrets"
fi

publish_job_header="$(
  awk '
    /^  publish:/ { capture = 1 }
    capture { print }
    capture && /^    steps:/ { exit }
  ' "$central_workflow"
)"
if grep -Eq 'MAVEN_(CENTRAL|SIGNING)_' <<<"$publish_job_header"; then
  die "Maven Central credentials are exposed to the whole publish job"
fi

tag_validation_steps="$(
  awk '
    /^  publish:/ { capture = 1 }
    capture && /- name: Download immutable Maven release bundle/ { exit }
    capture { print }
  ' "$central_workflow"
)"
if grep -Eq '\$\{\{[[:space:]]*secrets\.|MAVEN_(CENTRAL|SIGNING)_' <<<"$tag_validation_steps"; then
  die "tag checkout or validation can access Maven Central or signing secrets"
fi

echo "verified stable and prerelease release workflow policy"
