import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
#if canImport(Network)
import Network
import Darwin

/// iOS counterpart of the Android connectivity utility. Reachability is a hint,
/// not a guarantee that the news server or the physical network is trustworthy.
public struct NetworkSnapshot: Sendable, Equatable {
    public let available: Bool
    public let wifi: Bool
    public let cellular: Bool
    public let expensive: Bool
    public let constrained: Bool

    public var description: String {
        guard available else { return "Sin conexión de red detectada" }
        let route = wifi ? "Wi-Fi" : cellular ? "Datos móviles" : "Otra conexión"
        return route + (constrained ? " · modo de datos reducidos" : "")
                    + (expensive ? " · red de coste elevado" : "")
    }
}

/// Passive OS observation; does not open sockets, ping or request web pages.
public final class NetworkPathObserver {
    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "news.network.path")
    public var onUpdate: ((NetworkSnapshot) -> Void)?

    public init() {}
    public func start() {
        monitor.pathUpdateHandler = { [weak self] path in
            let snapshot = NetworkSnapshot(
                available: path.status == .satisfied,
                wifi: path.usesInterfaceType(.wifi),
                cellular: path.usesInterfaceType(.cellular),
                expensive: path.isExpensive,
                constrained: path.isConstrained)
            self?.onUpdate?(snapshot)
        }
        monitor.start(queue: queue)
    }
    public func stop() { monitor.cancel() }
}

public struct ConnectivityReport: Sendable {
    public let https: Bool
    public let dns: Bool
    public let tcp: Bool
    public let tls: Bool
    public let ntp: Bool
    public let elapsed: TimeInterval

    /// Only a real HTTPS response establishes general web access.
    public var webAvailable: Bool { https }
}

/// Multi-layer active diagnostics are opt-in or run after ambiguous feed errors.
/// One active manual report at a time and at most five parallel probes.
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

    /// Post-failure classifier only. Never call before downloading RSS or images.
    public func webAvailableAfterFeedFailure() async -> Bool {
        await Self.probeHTTPS()
    }

    private static func runDiagnostic() async -> ConnectivityReport {
        let start = Date()
        async let https = probeHTTPS()
        async let dns = probeDNS("www.apple.com")
        async let tcp = probeConnection("1.1.1.1", port: 443, tls: false)
        async let tls = probeConnection("www.apple.com", port: 443, tls: true)
        async let ntp = probeNTP("time.google.com")
        return await ConnectivityReport(
            https: https, dns: dns, tcp: tcp, tls: tls, ntp: ntp,
            elapsed: Date().timeIntervalSince(start))
    }

    private static func probeHTTPS() async -> Bool {
        for url in ["https://www.apple.com/library/test/success.html",
                    "https://www.google.com/generate_204"] {
            guard let endpoint = URL(string: url) else { continue }
            let config = URLSessionConfiguration.ephemeral
            config.timeoutIntervalForRequest = 4
            config.timeoutIntervalForResource = 4
            let session = URLSession(configuration: config)
            defer { session.invalidateAndCancel() }
            var request = URLRequest(url: endpoint)
            request.httpMethod = "GET"
            request.setValue("NewsReader-iOS/1.0", forHTTPHeaderField: "User-Agent")
            if let (_, response) = try? await session.data(for: request),
               let http = response as? HTTPURLResponse,
               (200...399).contains(http.statusCode) { return true }
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
