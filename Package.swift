// swift-tools-version: 5.9

import Foundation
import PackageDescription

let releaseVersion = "0.1.2"
let releaseChecksum = "16abc4c6876f283ac93533a1fd5ffdc5ebe8a45eac81f6b82fb0509b7b9b1455"
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
