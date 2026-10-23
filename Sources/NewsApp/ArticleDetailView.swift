import SwiftUI
import WebKit
import NewsCore

struct ArticleDetailView: View {
    let article: NewsArticle
    @Environment(\.openURL) private var openURL

    var body: some View {
        VStack(spacing: 0) {
            WebArticle(url: article.url)
            Divider()
            HStack {
                Button("Navegador") { openURL(article.url) }
                Spacer()
                ShareLink(item: article.url, subject: Text(article.title)) {
                    Label("Compartir", systemImage: "square.and.arrow.up")
                }
            }
            .padding()
        }
        .navigationTitle(article.title)
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct WebArticle: UIViewRepresentable {
    let url: URL

    func makeUIView(context: Context) -> WKWebView {
        let view = WKWebView(frame: .zero)
        view.allowsBackForwardNavigationGestures = true
        view.load(URLRequest(url: url))
        return view
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        // Never reload on unrelated SwiftUI render passes.
    }
}
