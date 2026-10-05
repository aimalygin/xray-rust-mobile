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

Enable **Settings → Actions → General → Workflow permissions →
Allow GitHub Actions to create and approve pull requests** for automatic
checksum-PR creation. If that setting is intentionally disabled, the Prepare
workflow fails after pushing
`release/v${version}-artifact-${GITHUB_RUN_ID}-${GITHUB_RUN_ATTEMPT}`. Open
that branch against `main` manually, verify that only `Package.swift` and
`release/artifacts.env` changed, and merge it before tagging.

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

### Candidate core source before the public tag

For stable or RC preparation, `release/core.env` may set `XRAY_RUST_REF_KIND=commit`,
leave `XRAY_RUST_TAG` and `XRAY_RUST_TAG_OBJECT` empty, and pin a clean exact
core commit/tree plus the existing file hashes. `check-release.sh --prepare`
and source builds/tests accept that explicit candidate mode. There is no
branch-based or dirty-source release fallback.

Canonical Apple preparation, generated/strict release validation and publication
require `XRAY_RUST_REF_KIND=tag` (the default for old locks) and the matching
annotated core release tag. After the core passes CI and exact-candidate device
evidence and publishes its matching release tag, replace the candidate lock with the
verified tag object and release commit/tree before preparing Apple artifacts.
Do not create an early public core tag simply to satisfy the mobile lock.

The version selector chooses `v08-release-evidence.yml` for 0.8,
`v07-release-evidence.yml` for 0.7 and the existing v0.6 workflow for 0.6.
Each binds to the locked core repository, commit/tree and an unexpired
successful evidence artifact. v0.8 requires schema-4 evidence for Trojan,
Shadowsocks 2022 and VMess on Apple and both Android paths, including the
required import, network/lifecycle, resource and performance checks. See the
[v0.8 release readiness checklist](https://github.com/aimalygin/xray-rust/blob/codex/v08-client-protocols/docs/v08-release-readiness.md).
The current development pin is not accepted release evidence, and the 0.7
exceptions do not carry over. v0.7 requires fresh
Apple/Android protocol lifecycle coverage, including FileDescriptor and PacketPump.
Candidate source checks and old device reports do not establish release acceptance.

The [2026-10-03 iPhone candidate report](https://github.com/aimalygin/xray-rust/blob/codex/v08-client-protocols/docs/device-results/2026-10-03-iphone17-v08/README.md)
uses core `de339981` and SDK `0148543`: LAN protocol/cipher checks and bounded
Trojan/VMess WAN transitions passed. SS2022 WAN passed only with an explicit
diagnostic fragmentation relay after the original path failed on IPv6 UDP;
Go controls reproduced the size/DF-dependent loss. The report preserves that
condition and all failures. It does not close the full Apple/Android or schema-4
gate, and neither the development core pin nor artifact locks changed.

The [2026-10-04 iPhone follow-up](https://github.com/aimalygin/xray-rust/blob/codex/v08-client-protocols/docs/device-results/2026-10-04-iphone17-lifecycle-resources/README.md)
adds startup cancellation, rapid restart, bounded extension CPU/memory and
legacy controls on iOS 27.0.1. It uses the same release Rust library and vendored
SDK sources, plus DEBUG-only reference-app instrumentation. The original Trojan
timeout and two intermittent WireGuard failures are retained alongside passing
controls; these observations do not close clean legacy/performance acceptance.
The runtime pin, source snapshots and artifact locks are unchanged.

The [same-device 0.7/0.8 WireGuard comparison](https://github.com/aimalygin/xray-rust/blob/codex/v08-client-protocols/docs/device-results/2026-10-04-iphone17-wg-baseline/README.md)
passed three alternating invocations per version and three further Trojan
lifecycle invocations. Earlier failures did not recur under diagnostics, but
their causes remain unresolved. The CI relay accounting fix changes only a
Rust test; neither these results nor that fix require a native runtime repin.

The [direct SS2022 UDP/MTU investigation](https://github.com/aimalygin/xray-rust/blob/753acd1b2ec018a97a167a5ce2c057bd078ce287/docs/device-results/2026-10-04-iphone17-ss2022-mtu/README.md)
reproduces the loss in Go and on iPhone and localizes the detailed boundary
failure to the return path after DF replies leave the server. Changing only
the temporary native Xray UDP socket to permit fragmentation passes 56/56
Go boundary trials, 40/40 iPhone size trials and direct Wi-Fi/cellular/Wi-Fi
plus lock/wake, without a relay. A persistent production-path configuration
and the exact dropping hop remain unvalidated. This adds DEBUG reference-app
instrumentation and evidence only; the runtime pin, canonical source snapshots
and artifact locks remain unchanged. Failed default controls remain recorded.

The [ordered reliability/deployment follow-up](https://github.com/aimalygin/xray-rust/blob/7aaf9a5bd07d174145aaf004530402483bf0b57f/docs/device-results/2026-10-04-iphone17-reliability-deployment/README.md)
passes five further WireGuard smoke and five Trojan lifecycle invocations, with
210 TCP / 140 UDP echoes matched at the backend. Earlier failure causes remain
unresolved. An optional server-only SS2022 startup hook reapplies the socket
policy on five starts including two restarts, without a resident helper. WAN
controls cover all three ciphers but retain failed trials: ChaCha Go 40/44,
AES-128 iPhone 38/40, and a later AES-128 Go 43/44 including a lost unfragmented
reply. AES-256 Go 44/44 and iPhone 40/40 pass; ordinary AES-128 iPhone smoke also
passes. This validates restart persistence, not universal WAN reliability or
production deployment. No native/SDK source, core pin or artifact lock changes
are required; full device and schema-4 acceptance remain open.

On 2026-10-04 the owner deferred further SS2022 UDP-loss investigation and
directed work to continue with other acceptance. Preserve the failures and path
conditions as known limitations. The [evidence assembly inventory](https://github.com/aimalygin/xray-rust/blob/1388c613971c8785f22107e2fac6be85f956e388/docs/v08-release-evidence.md)
lists remaining physical Android, Apple shared-scenario and calibrated sample
work. No validator exception, native repin or release authorization is implied.
Before the regression-report changes, ordinary CI passed core `3c7b162`
([run](https://github.com/aimalygin/xray-rust/actions/runs/37253541471)) and SDK
`90355c5` ([run](https://github.com/aimalygin/xray-rust-mobile/actions/runs/37253545430));
these source checks are separate from device/release qualification.

The Android PacketPump follow-up advances the development source pin to
`0d788564d85505ba0e2778320a561bc3d6500346` (tree
`f71235a8b17a5e5e88809ada36ce4efc19f29b00`) and synchronizes `XrayVpnService`.
An empty nonblocking TUN read now waits for readiness with a bounded `Os.poll`
instead of spinning. Packet buffers and the public API are unchanged. Earlier
Android/iPhone measurements retain native revision `de339981`; the Android
follow-up uses that exact native/JNI binary with a separately hashed updated
Kotlin adapter. These observations are not an exact-new-pin release manifest.
Reassess candidate evidence after the adapter change; artifact locks remain
unprepared and no publication is authorized.

The [Samsung Android report](https://github.com/aimalygin/xray-rust/blob/1388c613971c8785f22107e2fac6be85f956e388/docs/device-results/2026-10-04-android-v08/README.md)
retains both baseline and corrected-adapter runs. Each functional matrix passes
14/14 combinations, with 182 HTTP and 182 nonce-checked UDP checks. The
follow-up records 5,760/5,760 stress HTTP and 11,518/11,520 UDP attempts, with
all twelve bounded RSS/thread criteria passing. Maximum recovery-median RSS
growth is 7.61 MiB and no thread count grows. PacketPump recovery CPU is about
2.6–3.1% of one core after the readiness fix, versus about 101% before.
SS2022 AES-128/AES-256 PP timeouts remain unexplained; fixing idle CPU does not
resolve these packet losses. All original failures and exact native/APK hashes
remain published, along with replay scripts and verified cleanup. Android
network/lock checks are owner-skipped for v0.8 on both paths, per the
2026-10-04 instruction “для android пропускаем”. They are recorded as **not
tested**; only those two Android transition requirements are excluded from the
v0.8 policy. Apple requirements and measured UDP failures remain unchanged.
The [Android legacy and active-flow report](https://github.com/aimalygin/xray-rust/blob/1388c613971c8785f22107e2fac6be85f956e388/docs/device-results/2026-10-04-android-regressions/README.md)
adds physical VLESS/REALITY, XHTTP H1/H2/H3, WireGuard and Hysteria2 checks,
plus TCP/UDP cancellation for every new cipher on both TUN paths. Ordinary
primary traffic records 255 HTTP passes and 254 UDP passes with one UDP timeout.
The strict primary matrix completes 18/26 TCP and 25/26 UDP cases: WireGuard
whole-VPN stop intermittently misses remote EOF, while SS2022 retains the
server-side request for all three ciphers, reproduced by pinned Go-client to
Go-server controls. All twelve supplemental SS2022 local cancellation/recovery
controls pass. One Trojan PacketPump UDP recovery fails; four fresh-fixture
repeats pass without explaining the original failure. Preserve these findings,
all raw attempts, controller corrections and cleanup. The same installed APKs
and native/adapter identities were verified; no runtime or SDK pin change was
made for this follow-up. Review the findings, complete the remaining shared
scenarios and calibrated samples, and assemble schema-4 evidence before
claiming full qualification.


For direct stable 0.7.0, the core validator accepts its checksum-pinned measured
archive only with the reviewed metadata-only promotion and explicit owner
decisions: Android cellular was not tested, and the investigated WireGuard
timeout case is accepted for this release. Measured identities and failures remain
in the archive; runtime, ABI, dependencies and build inputs cannot change.

1. Choose either a stable `MAJOR.MINOR.PATCH` or an RC
   `MAJOR.MINOR.PATCH-rc.N`. Update `release/version.env`, `Package.swift`,
   Android `VERSION_NAME`, the
   unprepared artifact name in `release/artifacts.env`, the core lock if needed, adapter
   snapshots, and `CHANGELOG.md` on `main`.
2. For a version whose Apple archive is not prepared yet, set both the
   `Package.swift` checksum and `APPLE_XCFRAMEWORK_SHA256` to 64 zeroes, set
   `APPLE_ARTIFACT_RUN_ID=0`, and use
   `APPLE_ARTIFACT_NAME=apple-release-v<version>-unprepared`. Set
   `APPLE_ARTIFACT_SOURCE_COMMIT` and `APPLE_ARTIFACT_SOURCE_TREE` to 40
   zeroes. The prepare workflow replaces them with the exact source revision
   and tree used to build the Apple archive.
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
  hashes, adapter snapshots, and the Apple producer job/source commit/tree;
- requires the successful, non-expired versioned `v0.6 release evidence` or
  `v0.7 release evidence` run and retained artifact for that exact locked core
  commit and tree. For stable `0.6.0`, the core workflow validates the original
  RC archive plus the stable promotion source delta; it preserves the measured
  RC identity and does not claim a new physical-device run. Long device soak
  campaigns are excluded from the current release checklist by owner decision;
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
