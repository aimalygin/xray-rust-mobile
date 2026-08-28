# xray-rust-mobile

[![Maven Central](https://img.shields.io/maven-central/v/io.github.aimalygin/xray-rust-mobile.svg?label=Maven%20Central)](https://central.sonatype.com/artifact/io.github.aimalygin/xray-rust-mobile)

Project website: [xray-rust.aimalygin.chatgpt.site](https://xray-rust.aimalygin.chatgpt.site)

Native iOS, tvOS, macOS, and Android SDK packages for
[`xray-rust`](https://github.com/aimalygin/xray-rust). The repository provides
ready-to-integrate binaries, Swift and Kotlin APIs, and native tunnel adapters
for host applications.

Each release pins one reviewed core commit and publishes:

- `XrayRust.xcframework.zip` for Swift Package Manager;
- `io.github.aimalygin:xray-rust-mobile` as an Android AAR/Maven module;
- matching checksums and a release manifest.

An Apple Packet Tunnel extension can use the provided implementation directly:

~~~swift
import XrayAppleTunnel

final class PacketTunnelProvider: XrayPacketTunnelProvider {}
~~~

The underlying core measured 3.84 MiB idle resident memory and 18.3 MiB with
1,000 held SOCKS flows in the published synthetic localhost benchmark. See the
[full results and methodology](https://github.com/aimalygin/xray-rust/blob/main/docs/benchmarks/results.md).

This project is unofficial and is not affiliated with XTLS or Xray-core.

## Version mapping

| Mobile SDK | xray-rust | Core commit | C ABI |
| --- | --- | --- | --- |
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

## Apple platforms with Swift Package Manager

Add the package:

~~~swift
dependencies: [
    .package(
        url: "https://github.com/aimalygin/xray-rust-mobile.git",
        exact: "0.4.0"
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

The Android SDK is published to Maven Central and does not require GitHub
credentials.

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
    implementation("io.github.aimalygin:xray-rust-mobile:0.4.0")
}
~~~

The published coordinate, POM, signatures, sources, and API documentation are
available from [Maven Central](https://central.sonatype.com/artifact/io.github.aimalygin/xray-rust-mobile/0.4.0).

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
