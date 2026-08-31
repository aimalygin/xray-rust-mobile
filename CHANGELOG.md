# Changelog

## Unreleased

## 0.4.1-rc.4 - 2026-08-31

- Repinned the SDK to the source-only [`xray-rust` v0.4.1-rc.4][core-0.4.1-rc.4]
  prerelease. It fixes sustained XHTTP/2 `stream-up` uploads, adds safe
  pre-commit HTTP/2 GOAWAY retries, handles post-body HTTP/3 `H3_NO_ERROR`
  resets correctly, and compiles routing IP ranges with Xray-compatible
  address-family semantics.
- The core candidate is bound by exact annotated-tag, commit, tree, lockfile,
  FFI-header, and module-map identities and passed the expanded RC
  interoperability, fuzz, platform, supply-chain, and benchmark-evidence
  gates.
- This mobile RC is distributed only as a GitHub prerelease. Android is
  available as a standalone AAR asset for direct evaluation; no Maven archive
  or coordinate is published to GitHub Packages or Maven Central.

[core-0.4.1-rc.4]: https://github.com/aimalygin/xray-rust/releases/tag/v0.4.1-rc.4

## 0.4.1-rc.3 - 2026-08-28

- Repinned the SDK to the source-only [`xray-rust` v0.4.1-rc.3][core-0.4.1-rc.3]
  release candidate. It synchronizes the supported Xray-core v26.7.28
  configuration surface, including stricter plaintext VLESS validation, DNS
  outbound response controls, certificate pinning and peer-name verification,
  and target-compatible XHTTP session identifiers.
- This mobile RC is distributed only as a GitHub prerelease. Android is
  available as a standalone AAR asset for direct evaluation; no Maven archive
  or coordinate is published to GitHub Packages or Maven Central.

[core-0.4.1-rc.3]: https://github.com/aimalygin/xray-rust/releases/tag/v0.4.1-rc.3

## 0.4.0 - 2026-08-27

- Repinned the core to [`xray-rust` v0.4.0][core-0.4.0]. Apple VLESS URL
  imports now support XHTTP/SplitHTTP over plaintext, TLS, and REALITY,
  including bounded decoding of the XHTTP `extra` object. Unsupported
  non-empty certificate-pin/ECH parameters fail closed; the removed
  `scMaxConcurrentPosts` field remains import-compatible but is ignored, and
  XHTTP profiles do not acquire the raw-only Vision flow during migration.
- Reduced memory pressure for plaintext HTTP/1.1 XHTTP packet-up traffic by
  growing request bodies in 8 KiB steps and avoiding an extra payload clone.
  The core release includes an exact-profile RSS benchmark for this path.
- Updated `h2` to 0.4.16 for its upstream RustSec fix and replaced the yanked
  transitive `chacha20` 0.10.1 lock entry with 0.10.2.

[core-0.4.0]: https://github.com/aimalygin/xray-rust/releases/tag/v0.4.0

## 0.3.2 - 2026-08-16

- Repinned the core to [`xray-rust` v0.3.2][core-0.3.2]. Apple VLESS URL
  imports now preserve an omitted `flow` instead of silently enabling
  `xtls-rprx-vision`, matching the share-link semantics and server-side client
  configuration.

[core-0.3.2]: https://github.com/aimalygin/xray-rust/releases/tag/v0.3.2

## 0.3.1 - 2026-08-16

- Repinned the core to [`xray-rust` v0.3.1][core-0.3.1]. REALITY handshakes
  now advertise the Xray-core 26.7.28 compatibility version, the fingerprint
  namespace and eleven-profile modern pool match Xray-core v26.7.28, and the
  three current explicit browser-profile names are available in the Apple API.
- Added optional Android `XrayCore.create(fileLoggingDirectory = ...)` support
  for bounded, app-controlled diagnostic exports. File logging remains disabled
  unless the host explicitly supplies an existing private directory.

[core-0.3.1]: https://github.com/aimalygin/xray-rust/releases/tag/v0.3.1

## 0.3.0 - 2026-08-10

- Repinned the core to [`xray-rust` v0.3.0][core-0.3.0]. VLESS outbounds now
  support WebSocket, HTTPUpgrade, gRPC, and XHTTP (including the declared
  HTTP/3 subset), while TLS connections use Xray-compatible browser
  fingerprints by default.
- Made the fd-backed mobile TUN pump recover from transient I/O errors instead
  of silently stopping packet flow. New read-loop exit, write-loop exit, and
  transient-I/O counters are exposed through the C ABI and Swift diagnostics;
  ABI major 1 remains backward compatible through the size-prefixed stats
  structure.
- Hardened Apple utun discovery by matching the kernel control id rather than
  trusting an interface-name socket option. The Swift package now includes the
  `XrayKernelControl` C target required by the updated adapter.
- Preserved core status messages when `XrayCoreError` bridges to `NSError`,
  retained IPv6 default-route capture, and improved imported VLESS profiles
  with HTTP/TLS/QUIC sniffing and a stable `UseIPv4` DNS query strategy.

[core-0.3.0]: https://github.com/aimalygin/xray-rust/releases/tag/v0.3.0

## 0.2.0 - 2026-08-05

- Repinned the core to [`xray-rust` v0.2.0][core-0.2.0], which fixes file
  logging initialization inside the iOS Network Extension sandbox.
  `xray_core_new` failed with "Operation not permitted" because runtime log
  files were opened by walking every ancestor directory with read access, which
  the sandbox denies outside the app-group container. Apple platforms now
  resolve the log path with a single `O_NOFOLLOW_ANY` open, which keeps
  rejecting symlinks in any path component. That open requires iOS 14.5+ /
  macOS 11.3+ at runtime: it is within the iOS 15 and tvOS 17 deployment
  targets, but macOS 11.0–11.2 no longer supports file logging. The C ABI, the
  Swift and Kotlin adapters, and the published products are unchanged.

[core-0.2.0]: https://github.com/aimalygin/xray-rust/releases/tag/v0.2.0

## 0.1.7 - 2026-08-05

- Repackaged the XCFramework as bare `libxray_ffi.a` slices with no headers and
  no framework bundles, and moved the public C API into a new `XrayRustFFI`
  Clang target that vendors `xray_ffi.h` and `module.modulemap` from the pinned
  core. Xcode copies the headers of a static-library XCFramework into a flat
  `$BUILT_PRODUCTS_DIR/include` directory where the `module.modulemap` name is
  fixed, so two such XCFrameworks in one target fail with "Multiple commands
  produce .../include/module.modulemap". Owning the module in the package keeps
  that directory out of the build entirely and replaces the hand-assembled
  static frameworks introduced in 0.1.4, which required synthesized
  `Info.plist` metadata and versioned macOS bundle symlinks. The vendored
  module map still declares `module XrayRust`, so `import XrayRust` and the
  public API are unchanged for consumers.
- Stripped the dead `__LLVM,__bitcode` section from every Apple slice. rustup
  ships `std` and `compiler_builtins` as rlibs that already carry embedded
  bitcode, and rustc copies those objects verbatim into a staticlib, so it
  accounted for more than half of the published XCFramework. Apple removed
  bitcode support in Xcode 14 and the linker ignores the section, so the
  produced binaries are unchanged: linking against a stripped and an unstripped
  slice yields byte-identical output. The Apple build now requires the
  `llvm-tools` component of the pinned Rust toolchain, because Xcode's own
  `bitcode_strip` wraps the linker's `-bitcode_strip` flag, which Apple removed
  in Xcode 15.

## 0.1.6 - 2026-08-04

- Fixed generated Apple framework metadata so each slice declares exactly one
  supported platform in `CFBundleSupportedPlatforms`.

## 0.1.5 - 2026-08-04

- Repackaged the macOS framework with the standard versioned bundle layout,
  including `Versions/A`, `Versions/Current`, and top-level compatibility
  symlinks. The iOS and tvOS framework layouts remain unchanged.

## 0.1.4 - 2026-08-04

- Repackaged the Apple binary as static frameworks inside the XCFramework.
  This prevents Xcode `ProcessXCFramework` output collisions on the shared
  `include/module.modulemap` path when a consumer links another static-library
  XCFramework. The module name, public API, and static linkage are unchanged.

## 0.1.3 - 2026-08-04

- Added tvOS 17+ support to the published Swift Package and binary
  XCFramework, with `arm64` device and universal `arm64`/`x86_64` simulator
  slices.

## 0.1.2 - 2026-08-03

- Added macOS 11+ support to the published Swift Package and its binary
  XCFramework, including a universal `arm64` and `x86_64` static-library slice.

## 0.1.1 - 2026-08-03

- Added Packet Tunnel support for loading host-managed geodata generations
  from a shared App Group directory. Explicit generations use exclusive search
  so missing assets fail closed instead of mixing with process-default data;
  configurations without App Group settings retain the bundle-resource
  fallback.
- Preserved the existing Packet Tunnel `NSError` domain and codes and added
  coverage for App Group path validation, start configuration, DNS pinning,
  and runtime geodata loading. Swift clients with an exhaustive switch over
  `XrayPacketTunnelProviderError` must handle the new
  `invalidGeodataConfiguration` case.
- Documented atomic publication and immutable retention of verified geodata
  generations.

## 0.1.0 - 2026-08-02

- Added the first binary distribution of `xray-rust` for iOS and Android.
- Added Swift Package products for the core adapter, shared Apple helpers, and
  a packet-tunnel provider.
- Added an Android AAR with Kotlin, JNI, and four native ABIs.
