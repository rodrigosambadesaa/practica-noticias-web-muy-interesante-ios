import SwiftUI
import NewsCore

@main
struct NewsReaderApp: App {
    @StateObject private var viewModel = NewsViewModel(settings: AppConfiguration.settings)

    var body: some Scene {
        WindowGroup {
            NewsListView(viewModel: viewModel)
        }
    }
}
