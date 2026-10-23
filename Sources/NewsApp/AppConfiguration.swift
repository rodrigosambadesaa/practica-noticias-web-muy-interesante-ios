import Foundation
import NewsCore

enum AppConfiguration {
    static let settings = FeedSettings(
        displayName: "Muy Interesante",
        feedURL: URL(string: "https://www.muyinteresante.com/feed/")!,
        archive: .appendPage("https://www.muyinteresante.com/feed/?paged="),
        pageSize: 20
    )
}
