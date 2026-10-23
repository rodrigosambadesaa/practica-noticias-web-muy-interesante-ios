import XCTest
@testable import NewsCore

final class NewsCoreTests: XCTestCase {
    private let sample = """
    <?xml version="1.0" encoding="utf-8"?>
    <rss version="2.0" xmlns:media="http://search.yahoo.com/mrss/">
    <channel><title>Noticias</title><item>
    <title>El &amp;#039;pecho de paloma&amp;#039; y el caf&amp;eacute;</title>
    <description><![CDATA[<p>Madrid &amp; m&aacute;s</p><img src="https://example.com/photo.jpg"/>]]></description>
    <link>https://example.com/story</link>
    <pubDate>Tue, 20 Oct 2026 16:42:00 +0000</pubDate>
    <media:thumbnail url="https://example.com/image.jpg"/>
    </item></channel></rss>
    """

    func testNewsModelDecodesEscapedHeadlinesAndKeepsURL() throws {
        let articles = try RSSParser.parse(Data(sample.utf8))
        XCTAssertEqual(articles.count, 1)
        XCTAssertEqual(articles[0].title, "El 'pecho de paloma' y el café")
        XCTAssertEqual(articles[0].url.absoluteString, "https://example.com/story")
        XCTAssertEqual(articles[0].imageURL?.absoluteString, "https://example.com/image.jpg")
        XCTAssertTrue(articles[0].summary.contains("Madrid & más"))
        XCTAssertNotNil(articles[0].publicationDate)
    }

    func testNumericAndNamedHTMLEntities() {
        XCTAssertEqual(HTMLText.decode("&#039; &quot; &amp; &ntilde; &#x1F600;"),
                       "' \" & ñ 😀")
        XCTAssertEqual(HTMLText.decode("&amp;#039;"), "'")
        XCTAssertEqual(HTMLText.decode("A & B &unknown;"), "A & B &unknown;")
    }

    func testErrorOnInvalidRSS() {
        XCTAssertThrowsError(try RSSParser.parse(Data("<rss><item>".utf8)))
    }

    func testTransportHTTPClassificationAndNoRedundantPreflight() async throws {
        let url = URL(string: "https://example.com/feed")!
        let repository = FeedRepository(transport: StubTransport(payload: Data(sample.utf8), status: 200))
        let articles = try await repository.load(url)
        XCTAssertEqual(articles.count, 1)

        do {
            let unavailable = FeedRepository(transport: StubTransport(payload: Data(), status: 503))
            _ = try await unavailable.load(url)
            XCTFail("503 must not count as a connectivity failure")
        } catch let error as FeedFailure {
            XCTAssertEqual(error, .httpStatus(503))
            XCTAssertFalse(error.requiresConnectivityDiagnosis)
        }
    }

    func testNoDuplicateArticles() throws {
        let articles = try RSSParser.parse(Data(sample.utf8))
        let unique = FeedRepository.unique(articles, adding: articles)
        XCTAssertEqual(unique.count, 1)
    }

    func testArchivePagination() {
        let config = FeedSettings(displayName: "Marca",
                                  feedURL: URL(string: "https://example.com/feed")!,
                                  archive: .appendPage("https://example.com/feed?page="))
        XCTAssertEqual(config.nextPageURL(page: 2, olderThan: nil)?.absoluteString,
                       "https://example.com/feed?page=2")
    }
}

private struct StubTransport: FeedTransport {
    let payload: Data
    let status: Int
    func retrieve(_ url: URL) async throws -> (Data, Int) { (payload, status) }
}
