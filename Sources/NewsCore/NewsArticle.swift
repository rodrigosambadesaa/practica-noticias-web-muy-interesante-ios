import Foundation

public struct NewsArticle: Codable, Equatable, Identifiable, Sendable {
    public let title: String
    public let summary: String
    public let url: URL
    public let imageURL: URL?
    public let publicationDate: Date?

    public var id: String { url.absoluteString }

    public init(title: String, summary: String, url: URL, imageURL: URL?, publicationDate: Date?) {
        self.title = HTMLText.decode(title)
        self.summary = HTMLText.plainText(summary)
        self.url = url
        self.imageURL = imageURL
        self.publicationDate = publicationDate
    }
}

public enum HTMLText {
    private static let names: [String: String] = [
        "amp": "&", "quot": "\"", "apos": "'", "lt": "<", "gt": ">",
        "nbsp": " ", "laquo": "«", "raquo": "»", "hellip": "…",
        "ndash": "–", "mdash": "—", "lsquo": "‘", "rsquo": "’",
        "ldquo": "“", "rdquo": "”", "bull": "•", "euro": "€",
        "copy": "©", "reg": "®", "trade": "™", "ntilde": "ñ",
        "Ntilde": "Ñ", "aacute": "á", "eacute": "é", "iacute": "í",
        "oacute": "ó", "uacute": "ú", "Aacute": "Á", "Eacute": "É",
        "Iacute": "Í", "Oacute": "Ó", "Uacute": "Ú", "iquest": "¿",
        "iexcl": "¡", "uuml": "ü", "Uuml": "Ü", "ccedil": "ç"
    ]
    private static let reference = try! NSRegularExpression(
        pattern: "&(#(?:[xX][0-9A-Fa-f]{1,8}|[0-9]{1,10})|[A-Za-z][A-Za-z0-9]{1,31});"
    )
    private static let tags = try! NSRegularExpression(pattern: "<[^>]+>")

    public static func decode(_ input: String) -> String {
        var text = input
        // XMLParser already handles XML entities. Publishers sometimes double-escape HTML.
        for _ in 0..<2 {
            let range = NSRange(text.startIndex..<text.endIndex, in: text)
            let matches = reference.matches(in: text, range: range)
            guard !matches.isEmpty else { break }
            var output = text
            var changed = false
            for match in matches.reversed() {
                guard let keyRange = Range(match.range(at: 1), in: text),
                      let fullRange = Range(match.range, in: output),
                      let value = resolve(String(text[keyRange])) else { continue }
                output.replaceSubrange(fullRange, with: value)
                changed = true
            }
            text = output
            if !changed { break }
        }
        return text.replacingOccurrences(of: "\u{00A0}", with: " ")
    }

    public static func plainText(_ html: String) -> String {
        let decoded = decode(html)
        let range = NSRange(decoded.startIndex..<decoded.endIndex, in: decoded)
        let withoutTags = tags.stringByReplacingMatches(in: decoded, range: range, withTemplate: " ")
        return withoutTags.replacingOccurrences(of: "\\s+", with: " ",
                                                  options: .regularExpression).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func resolve(_ reference: String) -> String? {
        guard reference.hasPrefix("#") else { return names[reference] }
        let hex = reference.hasPrefix("#x") || reference.hasPrefix("#X")
        let digits = String(reference.dropFirst(hex ? 2 : 1))
        guard let value = UInt32(digits, radix: hex ? 16 : 10),
              value > 0, value <= 0x10FFFF, !(0xD800...0xDFFF).contains(value),
              value >= 32 else { return nil }
        return UnicodeScalar(value).map(String.init)
    }
}

public enum ArchiveStrategy: Sendable {
    case none
    case appendPage(String)
    case googleBefore
}

public struct FeedSettings: Sendable {
    public let displayName: String
    public let feedURL: URL
    public let archive: ArchiveStrategy
    public let pageSize: Int

    public init(displayName: String, feedURL: URL, archive: ArchiveStrategy, pageSize: Int = 20) {
        self.displayName = displayName
        self.feedURL = feedURL
        self.archive = archive
        self.pageSize = pageSize
    }

    public func nextPageURL(page: Int, olderThan: Date?) -> URL? {
        switch archive {
        case .none: return nil
        case .appendPage(let prefix): return URL(string: prefix + String(page))
        case .googleBefore:
            guard let olderThan else { return nil }
            let day = DateFormatter()
            day.locale = Locale(identifier: "en_US_POSIX")
            day.timeZone = TimeZone(secondsFromGMT: 0)
            day.dateFormat = "yyyy-MM-dd"
            let date = day.string(from: olderThan)
            let query = "site:publico.es before:\(date)"
            var components = URLComponents(string: "https://news.google.com/rss/search")
            components?.queryItems = [
                URLQueryItem(name: "q", value: query),
                URLQueryItem(name: "hl", value: "es"),
                URLQueryItem(name: "gl", value: "ES"),
                URLQueryItem(name: "ceid", value: "ES:es")
            ]
            return components?.url
        }
    }
}
