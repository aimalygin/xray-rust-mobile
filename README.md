# xray-rust-mobile

[![Maven Central](https://img.shields.io/maven-central/v/io.github.aimalygin/xray-rust-mobile.svg?label=Maven%20Central)](https://central.sonatype.com/artifact/io.github.aimalygin/xray-rust-mobile)

Project website: [xray-rust.aimalygin.chatgpt.site](https://xray-rust.aimalygin.chatgpt.site)

SDK **0.8.1** includes the Apple startup-probe ordering fix, updated core
dependencies and C ABI 1.12. Trojan, Shadowsocks 2022, VMess AEAD, Hysteria2 and
WireGuard are supported; Shadowsocks AEAD-2017 and legacy VMess remain excluded.
See [GitHub Releases](https://github.com/aimalygin/xray-rust-mobile/releases)
for downloadable artifacts and publication status, and [the changelog](CHANGELOG.md#081---2026-10-18)
for the release scope. The [core 0.8.1 evidence and limitations](https://github.com/aimalygin/xray-rust/releases/tag/v0.8.1)
retain the conditional SS2022 WAN PMTU result, remote EOF limitation and
unconfirmed 5% latency non-regression bound accepted for this release.

The development branch tracks **Unreleased** changes against reviewed core
[`15e8b205`](https://github.com/aimalygin/xray-rust/commit/15e8b205a0101a0eb0b23913ae994370ce8683b9),
whose [post-merge CI passed](https://github.com/aimalygin/xray-rust/actions/runs/40233590914).
This source synchronization leaves the last released version fields at 0.8.1;
local builds of this checkout are development snapshots, not the published
0.8.1 artifacts. The commit pin and unprepared artifact locks block publication.
Use the installation examples below for published 0.8.1 packages. For source
development, build the native artifacts locally before resolving the Swift
package; see [Unreleased changes](CHANGELOG.md#unreleased). A future release
version and acceptance scope will be chosen separately.

Native iOS, tvOS, macOS, and Android SDK packages for
[`xray-rust`](https://github.com/aimalygin/xray-rust). The repository provides
ready-to-integrate binaries, Swift and Kotlin APIs, and native tunnel adapters
for host applications.

Each stable release pins one reviewed core commit and publishes:

- `XrayRust.xcframework.zip` for Swift Package Manager;
- `io.github.aimalygin:xray-rust-mobile` as an Android AAR/Maven module;
- matching checksums and a release manifest.

Release candidates use `MAJOR.MINOR.PATCH-rc.N` tags and are GitHub
prereleases. They contain the verified XCFramework, standalone AAR,
the raw project `LICENSE`, third-party notices, checksums, and manifest, but
are never published to GitHub Packages or Maven Central.

An Apple Packet Tunnel extension can use the provided implementation directly:

~~~swift
import XrayAppleTunnel

final class PacketTunnelProvider: XrayPacketTunnelProvider {}
~~~

The underlying core measured 4.2 MiB idle resident memory and 20.9 MiB with
1,000 held SOCKS flows in the latest published synthetic localhost benchmark.
See the [full results and methodology](https://github.com/aimalygin/xray-rust/blob/main/docs/benchmarks/results/2026-08-31-v26.7.28/README.md).

This project is unofficial and is not affiliated with XTLS or Xray-core.

## Version mapping

| Mobile SDK | xray-rust | Core commit | C ABI |
| --- | --- | --- | --- |
| Unreleased source snapshot | commit pin; core reports `0.8.1` | `15e8b205a0101a0eb0b23913ae994370ce8683b9` | `1.12` |
| `0.8.1` | `v0.8.1` | `5b61eee201fac8639cb1dac0349e34af65db90f7` | `1.12` |
| `0.8.0` | `v0.8.0` | `fcce4be2771c1fb3f11e9503741d39a4d8df314e` | `1.11` |
| `0.7.0` | `v0.7.0` | `67969094b352f948c6b8b9e2ac75402c577cb7f7` | `1.7` |
| `0.6.1` | `v0.6.1-rc.1` | `1231add417a4e2e6aa4c9e51c13487d493498a1d` | `1` |
| `0.6.0` | `v0.6.0` | `8fd695d3da7ae98051b55b598aa7a16c8ecb1db5` | `1` |
| `0.6.0-rc.1` (candidate) | `v0.6.0-rc.1` | `1e713ca3e6c57be5747b4915b31e0db040a01c0c` | `1` |
| `0.5.0` | `v0.5.0` | `549807d621fadc618e6d0bab75f9e58ef35a7fc1` | `1` |
| `0.4.0` | `v0.4.0` | `e1199b2176ae834259e8a2b21db468bb9db5fb17` | `1` |
| `0.3.2` | `v0.3.2` | `850813037cd5c018348ec08b44b0b926414e17e8` | `1` |
| `0.3.1` | `v0.3.1` | `9dba6c222ce24d347fc97fbedfedadaeb16a512c` | `1` |
| `0.3.0` | `v0.3.0` | `774e08d0a22a2ff30a2ade38b9d616efe43661e7` | `1` |
| `0.2.0` | `v0.2.0` | `536d2640fe0fc2df87b61b128b21d3886d72951d` | `1` |
| `0.1.7` | `v0.1.1` | `ae14066eedca532e247503a19481263a437011c4` | `1` |
| `0.1.6` | `v0.1.1` | `ae14066eedca532e247503a19481263a437011c4` | `1` |
| `0.1.5` | `v0.1.1` | `ae14066eedca532e247503a19481263a437011c4` | `1` |
| `0.1.4` | `v0.1.1` | `ae14066eedca532e247503a19481263a437011c4` | `1` |
| `0.1.3` | `v0.1.1` | `ae14066eedca532e247503a19481263a437011c4` | `1` |
| `0.1.2` | `v0.1.1` | `ae14066eedca532e247503a19481263a437011c4` | `1` |
| `0.1.1` | `v0.1.1` | `ae14066eedca532e247503a19481263a437011c4` | `1` |
| `0.1.0` | `v0.1.0` | `e4daf171c6c44730312d4e35294b25e60691291f` | `1` |

For releases that change the core or its adapters, the Mobile SDK version stays
aligned with the pinned `xray-rust` tag. A packaging-only Swift or Kotlin
respin may advance independently without inventing a new Rust core version.
The complete trust anchor is in [`release/core.env`](release/core.env).

## Development synchronization after 0.8.1

The development snapshot includes Android's unmetered VPN setting, cached FFI metadata,
checked native statistics and wrapper cleanup from core #82/#88. SOCKS inbound
authenticates the TCP control connection; password-protected UDP associations
require a declared nonzero client port and enforce that source endpoint. UDP
datagrams carry no credentials. Association cleanup is also included in core.
SOCKS outbound supports TCP CONNECT and UDP ASSOCIATE over raw TCP or TLS
control connections; relay UDP datagrams remain plain. Its server domain is
bootstrapped before tunnel startup and Apple excludes the resolved carrier IPs
from tunnel routes. Destination-domain resolution remains with the SOCKS proxy.
HTTP outbound, SOCKS share-link import and UDP proxy chaining are outside this
scope. See the [pinned compatibility policy](https://github.com/aimalygin/xray-rust/blob/15e8b205a0101a0eb0b23913ae994370ce8683b9/docs/xray-core-differences.md)
for supported behavior and deliberate differences from Xray-core.

Android network-change coordination is tracked separately in [core #89](https://github.com/aimalygin/xray-rust/issues/89). The host still
owns network observation and uses the existing Hysteria2/WireGuard rebind APIs;
this snapshot does not add automatic migration or change borrowed-FD ownership.
The SDK's packaging toolchain remains independently pinned. Development CI checks
source/package integration, not new physical-device or performance acceptance.

## New APIs in 0.8.1

The Apple provider performs cancellable startup-probe preflight after DNS
bootstrap and before installing tunnel network settings. With a startup probe
enabled, the native library must expose ABI 1.12's `STARTUP_PROBE_PREFLIGHT`
capability. Probe failure, timeout or cancellation leaves network settings
untouched. The provider disables the already-completed probe on its data-path
core. Custom integrations can use `XrayCore.preflightStartupProbe()` on a loaded,
unstarted core; ordinary `start()` retains its existing startup-probe behavior.

Both adapters expose Hysteria2/WireGuard rebind, outbound URL probes,
`XrayHysteriaStreamLimits` and `XrayTunAdmissionOptions` through `XrayCore`.
Supply limits and admission when creating the core, before loading its config.
The default Hysteria2 limits remain 64 TCP streams and 32 UDP sessions per QUIC
session; explicit limits accept 1–256 and 1–128 respectively. Rebind returns the
number of accepted/coalesced requests, not a network-change completion signal.
The Android host owns its network-change observer.

TUN admission is opt-in and runs once per flow on bounded native workers, off
the packet loop. Callbacks must return promptly and must not call core lifecycle
methods. Timeout (1–5000 ms) bounds the decision, not callback execution. Keep
policy state safe for concurrent callbacks. With admission disabled there are
no per-packet host callbacks. Kotlin's `XrayAndroidUidAdmission` requires Android
10+ and an active VPN; unknown owners and lookup errors deny by default. Keep
`VpnService.Builder` app rules as well. Override `XrayVpnService.tunAdmissionOptions()`
to register this policy after VPN establishment. Some devices report an unknown
UID even for permitted, explicitly bound TCP sockets; test that case before
opting into strict UID enforcement.

The supplied `XrayPacketTunnelProvider` exposes both options through overridable
`hysteriaStreamLimits()` and `tunAdmissionOptions()` methods:

```swift
import XrayAppleTunnel
import XrayMobileAdapter

final class PacketTunnelProvider: XrayPacketTunnelProvider {
    override func hysteriaStreamLimits() throws -> XrayHysteriaStreamLimits? {
        try .init(maxTcpStreams: 128, maxUdpSessions: 64)
    }

    override func tunAdmissionOptions() throws -> XrayTunAdmissionOptions? {
        try .init(timeoutMilliseconds: 100, failOpen: false) { flow in
            // Example policy: allow only IPv4 destinations. Replace with host policy.
            flow.addressFamily == 4
        }
    }
}
```

These hooks run once per configured start, before DNS bootstrap and network
settings; a thrown error fails startup. Their settings remain fixed until restart
and apply to both direct utun fd and packetFlow backends. Default implementations
return `nil`, preserving the core's 64/32 limits and disabled admission path.
Admission callbacks may run concurrently and finish after tunnel shutdown: avoid
retaining the provider or calling lifecycle methods from a callback. Explicit
denial remains denied with `failOpen: true`; queue/buffer exhaustion also drops.
These are typed host policies, not additional Xray JSON/provider dictionary keys.
Apple does not provide the Android UID lookup helper.

Salamander, UDP port hopping, first-ClientHello fragmentation and UDP noise use the pinned
core's JSON configuration. Hysteria2 profile import also preserves
`obfs=salamander`, `obfs-password` and `mport`. Fragmentation supports the core's
bounded TCP TLS/REALITY/Vision configurations; it does not apply to QUIC or
arbitrary UDP. UDP noise uses bounded `finalmask.udp` settings on Hysteria2 and
XHTTP with exact `alpn: ["h3"]`, including mask ordering with Salamander. Legacy
freedom `settings.noises` is unsupported. Linux TPROXY is a desktop/server
inbound; Apple/Android applications continue using the TUN adapters.
These features stay disabled unless configured. Probe calls are
blocking; call them off the main thread. Capability/version checks guard the
optional host APIs; distribute the matched native library and adapters together.

The pin includes [core compatibility and performance evidence](https://github.com/aimalygin/xray-rust/blob/ee55398d436f22c1fd2b5d2ed3bc467cc03d8b0b/docs/benchmarks/results/2026-10-10-pr42-issues/README.md),
including pinned Xray-core and native Hysteria interoperability. SDK sync keeps
the canonical adapters byte-for-byte and retains release build profiles and
dependency locks. Host measurements are not a new physical-device acceptance
campaign; the report retains unexplained UDP timeouts and existing release
gates. No artifacts are published by updating this development pin.

## Apple platforms with Swift Package Manager

Add the package:

~~~swift
dependencies: [
    .package(
        url: "https://github.com/aimalygin/xray-rust-mobile.git",
        exact: "0.8.1"
    ),
]
~~~

Then add the product needed by the target:

~~~swift
.product(
    name: "XrayMobileAdapter",
    package: "xray-rust-mobile"
)
~~~

Available products:

- `XrayMobileAdapter` — lifecycle, packet I/O, direct `utun` fd support,
  statistics, diagnostic events, and the `NEPacketTunnelFlow` pump;
- `XrayAppleShared` — profiles, Keychain-backed config storage, VLESS URL
  import (including XHTTP over plaintext, TLS, and REALITY), logging, and DNS
  preflight;
- `XrayAppleTunnel` — a ready-to-subclass `NEPacketTunnelProvider`.

Minimum supported versions are iOS 15, tvOS 17, and macOS 11. The binary
contains `arm64` device slices and `arm64` plus `x86_64` simulator slices for
iOS and tvOS, plus a universal `arm64`/`x86_64` macOS slice.
`XrayAppleTunnel` APIs that depend on newer Network Extension functionality
require macOS 13.

`XrayRust.xcframework` deliberately ships bare `libxray_ffi.a` slices and no
headers. Xcode copies the headers of a static-library XCFramework into a flat
per-configuration `include` directory, and the `module.modulemap` name there is
fixed, so an app that also links another static-library XCFramework — a second
Xray core, for instance — fails to build with "Multiple commands produce
.../include/module.modulemap". The public C API is published from the
`XrayRustFFI` target of this package instead, which vendors `xray_ffi.h` and
its module map verbatim from the pinned core. `import XrayRust` is unaffected.
The practical consequence is that the XCFramework must be consumed through
Swift Package Manager: dropping it straight into an Xcode project provides the
library but no declared module, so copy the two files from
[`Sources/XrayRustFFI/include`](Sources/XrayRustFFI/include) alongside it.

Low-level lifecycle:

~~~swift
import XrayMobileAdapter

let core = try XrayCore(configJSON: configJSON)
try core.start()
defer { try? core.stop() }
~~~

For a packet-tunnel extension, the higher-level entry point is:

~~~swift
import XrayAppleTunnel

final class PacketTunnelProvider: XrayPacketTunnelProvider {}
~~~

Store the JSON in Keychain and put only its opaque reference in the provider
configuration:

~~~swift
import XrayAppleShared

let reference = XraySecureConfigReference.tunnel(profileID)
try XrayKeychainConfigStore().store(
    configJSON: configJSON,
    reference: reference
)
providerConfiguration[
    XrayTunnelProviderMessage.providerConfigReferenceKey
] = reference
~~~

`XrayKeychainConfigStore` writes to the target's default Keychain access group.
In both the host app and packet-tunnel extension, enable Keychain Sharing and
make the same shared group the first entry in `keychain-access-groups`:

~~~xml
<key>keychain-access-groups</key>
<array>
    <string>$(AppIdentifierPrefix)com.example.xray.shared</string>
</array>
~~~

The order matters: when no explicit access group is supplied, Apple uses the
first Keychain access group as the default. The host app still owns signing,
Network Extension entitlements, the provider bundle identifier, and VPN
consent. Never place the raw configuration JSON in `providerConfiguration` or
start options.

### Shared App Group geodata

Hosts that download or share `geosite.dat` and `geoip.dat` should give the
containing app and Packet Tunnel extension the same App Group entitlement:

~~~xml
<key>com.apple.security.application-groups</key>
<array>
    <string>group.com.example.xray</string>
</array>
~~~

Publish each checksum-verified generation into its own directory, for example:

~~~text
Library/Application Support/XrayGeodata/<version>-<sha256>/
  geosite.dat
  geoip.dat
~~~

Select that exact generation in the provider configuration:

~~~swift
providerConfiguration[
    XrayTunnelProviderMessage.providerGeodataAppGroupIdentifierKey
] = "group.com.example.xray"
providerConfiguration[
    XrayTunnelProviderMessage.providerGeodataRelativeDirectoryKey
] = "Library/Application Support/XrayGeodata/<version>-<sha256>"
~~~

Both values are required together. The relative directory must already exist
inside the App Group and every component must be a real directory rather than
a symbolic link. Empty, `.` and `..` path components are rejected. With both
keys absent, the Packet Tunnel keeps the existing `Bundle.main.resourceURL`
fallback. With both keys present, the selected generation is exclusive: a
referenced asset missing from it fails preflight instead of being loaded from
the process-default search directories.

Download into a sibling staging directory, verify checksums, then atomically
rename the completed directory to its final generation name. Published
generations are immutable: do not replace their files or use a mutable
`current` symlink, and retain the selected generation until the tunnel has
stopped and no saved provider configuration refers to it.

The App Group is a trusted cooperation boundary. The adapter validates the
selected path when the tunnel starts, but it does not hold directory file
descriptors or defend against another App Group writer replacing a published
generation concurrently. It does not download or verify geodata on the host's
behalf.

## Android with Gradle

Stable Android SDK versions are published to Maven Central and do not require
GitHub credentials. RC builds are available only as standalone AAR assets on
their GitHub prereleases.

In `settings.gradle.kts`:

~~~kotlin
dependencyResolutionManagement {
    repositories {
        google()
        mavenCentral()
    }
}
~~~

In the app module's `build.gradle.kts`:

~~~kotlin
dependencies {
    implementation("io.github.aimalygin:xray-rust-mobile:0.8.1")
}
~~~

The published coordinate, POM, signatures, sources, and API documentation are
listed on [Maven Central](https://central.sonatype.com/artifact/io.github.aimalygin/xray-rust-mobile/0.8.1).

Hosts that expose an explicit debug-logging preference can enable the core's
sanitized access and error logs by creating a private directory before loading
the configuration:

~~~kotlin
val logDirectory = File(context.filesDir, "xray-logs").apply { mkdirs() }
val core = XrayCore.create(
    configJson = configJson,
    vpnService = vpnService,
    fileLoggingDirectory = logDirectory,
)
~~~

Omit `fileLoggingDirectory` during normal operation. The core never enables
file logging by itself, and the host remains responsible for bounding and
exporting the generated `xray-access.log` and `xray-error.log` files.

Every GitHub release also contains the standalone AAR for consumers that need
to inspect or integrate the release artifact directly.

The AAR supports API 24+ and contains `arm64-v8a`, `armeabi-v7a`, `x86`, and
`x86_64`, with 16 KiB page-aligned native libraries. It merges the
`INTERNET` and `FOREGROUND_SERVICE` permissions. The library deliberately does
not register its base `XrayVpnService` or choose a target-SDK-specific service
type: the host must subclass it, register that concrete service, and declare
the matching permission.

~~~kotlin
class AppVpnService : XrayVpnService() {
    fun connect(configJson: String) {
        startXrayTunnel(
            configJson = configJson,
            tunRuntimeProfile = XrayTunRuntimeProfile.Mobile,
        )
    }

    override fun onXrayTunnelStartFailed(error: Throwable) {
        // Report a sanitized failure to the host app.
    }
}
~~~

Register the subclass in the host app manifest. Android 14+ requires both the
foreground-service type and its matching permission for an active VPN:

~~~xml
<manifest xmlns:android="http://schemas.android.com/apk/res/android">
    <uses-permission android:name="android.permission.FOREGROUND_SERVICE" />
    <uses-permission
        android:name="android.permission.FOREGROUND_SERVICE_SYSTEM_EXEMPTED" />

    <application>
        <service
            android:name=".AppVpnService"
            android:exported="false"
            android:foregroundServiceType="systemExempted"
            android:permission="android.permission.BIND_VPN_SERVICE">
            <intent-filter>
                <action android:name="android.net.VpnService" />
            </intent-filter>
        </service>
    </application>
</manifest>
~~~

The host app remains responsible for `VpnService.prepare`, a foreground
notification/channel, target-SDK-specific foreground service policy, lifecycle
commands, and user-visible error handling. Call `startForeground` promptly;
Android permits `systemExempted` only while the app is configured as an active
VPN, otherwise startup can fail with `ForegroundServiceTypeNotAllowedException`.

## v0.8 candidate profile imports

The candidate adds `XrayProfileFormat.trojan`, `.shadowsocks2022` and `.vmess`
in Swift, and `Trojan`, `Shadowsocks2022` and `Vmess` in Kotlin. Call
`XrayProfileImporter.profile` with the selected format and store the resulting
config in the host's secure profile store. Check `supportsProfileImport` on the
linked core's FFI information before offering a format to the user.

Trojan accepts `trojan://`; Shadowsocks 2022 accepts SIP002 `ss://` with the
three `2022-blake3-*` methods; VMess accepts AEAD profiles with zero/absent
`alterId`. Unknown or excluded methods fail import. The importer works offline;
loading a profile does not start a VPN. See the core's
[compatibility contract](https://github.com/aimalygin/xray-rust/blob/codex/v08-client-protocols/docs/config-compatibility.md)
for transport combinations, resource limits and SS2022 reconnect behavior.

## Build locally

The scripts prefer a clean sibling checkout at `../xray-rust`; otherwise they
clone the exact commit from `release/core.env` into `.build/core`.

Apple requires Xcode 16.4. `scripts/build-apple.sh` rejects another selected
Xcode for release reproducibility. To allow a different Xcode for a local
non-release build, set `XRAY_ALLOW_UNPINNED_XCODE=1`.

Apple:

~~~sh
source release/toolchains.env
rustup toolchain install "$RUST_TOOLCHAIN" --profile minimal \
  --component llvm-tools
rustup toolchain install "$TVOS_RUST_TOOLCHAIN" --profile minimal \
  --component rust-src
rustup target add --toolchain "$RUST_TOOLCHAIN" \
  aarch64-apple-darwin \
  x86_64-apple-darwin \
  aarch64-apple-ios \
  aarch64-apple-ios-sim \
  x86_64-apple-ios
scripts/build-apple.sh
scripts/check-apple-link.sh
scripts/package-apple.sh
~~~

Android requires JDK 17, Android SDK 35, NDK `26.3.11579264`, and CMake
`3.22.1`:

~~~sh
source release/toolchains.env
rustup toolchain install "$RUST_TOOLCHAIN" --profile minimal
rustup target add --toolchain "$RUST_TOOLCHAIN" \
  aarch64-linux-android \
  armv7-linux-androideabi \
  i686-linux-android \
  x86_64-linux-android
scripts/build-android.sh
scripts/package-android.sh
~~~

For an RC preflight, `scripts/package-android.sh --standalone-only` keeps the
locally staged Maven repository available for consumer smoke tests while
omitting the Maven archive from the distribution.

Generated native artifacts live under ignored `Artifacts/`, `.build/`, and
`dist/` directories. They are never committed to Git.

## Updating the pinned core

1. Review and update `release/core.env`, including the tag object, commit,
   tree, `Cargo.lock`, header, and module-map hashes.
2. Run `scripts/sync-upstream.sh --force` after reviewing that it will replace
   the local adapter snapshots.
3. Update `release/version.env`, `Package.swift`, Android
   `VERSION_NAME`, and `CHANGELOG.md`.
4. Run `scripts/check-release.sh --prepare` until the canonical Apple artifact
   is locked, then run strict `scripts/check-release.sh`.
5. Build both platforms and complete the two-phase release described in
   [`docs/releasing.md`](docs/releasing.md).

Do not make `xray-ffi` a Cargo dependency of another workspace. It must be
built from the pinned `xray-rust` workspace root so its locked path
dependencies and root `[patch.crates-io]` remain effective.

## License

Source in this repository is licensed under the
[Mozilla Public License 2.0](LICENSE). Binary releases retain the exact core
source commit and third-party notices needed to identify corresponding source;
see [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).
