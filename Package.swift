// swift-tools-version: 5.9

import Foundation
import PackageDescription

let releaseVersion = "0.1.1"
let releaseChecksum = "0000000000000000000000000000000000000000000000000000000000000000"
let localXCFrameworkPath = "Artifacts/XrayRust.xcframework"
let packageDirectory = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
let localXCFrameworkURL = packageDirectory.appendingPathComponent(
    localXCFrameworkPath
)
let usesLocalXCFramework = FileManager.default.fileExists(
    atPath: localXCFrameworkURL.path
)
let localXCFrameworkHasMacOS = FileManager.default.fileExists(
    atPath: localXCFrameworkURL
        .appendingPathComponent("macos-arm64_x86_64")
        .path
)

// Release assets are iOS-only. CI builds an additional local macOS slice so
// the shared Swift sources and XCTest suites can run on the host.
let supportedPlatforms: [SupportedPlatform] = if localXCFrameworkHasMacOS {
    [
        .iOS(.v15),
        .macOS(.v11),
    ]
} else {
    [
        .iOS(.v15),
    ]
}

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
        .target(
            name: "XrayAppleShared"
        ),
        .target(
            name: "XrayMobileAdapter",
            dependencies: [
                "XrayRust",
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
