// swift-tools-version: 5.9

import Foundation
import PackageDescription

let releaseVersion = "0.1.7"
let releaseChecksum = "0000000000000000000000000000000000000000000000000000000000000000"
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
            name: "XrayMobileAdapter",
            dependencies: [
                "XrayRustFFI",
                "XrayAppleShared",
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
            dependencies: ["XrayAppleShared"]
        ),
        .testTarget(
            name: "XrayMobileAdapterTests",
            dependencies: ["XrayMobileAdapter"]
        ),
        .testTarget(
            name: "XrayAppleTunnelTests",
            dependencies: ["XrayAppleTunnel"]
        ),
    ]
)
