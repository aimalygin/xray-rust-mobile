# xray-rust-mobile

Binary iOS, tvOS, macOS, and Android distribution for
[`xray-rust`](https://github.com/aimalygin/xray-rust).

The Rust implementation stays in the core repository. This repository pins one
reviewed core commit, carries the native Swift/Kotlin adapters, and publishes:

- `XrayRust.xcframework.zip` for Swift Package Manager;
- `io.github.aimalygin:xray-rust-mobile` as an Android AAR/Maven module;
- matching checksums and a release manifest.

## Version mapping

| Mobile SDK | xray-rust | Core commit | C ABI |
| --- | --- | --- | --- |
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
        exact: "0.1.4"
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
  import, logging, and DNS preflight;
- `XrayAppleTunnel` — a ready-to-subclass `NEPacketTunnelProvider`.

Minimum supported versions are iOS 15, tvOS 17, and macOS 11. The binary
contains `arm64` device slices and `arm64` plus `x86_64` simulator slices for
iOS and tvOS, plus a universal `arm64`/`x86_64` macOS slice.
`XrayAppleTunnel` APIs that depend on newer Network Extension functionality
require macOS 13.

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

The default publication target is GitHub Packages:

In `settings.gradle.kts`:

~~~kotlin
dependencyResolutionManagement {
    repositories {
        google()
        mavenCentral()
        maven {
            url = uri(
                "https://maven.pkg.github.com/aimalygin/xray-rust-mobile"
            )
            credentials {
                username = providers.gradleProperty("gpr.user").orNull
                    ?: System.getenv("GITHUB_ACTOR")
                password = providers.gradleProperty("gpr.key").orNull
                    ?: System.getenv("GITHUB_TOKEN")
            }
        }
    }
}
~~~

In the app module's `build.gradle.kts`:

~~~kotlin
dependencies {
    implementation("io.github.aimalygin:xray-rust-mobile:0.1.4")
}
~~~

GitHub currently requires package credentials even for public Maven packages;
use a personal access token (classic) with `read:packages`. Keep credentials
outside the project, for example in `~/.gradle/gradle.properties`:

~~~properties
gpr.user=<your GitHub username>
gpr.key=<PAT classic with read:packages>
~~~

Every GitHub release also contains the standalone AAR. Maven Central
publication can be added after the namespace and signing credentials are
provisioned.

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
Xcode for release reproducibility. For a local, non-release experiment only,
set `XRAY_ALLOW_UNPINNED_XCODE=1`.

Apple:

~~~sh
source release/toolchains.env
rustup toolchain install "$RUST_TOOLCHAIN" --profile minimal
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
