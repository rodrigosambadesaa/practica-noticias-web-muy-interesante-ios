import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public enum FeedFailure: Error, LocalizedError, Equatable {
    case invalidResponse
    case httpStatus(Int)
    case transport(String)
    case malformedFeed

    public var errorDescription: String? {
        switch self {
        case .invalidResponse: return "El servidor no devolvió una respuesta HTTP válida."
        case .httpStatus(let code): return "El servidor RSS devolvió HTTP \(code)."
        case .transport: return "No se pudo establecer comunicación con el servidor RSS."
        case .malformedFeed: return "El contenido del feed no es XML/RSS válido."
        }
    }
    public var requiresConnectivityDiagnosis: Bool {
        if case .transport = self { return true }
        return false
    }
}

public protocol FeedTransport: Sendable {
    func retrieve(_ url: URL) async throws -> (Data, Int)
}

public struct URLSessionFeedTransport: FeedTransport {
    public init() {}
    public func retrieve(_ url: URL) async throws -> (Data, Int) {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 15
        config.timeoutIntervalForResource = 30
        let session = URLSession(configuration: config)
        defer { session.finishTasksAndInvalidate() }
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData)
        request.setValue("application/rss+xml, application/xml, text/xml, */*", forHTTPHeaderField: "Accept")
        request.setValue("NewsReader-iOS/1.0", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw FeedFailure.invalidResponse }
        return (data, http.statusCode)
    }
}

public actor FeedRepository {
    private let transport: any FeedTransport
    public init(transport: any FeedTransport = URLSessionFeedTransport()) {
        self.transport = transport
    }

    public func load(_ url: URL) async throws -> [NewsArticle] {
        let payload: (Data, Int)
        do {
            payload = try await transport.retrieve(url)
        } catch let error as FeedFailure {
            throw error
        } catch {
            throw FeedFailure.transport(String(describing: error))
        }
        guard (200...299).contains(payload.1) else { throw FeedFailure.httpStatus(payload.1) }
        do {
            return try RSSParser.parse(payload.0)
        } catch {
            throw FeedFailure.malformedFeed
        }
    }

    public static func unique(_ original: [NewsArticle], adding more: [NewsArticle]) -> [NewsArticle] {
        var seen = Set(original.map(\.id))
        var result = original
        for item in more where seen.insert(item.id).inserted { result.append(item) }
        return result
    }
}

public actor NewsCache {
    private let file: URL
    public init(file: URL? = nil) {
        if let file { self.file = file }
        else {
            let root = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            self.file = root.appendingPathComponent("news-cache.json")
        }
    }

    public func load() -> [NewsArticle] {
        guard let data = try? Data(contentsOf: file),
              let saved = try? JSONDecoder().decode([NewsArticle].self, from: data) else { return [] }
        return saved
    }
    public func save(_ articles: [NewsArticle]) {
        guard let data = try? JSONEncoder().encode(articles) else { return }
        try? data.write(to: file, options: .atomic)
    }
}
