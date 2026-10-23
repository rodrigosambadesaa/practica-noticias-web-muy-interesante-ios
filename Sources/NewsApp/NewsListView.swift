import SwiftUI
import NewsCore

struct NewsListView: View {
    @ObservedObject var viewModel: NewsViewModel

    var body: some View {
        NavigationStack {
            Group {
                if viewModel.visible.isEmpty && viewModel.loading {
                    ProgressView("Descargando noticias…")
                } else {
                    List {
                        Section {
                            Label(viewModel.networkStatus, systemImage: "network")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .accessibilityIdentifier("networkStatus")

                            ForEach(viewModel.visible) { article in
                                NavigationLink {
                                    ArticleDetailView(article: article)
                                } label: {
                                    NewsCard(article: article)
                                }
                            }
                            if viewModel.canLoadMore {
                                Button {
                                    Task { await viewModel.loadMore() }
                                } label: {
                                    HStack {
                                        Spacer()
                                        if viewModel.loadingMore { ProgressView() }
                                        else { Label("Cargar más noticias", systemImage: "arrow.down") }
                                        Spacer()
                                    }
                                }
                                .disabled(viewModel.loadingMore)
                            }
                        } header: {
                            Text("Últimas noticias")
                        }
                    }
                    .listStyle(.insetGrouped)
                    .refreshable { await viewModel.refresh() }
                }
            }
            .navigationTitle(viewModel.settings.displayName)
            .searchable(text: $viewModel.search, prompt: "Buscar noticias")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        Task { await viewModel.runDiagnostics() }
                    } label: { Image(systemName: "network.badge.shield.half.filled") }
                    .accessibilityLabel("Diagnosticar conexión")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        Task { await viewModel.refresh() }
                    } label: { Image(systemName: "arrow.clockwise") }
                    .disabled(viewModel.loading)
                    .accessibilityLabel("Actualizar noticias")
                }
            }
            .alert("Aviso", isPresented: Binding(
                get: { viewModel.alertMessage != nil },
                set: { if !$0 { viewModel.alertMessage = nil } }
            )) {
                Button("Aceptar", role: .cancel) { viewModel.alertMessage = nil }
            } message: {
                Text(viewModel.alertMessage ?? "")
            }
            .alert("Diagnóstico de conectividad", isPresented: Binding(
                get: { viewModel.diagnosticMessage != nil },
                set: { if !$0 { viewModel.dismissDiagnostics() } }
            )) {
                Button("Cerrar") { viewModel.dismissDiagnostics() }
            } message: {
                Text(viewModel.diagnosticMessage ?? "")
            }
            .task { await viewModel.start() }
        }
    }
}

private struct NewsCard: View {
    let article: NewsArticle

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            if let url = article.imageURL {
                AsyncImage(url: url) { image in
                    image.resizable().scaledToFill()
                } placeholder: {
                    ZStack {
                        Color.secondary.opacity(0.1)
                        Image(systemName: "newspaper").foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity)
                .frame(height: 180)
                .clipped()
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }

            if let date = article.publicationDate {
                Text(date, format: .dateTime.day().month(.wide).year().hour().minute())
                    .font(.caption).foregroundStyle(.secondary)
            }
            Text(article.title)
                .font(.headline)
                .foregroundStyle(.primary)
            if !article.summary.isEmpty {
                Text(article.summary)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
            }
        }
        .padding(.vertical, 5)
        .accessibilityElement(children: .combine)
    }
}
