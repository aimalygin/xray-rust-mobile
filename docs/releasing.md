# Release process

Mobile releases are two-phase because a remote SwiftPM binary target must
contain the SHA-256 checksum of the exact ZIP stored at its tagged URL. Release
versions are either stable `MAJOR.MINOR.PATCH` or release candidates
`MAJOR.MINOR.PATCH-rc.N`, where `N` is a positive canonical integer. Build
metadata and other prerelease identifiers are not accepted.

An RC is deliberately a GitHub-only prerelease. It publishes the verified
XCFramework, standalone AAR, checksums, notices, and provenance manifest, but
never a Maven repository archive or remote Maven coordinate.

## Repository setup

Configure GitHub Actions to allow this repository to write packages and to
create pull requests. For stable versions, the release workflow publishes the
five unsigned Gradle artifacts to GitHub Packages as an authenticated mirror.
The separate Maven Central workflow signs the immutable stable release bundle
and is the public Android distribution path. Neither path accepts RC versions.
Enable immutable GitHub releases before publishing a public version. Apple
release artifacts must be built with the
Xcode version locked in `release/toolchains.env`; using another selected Xcode
is allowed only for local non-release builds and cannot produce the locked
release.

The prepare workflow artifact is retained for 30 days. The tag workflow only
publishes the exact locked Apple archive after rechecking its checksum and
structure; a separate job rebuilds the sources and tests the Apple products.

## Maven Central setup

GitHub Packages remains an authenticated mirror produced by the release
workflow. Maven Central is the public consumer target and uses a separate,
owner-approved workflow that reuses the immutable Maven bundle attached to an
existing stable release.

1. Sign in to the [Central Publisher Portal](https://central.sonatype.com/) with
   the GitHub account that owns `aimalygin`. Verify that the automatically
   provisioned namespace `io.github.aimalygin` is present.
2. Generate a Central user token and add its username and password to the
   `maven-central` GitHub environment as `MAVEN_CENTRAL_USERNAME` and
   `MAVEN_CENTRAL_PASSWORD`.
3. Add an ASCII-armored OpenPGP private key and its passphrase as
   `MAVEN_SIGNING_KEY` and `MAVEN_SIGNING_PASSWORD` in the same environment.
   Publish the corresponding primary public key to a Central-supported key
   server such as `keyserver.ubuntu.com`; do not sign with a signing subkey.
4. Protect the environment with required reviewer approval. Dispatch
   **Publish Maven Central** with an existing stable tag. A secret-free
   preflight rejects RC and malformed tags before the protected environment is
   entered. Leave `automatic`
   disabled for the first publication, inspect the validated deployment in the
   Portal, and publish it there. Later releases may use automatic publication.

The workflow removes repository-level `maven-metadata.xml`, adds the required
Javadoc artifact, regenerates checksums, signs every version artifact, uploads
the bundle through the official Central Publisher Portal API, and waits for a
validated or published state. Maven Central is immutable, so never retry a
version that has already reached `PUBLISHED`.

## Prepare

1. Choose either a stable `MAJOR.MINOR.PATCH` or an RC
   `MAJOR.MINOR.PATCH-rc.N`. Update `release/version.env`, `Package.swift`,
   Android `VERSION_NAME`, the
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
source release/version.env
version="$XRAY_MOBILE_VERSION"
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
- creates or resumes a channel-matching draft GitHub release, uploads the
  expected asset set and provenance metadata, and downloads every asset again
  for byte-for-byte comparison.

For a stable version, it also attaches the deterministic Maven repository
archive, publishes the GitHub Packages coordinate only after the draft assets
are complete, detects absent/complete/partial retry states, verifies the remote
AAR, POM, module metadata, sources JAR, and Javadoc JAR, and finally publishes
the draft as the latest stable GitHub release.

For an RC, Gradle still stages the Maven layout locally and a minified consumer
resolves it as a smoke test. Packaging then switches to standalone-only mode:
the public GitHub prerelease contains exactly the XCFramework ZIP, standalone
AAR, the raw root `LICENSE`, `THIRD_PARTY_NOTICES.md`,
`release-manifest.json`, and `SHA256SUMS`. The manifest records checksums for
both license files and `remoteMavenPublication: false`; the GitHub Packages job
is skipped, no Maven ZIP is uploaded, and finalization keeps the release marked
as a non-latest prerelease. The Maven Central workflow independently rejects
RC tags before requesting environment approval or secrets.

For a stable release, if GitHub Packages contains only part of the five-file
Maven coordinate, the workflow stops deliberately: publishing over a partial
version is unsafe. Delete that incomplete package version in the repository's
Packages settings, confirm that all five version URLs return 404, and rerun the
tag workflow. Do not delete or replace a complete coordinate.

After publication, resolve the exact SPM version from a clean sample app and
the exact Maven coordinate from a clean external Gradle consumer and record the
result. With release immutability enabled, a published release cannot be
changed; fixes use a new SDK version. Releases published by the earlier
workflow remain immutable prereleases. New `MAJOR.MINOR.PATCH` versions are
published as stable releases regardless of whether their semantic version is
below 1.0; `MAJOR.MINOR.PATCH-rc.N` versions remain prereleases.
