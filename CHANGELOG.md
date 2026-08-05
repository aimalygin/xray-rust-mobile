# Changelog

## Unreleased

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
