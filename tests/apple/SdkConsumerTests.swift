import Foundation
import XCTest
import XrayMobileAdapter
import XrayAppleShared
import XrayAppleTunnel

// Use public imports only: this exercises the packaged SDK, rather than
// reaching into adapter internals with @testable.
final class SdkConsumerTests: XCTestCase {
    func testHTTPAndHTTPSImportThroughPublicPackageAPI() throws {
        XCTAssertTrue(XrayCore.ffiInfo.supportsProfileImport(.http))
        for scheme in ["http", "https"] {
            let profile = try XrayProfileImporter.profile(
                from: "\(scheme)://synthetic:p%40ss@proxy.example:8443#Proxy", format: .http,
                dnsServers: ["192.0.2.53"])
            XCTAssertEqual(profile.name, "Proxy")
            XCTAssertEqual(profile.serverAddress, "proxy.example")
            try XrayMobileDNSPreflight.validate(profile.configJSON)
            _ = try XrayCore(configJSON: profile.configJSON)
        }
    }

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
        let masks = try XCTUnwrap(mask["udp"] as? [[String: Any]])
        XCTAssertEqual(masks[0]["type"] as? String, "udphop")
        XCTAssertEqual(masks[1]["type"] as? String, "salamander")
        let hop = try XCTUnwrap(masks[0]["settings"] as? [String: Any])
        XCTAssertEqual(hop["mode"] as? String, "intervalLocal,intervalRemote")
        XCTAssertEqual(hop["remotePorts"] as? String, "443,8443-8444")
        XCTAssertEqual((mask["quicParams"] as? [String: Any])?["disableChromeParrot"] as? Bool, true)
        try XrayMobileDNSPreflight.validate(profile.configJSON)
        _ = try XrayCore(configJSON: profile.configJSON)
    }

    func testUdpNoiseReachesBothQuicCarriersThroughPackagedFFI() throws {
        let carriers = [
            #"""
            {"protocol":"hysteria","settings":{"version":2,"address":"127.0.0.1","port":443},
             "streamSettings":{"network":"hysteria","security":"tls","tlsSettings":{"serverName":"example.test"},
              "hysteriaSettings":{"version":2,"auth":"synthetic"},"finalmask":{"udp":[
               {"type":"noise","settings":{"noise":[{"rand":"16-24","delay":1}]}},
               {"type":"salamander","settings":{"password":"synthetic"}}]}}}
            """#,
            #"""
            {"protocol":"trojan","settings":{"address":"127.0.0.1","port":443,"password":"synthetic"},
             "streamSettings":{"network":"xhttp","security":"tls","tlsSettings":{"serverName":"example.test","alpn":["h3"]},
              "finalmask":{"udp":[{"type":"noise","settings":{"noise":[{"rand":"16-24","delay":1}]}}]}}}
            """#
        ]
        for outbound in carriers {
            let config = #"{"dns":{"servers":["127.0.0.1"]},"inbounds":[{"protocol":"tun"}],"outbounds":["# + outbound + "]}"
            try XrayMobileDNSPreflight.validate(config)
            _ = try XrayCore(configJSON: config)
            XCTAssertThrowsError(try XrayCore(configJSON: config.replacingOccurrences(of: #""rand":"16-24""#, with: #""rand":4097"#)))
        }
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

    func testNewDialerProxyAndWireGuardDNSReachNativeValidation() throws {
        let chain = #"{"outbounds":[{"tag":"entry","protocol":"http","settings":{"address":"192.0.2.10","port":8080},"streamSettings":{"sockopt":{"dialerProxy":"exit"}}},{"tag":"exit","protocol":"freedom"}]}"#
        _ = try XrayCore(configJSON: chain)
        XCTAssertThrowsError(try XrayCore(configJSON: chain.replacingOccurrences(of: #""dialerProxy":"exit""#, with: #""dialerProxy":"missing""#)))
        let wireguard = #"{"outbounds":[{"protocol":"wireguard","settings":{"secretKey":"4242424242424242424242424242424242424242424242424242424242424242","address":["10.44.0.2"],"remoteDNS":["192.0.2.53"],"peers":[{"publicKey":"6363636363636363636363636363636363636363636363636363636363636363","endpoint":"192.0.2.1:51820"}]}}]}"#
        _ = try XrayCore(configJSON: wireguard)
        XCTAssertThrowsError(try XrayCore(configJSON: wireguard.replacingOccurrences(of: "192.0.2.53", with: "dns.example")))
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
