import Network
import XCTest
import XrayMobileAdapter
@testable import XrayAppleTunnel

@available(macOS 13.0, *)
final class XrayStartupProbePreflightTests: XCTestCase {
    func testNetworkSettingsWaitForSuccessAndRuntimeDoesNotRepeatProbe() throws {
        let server = try PreflightHTTPServer()
        defer { server.close() }
        wait(for: [server.ready], timeout: 5)
        let harness = PreflightHarness()
        let config = try probeConfig(server)
        let finished = expectation(description: "settings reached after successful probe")
        harness.start(config, applyNetworkSettings: { prepared in
            XCTAssertEqual(prepared.json, config.json)
            XCTAssertEqual(prepared.excludedServerAddresses, config.excludedServerAddresses)
            XCTAssertEqual(prepared.useTunFileDescriptor, config.useTunFileDescriptor)
            XCTAssertEqual(prepared.startupProbeConfiguration, .disabled)
            do {
                let core = try XrayPacketTunnelProvider.makeCore(
                    resolvedConfig: prepared,
                    borrowedDarwinTunFileDescriptor: nil,
                    diagnosticLogDirectory: nil
                )
                // The HTTP server only answered the preflight. A repeated
                // startup probe would stall and fail this data-path start.
                try core.start()
                try core.stop()
            } catch {
                XCTFail("data-path start failed after successful preflight: \(error)")
            }
        }) { error in
            XCTAssertNil(error)
            finished.fulfill()
        }
        wait(for: [server.requestReceived], timeout: 5)
        XCTAssertEqual(harness.settingsCallCount, 0)
        server.respond(status: 204)
        wait(for: [finished], timeout: 5)
        XCTAssertEqual(harness.settingsCallCount, 1)
    }

    func testFailedProbeDoesNotApplyOrRollBackNetworkSettings() throws {
        let server = try PreflightHTTPServer()
        defer { server.close() }
        wait(for: [server.ready], timeout: 5)
        let harness = PreflightHarness()
        let finished = expectation(description: "failed startup probe")
        harness.start(try probeConfig(server)) { error in
            XCTAssertTrue(error?.localizedDescription.contains("HTTP status 503") == true)
            finished.fulfill()
        }
        wait(for: [server.requestReceived], timeout: 5)
        server.respond(status: 503)
        wait(for: [finished], timeout: 5)
        XCTAssertEqual(harness.settingsCallCount, 0)
    }

    func testTimedOutProbeDoesNotApplyNetworkSettings() throws {
        let server = try PreflightHTTPServer()
        defer { server.close() }
        wait(for: [server.ready], timeout: 5)
        let harness = PreflightHarness()
        let finished = expectation(description: "startup probe timeout")
        harness.start(try probeConfig(server, timeoutMs: 100)) { error in
            XCTAssertTrue(error?.localizedDescription.contains("timed out") == true)
            finished.fulfill()
        }
        wait(for: [finished], timeout: 5)
        XCTAssertEqual(harness.settingsCallCount, 0)
    }

    func testStopDuringProbeCompletesOnceWithoutApplyingSettings() throws {
        let server = try PreflightHTTPServer()
        defer { server.close() }
        wait(for: [server.ready], timeout: 5)
        let harness = PreflightHarness()
        let finished = expectation(description: "cancelled startup probe")
        finished.assertForOverFulfill = true
        harness.start(try probeConfig(server, timeoutMs: 60_000)) { error in
            XCTAssertEqual(error as? XrayPacketTunnelProviderError, .startSuperseded)
            finished.fulfill()
        }
        wait(for: [server.requestReceived], timeout: 5)
        let started = Date()
        harness.stop()
        wait(for: [finished], timeout: 2)
        XCTAssertLessThan(Date().timeIntervalSince(started), 2)
        server.respond(status: 204)
        XCTAssertEqual(harness.settingsCallCount, 0)
    }

    func testNewStartCancelsOldProbeAndOnlyNewStartAppliesSettings() throws {
        let oldServer = try PreflightHTTPServer()
        let newServer = try PreflightHTTPServer()
        defer { oldServer.close(); newServer.close() }
        wait(for: [oldServer.ready, newServer.ready], timeout: 5)
        let harness = PreflightHarness()
        let oldFinished = expectation(description: "old start superseded")
        oldFinished.assertForOverFulfill = true
        harness.start(try probeConfig(oldServer, timeoutMs: 60_000)) { error in
            XCTAssertEqual(error as? XrayPacketTunnelProviderError, .startSuperseded)
            oldFinished.fulfill()
        }
        wait(for: [oldServer.requestReceived], timeout: 5)
        let newFinished = expectation(description: "new start reaches settings")
        harness.start(try probeConfig(newServer)) { error in
            XCTAssertNil(error)
            newFinished.fulfill()
        }
        wait(for: [oldFinished, newServer.requestReceived], timeout: 5)
        XCTAssertEqual(harness.settingsCallCount, 0)
        oldServer.respond(status: 204)
        newServer.respond(status: 204)
        wait(for: [newFinished], timeout: 5)
        XCTAssertEqual(harness.settingsCallCount, 1)
    }

    func testDisabledProbeContinuesDirectlyToNetworkSettings() throws {
        let harness = PreflightHarness()
        let finished = expectation(description: "settings without probe")
        harness.start(try probeConfig(nil)) { error in
            XCTAssertNil(error)
            finished.fulfill()
        }
        wait(for: [finished], timeout: 5)
        XCTAssertEqual(harness.settingsCallCount, 1)
    }

    private func probeConfig(_ server: PreflightHTTPServer?, timeoutMs: UInt64 = 2_000) throws -> XrayPacketTunnelProvider.ResolvedConfig {
        let probe: XrayPacketTunnelStartupProbeConfiguration
        if let server {
            let port = try XCTUnwrap(server.listener.port)
            probe = .enabled(.init(url: "http://127.0.0.1:\(port.rawValue)/health", timeoutMs: timeoutMs))
        } else {
            probe = .disabled
        }
        return .init(
            json: #"{"inbounds":[{"protocol":"tun"}],"dns":{"servers":["1.1.1.1"]},"outbounds":[{"tag":"direct","protocol":"freedom"}]}"#,
            source: "test",
            serverAddress: nil,
            excludedServerAddresses: ["192.0.2.1"],
            debugLoggingEnabled: false,
            useTunFileDescriptor: true,
            tunRuntimeProfile: .default,
            startupProbeConfiguration: probe,
            dnsConfiguration: .system
        )
    }
}

// Exercises the exact preflight coordinator used by the provider, with the
// settings side effect injected. NEProvider itself requires an entitled host.
private final class PreflightHarness {
    private let lifecycle = XrayPacketTunnelLifecycle<Int> { _ in }
    private let completionQueue = DispatchQueue(label: "xray.test.preflight-completion")
    private let lock = NSLock()
    private var settingsCalls = 0

    var settingsCallCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return settingsCalls
    }

    func start(
        _ config: XrayPacketTunnelProvider.ResolvedConfig,
        applyNetworkSettings: @escaping (XrayPacketTunnelProvider.ResolvedConfig) -> Void = { _ in },
        completion: @escaping (Error?) -> Void
    ) {
        XrayPacketTunnelStartupProbePreflight.start(
            resolvedConfig: config,
            lifecycle: lifecycle,
            lifecycleToken: lifecycle.beginStart(),
            diagnosticLogDirectory: nil,
            completionQueue: completionQueue,
            applyNetworkSettings: { prepared in
                self.lock.lock()
                self.settingsCalls += 1
                self.lock.unlock()
                applyNetworkSettings(prepared)
                completion(nil)
            },
            completionHandler: completion
        )
    }

    func stop() { lifecycle.stop() }
}

private final class PreflightHTTPServer {
    let ready = XCTestExpectation(description: "HTTP server ready")
    let requestReceived = XCTestExpectation(description: "probe HTTP request received")
    let listener: NWListener
    private let queue = DispatchQueue(label: "xray.test.startup-preflight-server")
    private var connections: [NWConnection] = []

    init() throws {
        listener = try NWListener(using: .tcp, on: .any)
        listener.stateUpdateHandler = { [weak self] state in
            if case .ready = state { self?.ready.fulfill() }
        }
        listener.newConnectionHandler = { [weak self] connection in
            guard let self else { return }
            self.connections.append(connection)
            connection.start(queue: self.queue)
            self.receiveRequest(connection)
        }
        listener.start(queue: queue)
    }

    private func receiveRequest(_ connection: NWConnection, accumulated: Data = Data()) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 4_096) { [weak self] data, _, complete, error in
            guard let self else { return }
            let request = accumulated + (data ?? Data())
            if request.range(of: Data("\r\n\r\n".utf8)) != nil {
                self.requestReceived.fulfill()
            } else if !complete, error == nil, request.count < 4_096 {
                self.receiveRequest(connection, accumulated: request)
            }
        }
    }

    func respond(status: Int) {
        queue.sync {
            let response = Data("HTTP/1.1 \(status) Test\r\nContent-Length: 0\r\n\r\n".utf8)
            for connection in connections {
                connection.send(content: response, completion: .contentProcessed { _ in })
            }
        }
    }

    func close() {
        queue.sync {
            connections.forEach { $0.cancel() }
            listener.cancel()
        }
    }
}
