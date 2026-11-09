import Foundation
import ConnectivityAndInternetAccess
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
#if canImport(Network)
import Network
import Darwin

/// NWPath is a routing hint, never proof of HTTPS access or portal absence.
public struct NetworkSnapshot: Sendable, Equatable {
    public let available: Bool
    public let wifi: Bool
    public let cellular: Bool
    public let expensive: Bool
    public let constrained: Bool
    public let interfaceName: String
    public let observedAt: Date

    public init(state: NetworkState) {
        available = state.isConnected
        wifi = state.interfaceType == .wifi
        cellular = state.interfaceType == .cellular
        expensive = state.isExpensive
        constrained = state.isConstrained
        interfaceName = state.interfaceType.description
        observedAt = state.timestamp
    }

    public var description: String {
        guard available else { return "Sin conexión de red detectada" }
        let route = wifi ? "Wi-Fi" : (cellular ? "Datos móviles" : "Otra conexión")
        return route + (constrained ? " · modo de datos reducidos" : "")
                     + (expensive ? " · red de coste elevado" : "")
    }
}

/// Adapter to the shared package's single passive observer; no second NWPathMonitor.
public final class NetworkPathObserver: @unchecked Sendable {
    public var onUpdate: ((NetworkSnapshot) -> Void)?
    private var token: NetworkObserverToken?

    public init() {}
    /// Called on the main actor by NewsViewModel; callbacks arrive on the main queue.
    public func start() {
        guard token == nil else { return }
        token = ConnectivityAndInternetAccess.observeNetwork { [weak self] state in
            self?.onUpdate?(NetworkSnapshot(state: state))
        }
    }
    public func stop() {
        token?.close()
        token = nil
    }
    deinit { token?.close() }
}

public struct ConnectivityReport: Sendable {
    public let https: Bool
    public let dns: Bool
    public let tcp: Bool
    public let tls: Bool
    public let ntp: Bool
    public let elapsed: TimeInterval
    public let sharedProbe: ReachabilityResult
    public let portalProbe: ReachabilityResult

    /// The feed itself is the primary check; DNS and path availability are only hints.
    public var webAvailable: Bool { https }

    /// A successful DNS stage must never be classified as HTTPS reachability.
    public static func provesHTTPS(_ result: ReachabilityResult) -> Bool {
        result.isReachable && result.stage == .httpProbe &&
            (result.reachedHost?.hasPrefix("https://") ?? false)
    }
}

/// Active probes run only on explicit request or after a transport error.
/// The original DNS / TCP / TLS / NTP tests remain available alongside the shared package.
public actor ConnectivityEngine {
    private var inFlight: Task<ConnectivityReport, Never>?

    public init() {}

    public func diagnose() async -> ConnectivityReport {
        if let inFlight { return await inFlight.value }
        let job = Task { await Self.runDiagnostic() }
        inFlight = job
        let result = await job.value
        inFlight = nil
        return result
    }

    /// Do not preflight each RSS request: the actual HTTPS feed transfer comes first.
    public func webAvailableAfterFeedFailure() async -> Bool {
        await Self.probeHTTPS()
    }

    private static func runDiagnostic() async -> ConnectivityReport {
        let start = Date()
        // Use the complete, configurable SPM engine: system DNS -> direct UDP
        // resolvers -> HTTP fallback. DNS-only success never proves HTTPS.
        let generalEngine = ConnectivityAndInternetAccess.Builder()
            .setSystemDNSHost("example.com")
            .setDnsResolvers(["1.1.1.1", "8.8.8.8", "9.9.9.9", "208.67.222.222"])
            .setHosts([
                "https://www.google.com/generate_204",
                "https://www.apple.com/library/test/success.html",
                "https://www.cloudflare.com/cdn-cgi/trace"
            ])
            .setGlobalTimeout(2.5)
            .build()
        let portalEngine = ConnectivityAndInternetAccess.strictCaptivePortalBuilder().build()
        async let shared = generalEngine.checkInternetAsync()
        async let portal = portalEngine.checkInternetAsync()
        async let https = probeHTTPS()
        async let dns = probeDNS("www.apple.com")
        async let tcp = probeConnection("1.1.1.1", port: 443, tls: false)
        async let tls = probeConnection("www.apple.com", port: 443, tls: true)
        async let ntp = probeNTP("time.google.com")
        return await ConnectivityReport(
            https: https, dns: dns, tcp: tcp, tls: tls, ntp: ntp,
            elapsed: Date().timeIntervalSince(start),
            sharedProbe: shared, portalProbe: portal
        )
    }

    /// Only a verified HTTPS response (not DNS, TCP, or an HTTP captive-portal page)
    /// counts as proof of general web connectivity.
    private static func probeHTTPS() async -> Bool {
        let endpoints: [(String, Int)] = [
            ("https://www.google.com/generate_204", 204),
            ("https://www.apple.com/library/test/success.html", 200)
        ]
        for (address, expectedCode) in endpoints {
            guard let url = URL(string: address) else { continue }
            let config = URLSessionConfiguration.ephemeral
            config.timeoutIntervalForRequest = 4
            config.timeoutIntervalForResource = 4
            let session = URLSession(configuration: config)
            defer { session.invalidateAndCancel() }
            var request = URLRequest(url: url)
            request.httpMethod = "GET"
            request.setValue("NewsReader-iOS/1.1", forHTTPHeaderField: "User-Agent")
            guard let (data, response) = try? await session.data(for: request),
                  let http = response as? HTTPURLResponse,
                  http.statusCode == expectedCode,
                  http.url?.host == url.host else { continue }
            if expectedCode == 204 { return true }
            if String(data: data, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines) == "Success" { return true }
        }
        return false
    }

    private static func probeDNS(_ host: String) async -> Bool {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                var result: UnsafeMutablePointer<addrinfo>?
                let code = getaddrinfo(host, nil, nil, &result)
                if let result { freeaddrinfo(result) }
                continuation.resume(returning: code == 0)
            }
        }
    }

    private static func probeConnection(_ host: String, port: UInt16,
                                        tls: Bool) async -> Bool {
        await withCheckedContinuation { continuation in
            let connection = NWConnection(host: NWEndpoint.Host(host),
                                          port: NWEndpoint.Port(rawValue: port)!,
                                          using: tls ? .tls : .tcp)
            let once = CompletionLatch { ok in
                connection.cancel()
                continuation.resume(returning: ok)
            }
            connection.stateUpdateHandler = { state in
                switch state {
                case .ready: once.complete(true)
                case .failed, .cancelled: once.complete(false)
                default: break
                }
            }
            connection.start(queue: DispatchQueue.global(qos: .utility))
            DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 4) {
                once.complete(false)
            }
        }
    }

    private static func probeNTP(_ host: String) async -> Bool {
        await withCheckedContinuation { continuation in
            let connection = NWConnection(host: NWEndpoint.Host(host),
                                          port: NWEndpoint.Port(rawValue: 123)!,
                                          using: .udp)
            let once = CompletionLatch { ok in
                connection.cancel()
                continuation.resume(returning: ok)
            }
            connection.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    var packet = [UInt8](repeating: 0, count: 48)
                    packet[0] = 0x1B
                    connection.send(content: Data(packet), completion: .contentProcessed { error in
                        if error != nil { once.complete(false) }
                    })
                    connection.receiveMessage { data, _, _, error in
                        once.complete(error == nil && (data?.count ?? 0) >= 48)
                    }
                case .failed, .cancelled: once.complete(false)
                default: break
                }
            }
            connection.start(queue: DispatchQueue.global(qos: .utility))
            DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 4) {
                once.complete(false)
            }
        }
    }
}

private final class CompletionLatch: @unchecked Sendable {
    private let lock = NSLock()
    private var completed = false
    private let callback: (Bool) -> Void

    init(_ callback: @escaping (Bool) -> Void) { self.callback = callback }
    func complete(_ value: Bool) {
        lock.lock()
        let shouldComplete = !completed
        completed = true
        lock.unlock()
        if shouldComplete { callback(value) }
    }
}
#endif
