import Foundation
import XCTest
import XrayMobileAdapter
import XrayAppleShared
import XrayAppleTunnel

// Use public imports only: this exercises the packaged SDK, rather than
// reaching into adapter internals with @testable.
final class SdkConsumerTests: XCTestCase {
    func testHostOptionsAndIdleRebindThroughPackagedFFI() throws {
        let info = XrayCore.ffiInfo
        XCTAssertEqual(info.version.major, 1)
        XCTAssertGreaterThanOrEqual(info.version.minor, 11)
        XCTAssertTrue(info.supports(.hysteriaStreamLimits))
        XCTAssertTrue(info.supports(.tunAdmission))
        XCTAssertTrue(info.supports(.outboundProbe))
        let core = try XrayCore(configJSON:
            """
            {"inbounds":[{"protocol":"tun"}],"outbounds":[{"protocol":"freedom"}]}
            """,
            hysteriaStreamLimits: XrayHysteriaStreamLimits(maxTcpStreams: 128, maxUdpSessions: 64),
            tunAdmission: XrayTunAdmissionOptions { _ in false })
        try core.start()
        defer { try? core.stop() }
        XCTAssertEqual(try core.rebindHysteria(), 0)
        XCTAssertEqual(try core.rebindWireGuard(), 0)
    }

    func testSalamanderAndHoppingSurvivePublicImportAndPreflight() throws {
        let profile = try XrayProfileImporter.profile(from:
            "hy2://synthetic@example.test:443?obfs=salamander&obfs-password=synthetic-test&mport=443,8443-8444",
            format: .hysteria2)
        let root = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(profile.configJSON.utf8)) as? [String: Any])
        let proxy = try XCTUnwrap((root["outbounds"] as? [[String: Any]])?.first)
        let stream = try XCTUnwrap(proxy["streamSettings"] as? [String: Any])
        let mask = try XCTUnwrap(stream["finalmask"] as? [String: Any])
        XCTAssertEqual((mask["udp"] as? [[String: Any]])?.first?["type"] as? String, "salamander")
        XCTAssertNotNil((mask["quicParams"] as? [String: Any])?["udpHop"])
        try XrayMobileDNSPreflight.validate(profile.configJSON)
        _ = try XrayCore(configJSON: profile.configJSON)
    }

    func testFragmentConfigurationReachesNativeValidation() throws {
        let config = """
        {"dns":{"servers":["127.0.0.1"]},"inbounds":[{"protocol":"tun"}],"outbounds":[{"protocol":"trojan",
          "settings":{"address":"127.0.0.1","port":443,"password":"synthetic-test"},
          "streamSettings":{"network":"raw","security":"tls","tlsSettings":{"serverName":"example.test"},
            "finalmask":{"tcp":[{"type":"fragment","settings":{"packets":"tlshello","length":37,"delay":0}}]}}}]}
        """
        try XrayMobileDNSPreflight.validate(config)
        _ = try XrayCore(configJSON: config)
        XCTAssertThrowsError(try XrayCore(configJSON: config.replacingOccurrences(of: "\"length\":37", with: "\"length\":0")))
    }
}

// Compilation verifies external subclass access. Instantiating NEProvider in an
// unsigned XCTest process requires Apple's Network Extension entitlement; the
// canonical tests exercise the provider's native factory with both I/O backends.
@available(macOS 13.0, *)
private final class ConsumerPacketTunnelProvider: XrayPacketTunnelProvider {
    override func hysteriaStreamLimits() throws -> XrayHysteriaStreamLimits? {
        try .init(maxTcpStreams: 128, maxUdpSessions: 64)
    }

    override func tunAdmissionOptions() throws -> XrayTunAdmissionOptions? {
        try .init(timeoutMilliseconds: 100, failOpen: false) { flow in
            flow.addressFamily == 4
        }
    }
}
