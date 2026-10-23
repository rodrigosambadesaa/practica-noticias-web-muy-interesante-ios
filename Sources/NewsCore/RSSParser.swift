import Foundation
#if canImport(FoundationXML)
import FoundationXML
#endif

public enum RSSParseError: Error, LocalizedError {
    case malformedXML, emptyFeed
    public var errorDescription: String? {
        switch self {
        case .malformedXML: return "El servidor ha devuelto un RSS/XML no válido."
        case .emptyFeed: return "El feed no contiene artículos utilizables."
        }
    }
}

public enum RSSParser {
    public static func parse(_ data: Data) throws -> [NewsArticle] {
        let delegate = RSSDelegate()
        let parser = XMLParser(data: data)
        parser.shouldResolveExternalEntities = false
        parser.delegate = delegate
        guard parser.parse() else { throw RSSParseError.malformedXML }
        guard !delegate.articles.isEmpty else { throw RSSParseError.emptyFeed }
        return delegate.articles
    }
}

private final class RSSDelegate: NSObject, XMLParserDelegate {
    private struct Draft {
        var title = ""
        var description = ""
        var link = ""
        var image = ""
        var date = ""
        var imagePriority = 0
    }

    private(set) var articles: [NewsArticle] = []
    private var depth = 0
    private var itemDepth = -1
    private var fieldDepth = -1
    private var field = ""
    private var text = ""
    private var draft: Draft?
    private let dateFormats = [
        "EEE, dd MMM yyyy HH:mm:ss Z",
        "EEE, dd MMM yyyy HH:mm:ss zzz",
        "yyyy-MM-dd'T'HH:mm:ssXXXXX",
        "yyyy-MM-dd'T'HH:mm:ss'Z'"
    ]

    func parser(_ parser: XMLParser, didStartElement elementName: String,
                namespaceURI: String?, qualifiedName qName: String?,
                attributes attributeDict: [String : String] = [:]) {
        depth += 1
        let name = elementName.lowercased()
        let local = name.split(separator: ":").last.map(String.init) ?? name
        if (name == "item" || name == "entry") && draft == nil {
            itemDepth = depth
            draft = Draft()
        } else if draft != nil && depth == itemDepth + 1 {
            if local == "enclosure" || local == "thumbnail" || local == "content" {
                let priority = local == "enclosure" ? 3 : local == "content" ? 2 : 1
                let type = attributeDict["type"] ?? ""
                if let candidate = attributeDict["url"], !candidate.isEmpty,
                   (type.isEmpty || type.hasPrefix("image/")),
                   priority >= (draft?.imagePriority ?? 0) {
                    draft?.image = candidate
                    draft?.imagePriority = priority
                }
            }
            if local == "link", let href = attributeDict["href"] {
                draft?.link = href
            }
            if ["title", "description", "summary", "link", "pubdate", "published", "updated", "date", "encoded"].contains(local) {
                field = local
                fieldDepth = depth
                text = ""
            }
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        if fieldDepth > 0 { text += string }
    }
    func parser(_ parser: XMLParser, foundCDATA CDATABlock: Data) {
        if fieldDepth > 0 { text += String(data: CDATABlock, encoding: .utf8) ?? "" }
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String,
                namespaceURI: String?, qualifiedName qName: String?) {
        let local = elementName.lowercased().split(separator: ":").last.map(String.init) ?? elementName.lowercased()
        if fieldDepth == depth, draft != nil {
            let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
            switch field {
            case "title": draft?.title = value
            case "description", "summary", "encoded":
                if draft?.description.isEmpty == true || field == "encoded" { draft?.description = value }
            case "link": if draft?.link.isEmpty == true { draft?.link = value }
            case "pubdate", "date", "published", "updated": draft?.date = value
            default: break
            }
            fieldDepth = -1
            field = ""
            text = ""
        }
        if depth == itemDepth && (local == "item" || local == "entry") {
            if let draft, let url = URL(string: HTMLText.decode(draft.link)),
               ["https", "http"].contains(url.scheme?.lowercased() ?? ""),
               !draft.title.isEmpty {
                let image = imageURL(for: draft)
                let date = parseDate(draft.date)
                articles.append(NewsArticle(title: draft.title, summary: draft.description,
                                           url: url, imageURL: image, publicationDate: date))
            }
            draft = nil
            itemDepth = -1
        }
        depth -= 1
    }

    private func imageURL(for draft: Draft) -> URL? {
        var candidate = draft.image
        if candidate.isEmpty, let regex = try? NSRegularExpression(pattern: #"<img\b[^>]*?\bsrc\s*=\s*["']([^"']+)["']"#, options: [.caseInsensitive]) {
            let html = draft.description
            let range = NSRange(html.startIndex..<html.endIndex, in: html)
            if let match = regex.firstMatch(in: html, range: range),
               let matchRange = Range(match.range(at: 1), in: html) {
                candidate = String(html[matchRange])
            }
        }
        let decoded = HTMLText.decode(candidate)
        guard let url = URL(string: decoded),
              ["https", "http"].contains(url.scheme?.lowercased() ?? "") else { return nil }
        return url
    }

    private func parseDate(_ raw: String) -> Date? {
        for pattern in dateFormats {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.dateFormat = pattern
            formatter.isLenient = false
            if let date = formatter.date(from: raw) { return date }
        }
        return ISO8601DateFormatter().date(from: raw)
    }
}
