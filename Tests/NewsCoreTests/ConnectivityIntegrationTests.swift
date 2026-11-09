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
}
