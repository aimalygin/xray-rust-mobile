# Changelog

## Unreleased

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
