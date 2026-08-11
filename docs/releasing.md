# Release process

Mobile releases are two-phase because a remote SwiftPM binary target must
contain the SHA-256 checksum of the exact ZIP stored at its tagged URL.

## Repository setup

Before the first release, configure GitHub Actions to allow this repository to
write packages and to create pull requests. The GitHub Packages workflow
intentionally publishes the four unsigned Gradle artifacts; the Gradle project
retains optional `MAVEN_SIGNING_KEY`/`MAVEN_SIGNING_PASSWORD` support for a
future Maven Central publication. Enable immutable GitHub releases before
publishing a public version. Apple release artifacts must be built with the
Xcode version locked in `release/toolchains.env`; using another selected Xcode
is allowed only for local experiments and cannot produce the locked release.

The prepare workflow artifact is retained for 30 days. The tag workflow only
publishes the exact locked Apple archive after rechecking its checksum and
structure; a separate job rebuilds the sources and tests the Apple products.

## Prepare

1. Update `release/version.env`, `Package.swift`, Android `VERSION_NAME`, the
   unprepared artifact name in `release/artifacts.env`, the core lock if needed, adapter
   snapshots, and `CHANGELOG.md` on `main`.
2. For a version whose Apple archive is not prepared yet, set both the
   `Package.swift` checksum and `APPLE_XCFRAMEWORK_SHA256` to 64 zeroes, set
   `APPLE_ARTIFACT_RUN_ID=0`, and use
   `APPLE_ARTIFACT_NAME=apple-release-v<version>-unprepared`.
3. Run `scripts/check-release.sh --prepare`.
4. Optionally run `scripts/prepare-release.sh <version>` on a provisioned macOS
   host. This is a local reproducibility preflight only; it does not update or
   commit release locks.
5. Push the metadata changes to `main`, then dispatch **Prepare release** for
   the exact version. The workflow builds the canonical Apple ZIP with iOS,
   tvOS, and macOS slices and opens a PR that updates both `Package.swift` and
   `release/artifacts.env`.
6. Review and merge that checksum PR. Run strict `scripts/check-release.sh` on
   the merged commit.

Never create a public tag with a placeholder checksum, move a published tag,
or replace an asset under an existing release URL.

## Publish

Create and push an annotated tag only after the generated lock PR is merged:

~~~sh
version=0.3.0
git tag -a "v${version}" -m "xray-rust-mobile v${version}"
git push origin "v${version}"
~~~

The tag workflow:

- verifies the annotated tag, mobile version, exact core tag/commit/tree/file
  hashes, and adapter snapshots;
- rebuilds the Swift test XCFramework and runs all Swift tests;
- verifies the locked iOS, tvOS, and macOS SwiftPM ZIP and requires its
  checksum to match the prepared lock;
- builds/tests the release AAR, checks JNI dependencies and 16 KiB alignment,
  and compiles a minified application consumer from the staged Maven module;
- creates or resumes a draft GitHub release, uploads all binary assets and
  provenance metadata, and downloads them again for byte-for-byte comparison;
- publishes the Maven coordinate only after the draft assets are complete,
  detecting absent, complete, or partially published retry states;
- verifies the remote Maven AAR, POM, module metadata, and sources JAR, then
  promotes the draft to a prerelease.

If GitHub Packages contains only part of the four-file Maven coordinate, the
workflow stops deliberately: publishing over a partial version is unsafe.
Delete that incomplete package version in the repository's Packages settings,
confirm that all four version URLs return 404, and rerun the tag workflow. Do
not delete or replace a complete coordinate.

After publication, resolve the exact SPM version from a clean sample app and
the exact Maven coordinate from a clean external Gradle consumer and record the
result. With release immutability enabled, a published prerelease cannot be
converted into a stable release; decide that status before publishing. This
workflow intentionally publishes pre-1.0 versions as prereleases. Fixes use a
new SDK version.
