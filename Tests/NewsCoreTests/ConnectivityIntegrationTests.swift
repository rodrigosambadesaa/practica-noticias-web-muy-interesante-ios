import XCTest
import ConnectivityAndInternetAccess
@testable import NewsCore

final class ConnectivityIntegrationTests: XCTestCase {
    func testDNSOnlyDoesNotProveHTTPS() {
        let answer = ReachabilityResult(isReachable: true,
                                        reachedHost: "dns://system/example.com",
                                        stage: .systemDNS)
        XCTAssertFalse(ConnectivityReport.provesHTTPS(answer))
    }

    func testDirectDNSOnlyDoesNotProveHTTPS() {
        let answer = ReachabilityResult(isReachable: true,
                                        reachedHost: "dns://1.1.1.1/example.com",
                                        stage: .directDNS)
        XCTAssertFalse(ConnectivityReport.provesHTTPS(answer))
    }

    func testOnlySuccessfulHTTPSProbeProvesHTTPS() {
        let success = ReachabilityResult(isReachable: true,
                                         reachedHost: "https://www.google.com/generate_204",
                                         stage: .httpProbe)
        let httpOnly = ReachabilityResult(isReachable: true,
                                          reachedHost: "http://example.com",
                                          stage: .httpProbe)
        let failed = ReachabilityResult(isReachable: false,
                                        reachedHost: "https://example.com",
                                        stage: .httpProbe)
        XCTAssertTrue(ConnectivityReport.provesHTTPS(success))
        XCTAssertFalse(ConnectivityReport.provesHTTPS(httpOnly))
        XCTAssertFalse(ConnectivityReport.provesHTTPS(failed))
    }

    func testOfflineNetworkSnapshotIsNotInternetValidation() {
        let state = NetworkState(isConnected: false)
        let snapshot = NetworkSnapshot(state: state)
        XCTAssertFalse(snapshot.available)
        XCTAssertTrue(snapshot.description.contains("Sin conexión"))
    }
    func testSharedBuilderRunsSystemDNSStageWithMock() async {
        let engine = ConnectivityAndInternetAccess.Builder()
            .setSystemDNSHost("example.com")
            .setDnsResolvers(["1.1.1.1", "8.8.8.8"])
            .setHosts(["https://example.com/generate_204"])
            .setGlobalTimeout(1.0)
            .setDnsProbeStrategy { host in host == "dns://system/example.com" }
            .setHttpProbeStrategy { url, _ in (true, 204, url.absoluteString) }
            .build()
        let result = await engine.checkInternetAsync()
        XCTAssertTrue(result.isReachable)
        XCTAssertEqual(result.stage, .systemDNS)
        XCTAssertEqual(result.attemptedHosts, ["dns://system/example.com"])
        XCTAssertFalse(ConnectivityReport.provesHTTPS(result))
    }

    func testSharedBuilderFallsThroughToDirectDNS() async {
        let engine = ConnectivityAndInternetAccess.Builder()
            .setSystemDNSHost("example.com")
            .setDnsResolvers(["1.1.1.1"])
            .setHosts([])
            .setGlobalTimeout(1.0)
            .setDnsProbeStrategy { $0 == "dns://1.1.1.1/example.com" }
            .build()
        let result = await engine.checkInternetAsync()
        XCTAssertEqual(result.stage, .directDNS)
        XCTAssertFalse(ConnectivityReport.provesHTTPS(result))
        XCTAssertTrue(result.attemptedHosts.contains("dns://1.1.1.1/example.com"))
    }

    func testSharedBuilderFallsThroughToHTTPS() async {
        let engine = ConnectivityAndInternetAccess.Builder()
            .setSystemDNSHost("")
            .setDnsResolvers([])
            .setHosts(["https://example.com/generate_204"])
            .setGlobalTimeout(1.0)
            .setHttpProbeStrategy { url, _ in (true, 204, url.absoluteString) }
            .build()
        let result = await engine.checkInternetAsync()
        XCTAssertEqual(result.stage, .httpProbe)
        XCTAssertTrue(ConnectivityReport.provesHTTPS(result))
        XCTAssertEqual(result.attemptedHosts, ["https://example.com/generate_204"])
    }

    func testStrictPortalModeSkipsDNS() {
        let engine = ConnectivityAndInternetAccess.strictCaptivePortalBuilder().build()
        XCTAssertTrue(engine.configuration.isStrictCaptivePortalMode)
        XCTAssertEqual(engine.configuration.dnsResolvers, [])
        XCTAssertEqual(engine.configuration.systemDNSHost, "")
    }

    func testSnapshotExposesTransportAndDoesNotDeclareInternetAccess() {
        let state = NetworkState(isConnected: true, interfaceType: .wifi,
                                 isExpensive: false, isConstrained: true)
        let snapshot = NetworkSnapshot(state: state)
        XCTAssertTrue(snapshot.available)
        XCTAssertEqual(snapshot.interfaceName, "Wi-Fi")
        XCTAssertTrue(snapshot.constrained)
        XCTAssertFalse(state.isInternetValidated)
        XCTAssertFalse(state.isCaptivePortalDetected)
    }

}
