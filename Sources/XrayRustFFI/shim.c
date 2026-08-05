// SwiftPM requires every Clang target to contain at least one source file.
//
// This target carries no implementation: it exists only to publish the
// upstream `xray_ffi.h` and its module map into the package graph, so that
// `XrayRust.xcframework` can ship bare `.a` slices. Xcode copies the headers
// of a static-library XCFramework into a flat, per-configuration `include`
// directory, where the fixed `module.modulemap` name collides with any other
// static-library XCFramework a consumer links. Owning the module here keeps
// that directory out of the build entirely.
//
// The implementation lives in the XrayRust binary target.

typedef int xray_ffi_module_shim;
