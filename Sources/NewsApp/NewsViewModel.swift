import Foundation
import Network
import NewsCore
import SwiftUI

@MainActor
final class NewsViewModel: ObservableObject {
    @Published var articles: [NewsArticle] = []
    @Published var search = ""
    @Published var visibleCount = 20
    @Published var loading = false
    @Published var loadingMore = false
    @Published var networkStatus = "Comprobando conexión…"
    @Published var diagnosticMessage: String?
    @Published var alertMessage: String?

    let settings: FeedSettings
    private let repository = FeedRepository()
    private let cache = NewsCache()
    private let diagnostics = ConnectivityEngine()
    private let observer = NetworkPathObserver()
    private var started = false
    private var nextPage = 2
    private var exhausted = false
    private var consecutiveDuplicates = 0

    init(settings: FeedSettings) {
        self.settings = settings
        self.visibleCount = settings.pageSize
        observer.onUpdate = { [weak self] snapshot in
            Task { @MainActor [weak self] in
                self?.networkStatus = snapshot.description
            }
        }
        observer.start()
    }

    var visible: [NewsArticle] {
        let filtered = search.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? articles
            : articles.filter {
                $0.title.localizedCaseInsensitiveContains(search)
                    || $0.summary.localizedCaseInsensitiveContains(search)
            }
        return Array(filtered.prefix(visibleCount))
    }

    var canLoadMore: Bool {
        !loading && !loadingMore && search.isEmpty
            && (visibleCount < articles.count || !exhausted)
    }

    func start() async {
        guard !started else { return }
        started = true
        let local = await cache.load()
        if articles.isEmpty {
            articles = local
        }
        await refresh()
    }

    func refresh() async {
        guard !loading else { return }
        loading = true
        defer { loading = false }

        do {
            let fresh = try await repository.load(settings.feedURL)
            articles = FeedRepository.unique(fresh, adding: articles)
            visibleCount = settings.pageSize
            nextPage = 2
            exhausted = false
            consecutiveDuplicates = 0
            await cache.save(articles)
        } catch {
            let original = error.localizedDescription
            if let problem = error as? FeedFailure, problem.requiresConnectivityDiagnosis {
                let webWorks = await diagnostics.webAvailableAfterFeedFailure()
                alertMessage = webWorks
                    ? "La conexión HTTPS general funciona, pero el feed no responde: \(original). Puede tratarse de una incidencia del servidor."
                    : "No se ha podido comprobar el acceso general a HTTPS: \(original). Compruebe la conexión o inténtelo de nuevo."
            } else {
                alertMessage = original
            }
        }
    }

    func loadMore() async {
        guard canLoadMore else { return }
        if visibleCount < articles.count {
            visibleCount = min(visibleCount + settings.pageSize, articles.count)
            return
        }
        guard let url = settings.nextPageURL(
            page: nextPage,
            olderThan: articles.compactMap(\.publicationDate).min()
        ) else {
            exhausted = true
            return
        }
        loadingMore = true
        defer { loadingMore = false }
        do {
            let page = try await repository.load(url)
            let before = articles.count
            articles = FeedRepository.unique(articles, adding: page)
            let added = articles.count - before
            if added == 0 {
                consecutiveDuplicates += 1
                if consecutiveDuplicates >= 2 { exhausted = true }
            } else {
                consecutiveDuplicates = 0
                await cache.save(articles)
            }
            nextPage += 1
            visibleCount = min(visibleCount + settings.pageSize, articles.count)
        } catch {
            alertMessage = "No se pudieron cargar noticias anteriores: \(error.localizedDescription)"
        }
    }

    func runDiagnostics() async {
        guard diagnosticMessage == nil else { return }
        let report = await diagnostics.diagnose()
        diagnosticMessage = """
        HTTP(S): \(report.https ? "Accesible" : "Sin respuesta")
        DNS: \(report.dns ? "Responde" : "Sin respuesta")
        TCP: \(report.tcp ? "Conecta" : "Sin respuesta")
        TLS: \(report.tls ? "Conecta" : "Sin respuesta")
        NTP: \(report.ntp ? "Responde" : "Bloqueado o no disponible")
        Tiempo: \(String(format: "%.1f", report.elapsed)) s

        \(report.https ? "Hay acceso web HTTPS general. Esto no garantiza que el feed funcione." : "No se ha confirmado acceso web general. DNS/TCP por sí solos no prueban Internet HTTPS.")
        """
    }

    func dismissDiagnostics() { diagnosticMessage = nil }
}
