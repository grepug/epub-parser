import Foundation

/// Represents an item in the EPUB manifest
public struct EPUBManifestItem: Hashable {
    /// The unique identifier of the item
    public let id: String
    /// The path to the item
    public let path: String
    /// The media type of the item
    public let mediaType: String
    /// Any additional properties
    public let properties: [String: String]
}

/// Parser for container.xml
internal class ContainerXMLParser: NSObject, XMLParserDelegate {
    private var contentOPFPath: String?
    private var isRootFile = false
    private var baseURL: URL!

    func parseContainerXML(at url: URL, baseURL: URL) -> URL? {
        self.baseURL = baseURL
        contentOPFPath = nil

        guard let parser = XMLParser(contentsOf: url) else { return nil }
        parser.delegate = self
        parser.parse()

        guard let path = contentOPFPath else { return nil }
        return URL(string: path, relativeTo: baseURL)
    }

    func parser(
        _ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?,
        qualifiedName qName: String?, attributes attributeDict: [String: String] = [:]
    ) {
        if elementName == "rootfile" {
            isRootFile = true
            if let path = attributeDict["full-path"] {
                contentOPFPath = path
            }
        }
    }

    func parser(
        _ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?,
        qualifiedName qName: String?
    ) {
        if elementName == "rootfile" {
            isRootFile = false
        }
    }
}

/// Parser for content.opf
internal class OPFParser: NSObject, XMLParserDelegate {
    private var ncxPath: String?
    private var parsingManifest = false
    private var parsingSpine = false
    private var tocID: String?
    private var items: [String: String] = [:]

    func parseOPF(at url: URL) throws -> String {
        guard let parser = XMLParser(contentsOf: url) else {
            throw EPUBParserError.opfParsingFailed
        }

        ncxPath = nil
        tocID = nil
        items = [:]

        parser.delegate = self
        parser.parse()

        // First try to find toc from spine toc attribute
        if let tocID = tocID, let path = items[tocID] {
            return path
        }

        // Otherwise look for an item with media-type application/x-dtbncx+xml
        for (_, path) in items where path.hasSuffix(".ncx") {
            return path
        }

        throw EPUBParserError.tocNCXPathNotFound
    }

    func parser(
        _ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?,
        qualifiedName qName: String?, attributes attributeDict: [String: String] = [:]
    ) {
        switch elementName {
        case "manifest":
            parsingManifest = true
        case "spine":
            parsingSpine = true
            tocID = attributeDict["toc"]
        case "item" where parsingManifest:
            if let id = attributeDict["id"], let href = attributeDict["href"] {
                items[id] = href
            }
        default:
            break
        }
    }

    func parser(
        _ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?,
        qualifiedName qName: String?
    ) {
        switch elementName {
        case "manifest":
            parsingManifest = false
        case "spine":
            parsingSpine = false
        default:
            break
        }
    }
}

/// Parser for toc.ncx
internal class TOCNCXParser: NSObject, XMLParserDelegate {
    private var chapters: [EPUBChapterInfo] = []
    private var currentElement = ""
    private var currentID = ""
    private var currentTitle = ""
    private var currentContentSrc = ""
    private var currentPlayOrder = 0
    private var isParsingNavLabel = false
    private var isParsingText = false

    func parseNCX(at url: URL) throws -> [EPUBChapterInfo] {
        guard let parser = XMLParser(contentsOf: url) else {
            throw EPUBParserError.ncxParsingFailed
        }

        chapters = []
        parser.delegate = self

        if parser.parse() {
            return chapters
        } else if let error = parser.parserError {
            throw error
        } else {
            throw EPUBParserError.ncxParseError
        }
    }

    // MARK: - XMLParserDelegate

    func parser(
        _ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?,
        qualifiedName qName: String?, attributes attributeDict: [String: String] = [:]
    ) {
        currentElement = elementName

        switch elementName {
        case "navPoint":
            currentID = attributeDict["id"] ?? ""
            currentPlayOrder = Int(attributeDict["playOrder"] ?? "0") ?? 0
        case "navLabel":
            isParsingNavLabel = true
        case "text" where isParsingNavLabel:
            isParsingText = true
        case "content":
            currentContentSrc = attributeDict["src"] ?? ""
        default:
            break
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        if currentElement == "text" && isParsingText {
            currentTitle += string
        }
    }

    func parser(
        _ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?,
        qualifiedName qName: String?
    ) {
        switch elementName {
        case "navPoint":
            guard !currentID.isEmpty else { return }

            let chapter = EPUBChapterInfo(
                id: currentID,
                title: currentTitle.trimmingCharacters(in: .whitespacesAndNewlines),
                contentPath: currentContentSrc,
                playOrder: currentPlayOrder
            )

            chapters.append(chapter)

            currentID = ""
            currentTitle = ""
            currentContentSrc = ""
            currentPlayOrder = 0
        case "navLabel":
            isParsingNavLabel = false
        case "text":
            isParsingText = false
        default:
            break
        }
    }
}

/// Parser for EPUB manifest items
internal class ManifestParser: NSObject, XMLParserDelegate {
    private var manifestItems: [EPUBManifestItem] = []
    private var isParsingManifest = false
    private var baseURL: URL

    init(baseURL: URL) {
        self.baseURL = baseURL
        super.init()
    }

    func parseManifest(at url: URL) throws -> [EPUBManifestItem] {
        guard let parser = XMLParser(contentsOf: url) else {
            throw EPUBParserError.opfParsingFailed
        }

        manifestItems = []
        isParsingManifest = false

        parser.delegate = self
        if parser.parse() {
            return manifestItems
        } else if let error = parser.parserError {
            throw error
        } else {
            throw EPUBParserError.opfParseError
        }
    }

    // MARK: - XMLParserDelegate

    func parser(
        _ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?,
        qualifiedName qName: String?, attributes attributeDict: [String: String] = [:]
    ) {
        switch elementName {
        case "manifest":
            isParsingManifest = true
        case "item" where isParsingManifest:
            // Extract required attributes
            guard
                let id = attributeDict["id"],
                let href = attributeDict["href"],
                let mediaType = attributeDict["media-type"]
            else { return }

            // Extract optional properties and create a dictionary
            var properties: [String: String] = [:]
            for (key, value) in attributeDict where !["id", "href", "media-type"].contains(key) {
                properties[key] = value
            }

            // Create and add the manifest item
            let item = EPUBManifestItem(
                id: id,
                path: href,
                mediaType: mediaType,
                properties: properties
            )

            manifestItems.append(item)
        default:
            break
        }
    }

    func parser(
        _ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?,
        qualifiedName qName: String?
    ) {
        if elementName == "manifest" {
            isParsingManifest = false
        }
    }
}
