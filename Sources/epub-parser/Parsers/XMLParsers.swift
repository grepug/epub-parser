import Foundation

/// Represents an item in the EPUB manifest
public struct EPUBManifestItem: Hashable, Codable, Sendable {
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

        guard let parser = XMLParser(contentsOf: url) else {
            return nil
        }
        parser.delegate = self
        parser.parse()

        guard let path = contentOPFPath else {
            return nil
        }

        // First try the direct path
        let directURL = baseURL.appendingPathComponent(path)

        if FileManager.default.fileExists(atPath: directURL.path) {
            return directURL
        }

        // Handle EPUBs with nested directory structures
        // Look for the OPF file in subdirectories if direct path doesn't work
        if let subdirURL = findOPFInSubdirectories(path: path, baseURL: baseURL) {
            return subdirURL
        }

        return nil
    }

    private func findOPFInSubdirectories(path: String, baseURL: URL) -> URL? {
        let directoryResolver = EPUBDirectoryResolver()
        return directoryResolver.findOPFInSubdirectories(opfPath: path, baseURL: baseURL)
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

        // Look for EPUB3 navigation document marked with properties="nav"
        if let navPath = items["__nav__"] {
            return navPath
        }

        // Look for EPUB3 navigation document by filename pattern
        for (_, path) in items where path.contains("nav.") && (path.hasSuffix(".xhtml") || path.hasSuffix(".html")) {
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
                // Check if this is an EPUB3 nav document
                if let properties = attributeDict["properties"], properties.contains("nav") {
                    // Store this as a potential nav document
                    items["__nav__"] = href
                }
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
    private var tocItems: [EPUBTOCItem] = []
    private var navPointStack: [(item: EPUBTOCItem, depth: Int)] = []
    private var currentElement = ""
    private var currentID = ""
    private var currentTitle = ""
    private var currentContentSrc = ""
    private var currentPlayOrder = 0
    private var isParsingNavLabel = false
    private var isParsingText = false
    private var currentDepth = 0

    func parseNCX(at url: URL) throws -> [EPUBTOCItem] {
        // Read the file content first to sanitize it
        guard let originalContent = try? String(contentsOf: url, encoding: .utf8) else {
            throw EPUBParserError.ncxParsingFailed
        }

        // Sanitize XML content to fix common issues like unescaped ampersands
        let sanitizedContent = sanitizeXMLContent(originalContent)

        // Create parser with sanitized content
        guard let sanitizedData = sanitizedContent.data(using: .utf8) else {
            throw EPUBParserError.ncxParsingFailed
        }
        let parser = XMLParser(data: sanitizedData)

        tocItems = []
        navPointStack = []
        currentDepth = 0
        parser.delegate = self

        if parser.parse() {
            return tocItems
        } else if let error = parser.parserError {
            throw error
        } else {
            throw EPUBParserError.ncxParseError
        }
    }

    /// Sanitize XML content to fix common malformed XML issues
    private func sanitizeXMLContent(_ content: String) -> String {
        var sanitized = content

        // Fix unescaped ampersands that are not part of valid XML entities
        // This regex finds & that are not followed by a valid entity name and semicolon
        let ampersandPattern = "&(?!(amp|lt|gt|quot|apos|#\\d+|#x[0-9a-fA-F]+);)"
        sanitized = sanitized.replacingOccurrences(
            of: ampersandPattern,
            with: "&amp;",
            options: .regularExpression
        )

        return sanitized
    }

    // MARK: - XMLParserDelegate

    func parser(
        _ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?,
        qualifiedName qName: String?, attributes attributeDict: [String: String] = [:]
    ) {
        currentElement = elementName

        switch elementName {
        case "navPoint":
            currentDepth += 1
            currentID = attributeDict["id"] ?? ""
            currentPlayOrder = Int(attributeDict["playOrder"] ?? "0") ?? 0
        case "navLabel":
            isParsingNavLabel = true
            currentTitle = ""  // Reset title when starting a new navLabel
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
            guard !currentID.isEmpty else {
                currentDepth -= 1
                return
            }

            var tocItem = EPUBTOCItem(
                id: currentID,
                title: currentTitle.trimmingCharacters(in: .whitespacesAndNewlines),
                playOrder: currentPlayOrder,
                href: currentContentSrc,
                children: []
            )

            // Pop all children at deeper levels and add them to this item
            while let last = navPointStack.last, last.depth > currentDepth {
                tocItem.children?.insert(navPointStack.removeLast().item, at: 0)
            }

            // Add to stack regardless of depth
            navPointStack.append((tocItem, currentDepth))

            currentID = ""
            currentTitle = ""
            currentContentSrc = ""
            currentPlayOrder = 0
            currentDepth -= 1
        case "navLabel":
            isParsingNavLabel = false
        case "text":
            isParsingText = false
        case "ncx", "navMap":
            // At the end of ncx or navMap, gather all items at depth 1 or 2 (depending on structure)
            print("🔍 [NCX Parser] \(elementName) ended. Stack count: \(navPointStack.count)")

            // Find the minimum depth in the stack
            let minDepth = navPointStack.map { $0.depth }.min() ?? 1
            print("🔍 [NCX Parser] Minimum depth in stack: \(minDepth)")

            while let last = navPointStack.last, last.depth == minDepth {
                let item = navPointStack.removeLast().item
                tocItems.insert(item, at: 0)
                print("🔍 [NCX Parser] Moved item to tocItems: \(item.title) (depth: \(last.depth))")
            }
            print("🔍 [NCX Parser] Final tocItems count: \(tocItems.count)")
        default:
            break
        }
    }
}

/// Parser for EPUB3 navigation documents (nav.xhtml)
internal class EPUB3NavParser: NSObject, XMLParserDelegate {
    private var tocItems: [EPUBTOCItem] = []
    private var navItemStack: [(item: EPUBTOCItem, depth: Int)] = []
    private var currentElement = ""
    private var currentTitle = ""
    private var currentHref = ""
    private var isParsingTOC = false
    private var isParsingLink = false
    private var chapterIndex = 0
    private var currentDepth = 0
    private var listDepth = 0

    func parseNav(at url: URL) throws -> [EPUBTOCItem] {
        guard let parser = XMLParser(contentsOf: url) else {
            throw EPUBParserError.ncxParsingFailed
        }

        tocItems = []
        navItemStack = []
        isParsingTOC = false
        chapterIndex = 0
        currentDepth = 0
        listDepth = 0
        parser.delegate = self

        if parser.parse() {
            return tocItems
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
        case "nav":
            // Check if this is the TOC navigation
            if let type = attributeDict["epub:type"], type == "toc" {
                isParsingTOC = true
            }
        case "ol", "ul":
            if isParsingTOC {
                listDepth += 1
            }
        case "li" where isParsingTOC:
            currentDepth = listDepth
        case "a" where isParsingTOC:
            isParsingLink = true
            currentHref = attributeDict["href"] ?? ""
            currentTitle = ""
        default:
            break
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        if isParsingLink {
            currentTitle += string
        }
    }

    func parser(
        _ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?,
        qualifiedName qName: String?
    ) {
        switch elementName {
        case "nav":
            isParsingTOC = false
            // At the end, gather all root level items
            while let last = navItemStack.last, last.depth == 1 {
                tocItems.insert(navItemStack.removeLast().item, at: 0)
            }
        case "ol", "ul":
            if isParsingTOC {
                listDepth -= 1
            }
        case "a" where isParsingTOC && isParsingLink:
            isParsingLink = false

            guard !currentHref.isEmpty && !currentTitle.isEmpty else { return }

            chapterIndex += 1
            var tocItem = EPUBTOCItem(
                id: "toc_\(chapterIndex)",
                title: currentTitle.trimmingCharacters(in: .whitespacesAndNewlines),
                playOrder: chapterIndex,
                href: currentHref,
                children: []
            )

            // Pop all children at deeper levels and add them to this item
            while let last = navItemStack.last, last.depth > currentDepth {
                tocItem.children?.insert(navItemStack.removeLast().item, at: 0)
            }

            navItemStack.append((tocItem, currentDepth))

            currentTitle = ""
            currentHref = ""
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

/// Parser for EPUB spine (reading order)
internal class SpineParser: NSObject, XMLParserDelegate {
    private var spineItems: [EPUBSpineItem] = []
    private var isParsingSpine = false
    private var manifestItems: [EPUBManifestItem]
    private var spineIndex = 0

    init(manifestItems: [EPUBManifestItem]) {
        self.manifestItems = manifestItems
        super.init()
    }

    func parseSpine(at url: URL) throws -> [EPUBSpineItem] {
        guard let parser = XMLParser(contentsOf: url) else {
            throw EPUBParserError.opfParsingFailed
        }

        spineItems = []
        isParsingSpine = false
        spineIndex = 0

        parser.delegate = self
        if parser.parse() {
            print("🔍 [Spine Parser] Before deduplication: \(spineItems.count) items")

            // Deduplicate spine items by ID, keeping the first occurrence
            var seenIds = Set<String>()
            var deduplicatedItems: [EPUBSpineItem] = []

            for item in spineItems {
                if !seenIds.contains(item.id) {
                    seenIds.insert(item.id)
                    deduplicatedItems.append(item)
                } else {
                    print("🔍 [Spine Parser] Removing duplicate ID: \(item.id) at original index \(item.index)")
                }
            }

            print("🔍 [Spine Parser] After deduplication: \(deduplicatedItems.count) items")

            // Update indices to be sequential after deduplication
            let finalItems = deduplicatedItems.enumerated().map { (offset, item) in
                EPUBSpineItem(
                    id: item.id,
                    index: offset,
                    linear: item.linear,
                    manifestItem: item.manifestItem
                )
            }

            return finalItems
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
        case "spine":
            isParsingSpine = true
        case "itemref" where isParsingSpine:
            guard let idref = attributeDict["idref"] else { return }

            // Find the corresponding manifest item
            guard let manifestItem = manifestItems.first(where: { $0.id == idref }) else {
                return
            }

            // Check if linear (default is true)
            let linearString = attributeDict["linear"] ?? "yes"
            let isLinear = linearString.lowercased() != "no"

            let spineItem = EPUBSpineItem(
                id: idref,
                index: spineIndex,
                linear: isLinear,
                manifestItem: manifestItem
            )

            spineItems.append(spineItem)
            spineIndex += 1
        default:
            break
        }
    }

    func parser(
        _ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?,
        qualifiedName qName: String?
    ) {
        if elementName == "spine" {
            isParsingSpine = false
        }
    }
}

/// Parser for EPUB metadata
internal class MetadataParser: NSObject, XMLParserDelegate {
    private var title: String?
    private var creators: [String] = []
    private var contributors: [String] = []
    private var language: String?
    private var identifier: String?
    private var publisher: String?
    private var date: String?
    private var bookDescription: String?
    private var subjects: [String] = []
    private var rights: String?
    private var type: String?
    private var source: String?
    private var coverage: String?

    private var currentElement = ""
    private var isParsingMetadata = false
    private var foundText = ""

    func parseMetadata(at url: URL) throws -> EPUBMetadata {
        guard let parser = XMLParser(contentsOf: url) else {
            throw EPUBParserError.opfParsingFailed
        }

        // Reset all properties
        title = nil
        creators = []
        contributors = []
        language = nil
        identifier = nil
        publisher = nil
        date = nil
        bookDescription = nil
        subjects = []
        rights = nil
        type = nil
        source = nil
        coverage = nil
        isParsingMetadata = false

        parser.delegate = self
        if parser.parse() {
            return EPUBMetadata(
                title: title,
                creators: creators,
                contributors: contributors,
                language: language,
                identifier: identifier,
                publisher: publisher,
                date: date,
                description: bookDescription,
                subjects: subjects,
                rights: rights,
                type: type,
                source: source,
                coverage: coverage,
                coverImagePath: nil  // Will be set later by EPUBParser
            )
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
        currentElement = elementName
        foundText = ""

        if elementName == "metadata" {
            isParsingMetadata = true
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        if isParsingMetadata {
            foundText += string
        }
    }

    func parser(
        _ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?,
        qualifiedName qName: String?
    ) {
        guard isParsingMetadata else { return }

        let text = foundText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }

        switch elementName {
        case "dc:title", "title":
            title = text
        case "dc:creator", "creator":
            creators.append(text)
        case "dc:contributor", "contributor":
            contributors.append(text)
        case "dc:language", "language":
            language = text
        case "dc:identifier", "identifier":
            identifier = text
        case "dc:publisher", "publisher":
            publisher = text
        case "dc:date", "date":
            date = text
        case "dc:description", "description":
            bookDescription = text
        case "dc:subject", "subject":
            subjects.append(text)
        case "dc:rights", "rights":
            rights = text
        case "dc:type", "type":
            type = text
        case "dc:source", "source":
            source = text
        case "dc:coverage", "coverage":
            coverage = text
        case "metadata":
            isParsingMetadata = false
        default:
            break
        }

        foundText = ""
    }
}
