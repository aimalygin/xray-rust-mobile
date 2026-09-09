// swift-tools-version: 5.9

import Foundation
import PackageDescription

let releaseVersion = "0.6.1"
let releaseChecksum = "acd9bc2d40c27e360a16ac3860ec48882cf8ac17f23f2d564bb954b7071a84c4"
let localXCFrameworkPath = "Artifacts/XrayRust.xcframework"
let packageDirectory = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
let localXCFrameworkURL = packageDirectory.appendingPathComponent(
    localXCFrameworkPath
)
let usesLocalXCFramework = FileManager.default.fileExists(
    atPath: localXCFrameworkURL.path
)
let supportedPlatforms: [SupportedPlatform] = [
    .iOS(.v15),
    .tvOS(.v17),
    .macOS(.v11),
]

let xrayRustTarget: Target = if usesLocalXCFramework {
    .binaryTarget(
        name: "XrayRust",
        path: localXCFrameworkPath
    )
} else {
    .binaryTarget(
        name: "XrayRust",
        url: "https://github.com/aimalygin/xray-rust-mobile/releases/download/v\(releaseVersion)/XrayRust.xcframework.zip",
        checksum: releaseChecksum
    )
}

let package = Package(
    name: "XrayRustMobile",
    platforms: supportedPlatforms,
    products: [
        .library(name: "XrayMobileAdapter", targets: ["XrayMobileAdapter"]),
        .library(name: "XrayAppleShared", targets: ["XrayAppleShared"]),
        .library(name: "XrayAppleTunnel", targets: ["XrayAppleTunnel"]),
    ],
    targets: [
        xrayRustTarget,
        // The XCFramework ships bare `.a` slices with no headers, so the
        // public C API is published from here instead. `include/module.modulemap`
        // is vendored verbatim from the pinned core and declares `module
        // XrayRust`, which keeps the import name unchanged for the adapters.
        .target(
            name: "XrayRustFFI",
            dependencies: ["XrayRust"],
            publicHeadersPath: "include"
        ),
        .target(
            name: "XrayAppleShared"
        ),
        .target(
            name: "XrayKernelControl"
        ),
        .target(
            name: "XrayMobileAdapter",
            dependencies: [
                "XrayRustFFI",
                "XrayAppleShared",
                "XrayKernelControl",
            ]
        ),
        .target(
            name: "XrayAppleTunnel",
            dependencies: [
                "XrayAppleShared",
                "XrayMobileAdapter",
            ]
        ),
        .testTarget(
            name: "XrayAppleSharedTests",
            dependencies: ["XrayAppleShared"],
            path: "platform/apple/Tests/XrayAppleSharedTests"
        ),
        .testTarget(
            name: "XrayMobileAdapterTests",
            dependencies: [
                "XrayMobileAdapter",
                "XrayKernelControl",
            ],
            path: "platform/apple/Tests/XrayMobileAdapterTests"
        ),
        .testTarget(
            name: "XrayAppleTunnelTests",
            dependencies: ["XrayAppleTunnel"],
            path: "platform/apple/Tests/XrayAppleTunnelTests"
        ),
    ]
)
