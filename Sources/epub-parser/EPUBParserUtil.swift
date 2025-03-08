import Foundation
import ZIPFoundation

/// Errors that can occur during EPUB parsing
public enum EPUBParserError: LocalizedError {
    case contentOPFNotFound
    case tocNCXNotFound
    case chapterNotFound(id: String)
    case htmlPathResolutionFailed
    case opfParsingFailed
    case tocNCXPathNotFound
    case ncxParsingFailed
    case ncxParseError

    public var errorDescription: String? {
        switch self {
        case .contentOPFNotFound:
            return "Failed to find content.opf path"
        case .tocNCXNotFound:
            return "TOC file not found"
        case .chapterNotFound(let id):
            return "Could not find chapter with id \(id)"
        case .htmlPathResolutionFailed:
            return "Could not resolve HTML path"
        case .opfParsingFailed:
            return "Failed to create parser for OPF"
        case .tocNCXPathNotFound:
            return "Could not find toc.ncx path"
        case .ncxParsingFailed:
            return "Failed to create parser for NCX"
        case .ncxParseError:
            return "Failed to parse NCX file"
        }
    }
}

/// A simple model to represent an EPUB chapter
public struct EPUBChapterInfo: Identifiable, Hashable {
    public let id: String
    public let title: String
    public let contentPath: String
    public let playOrder: Int

    public func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    public static func == (lhs: EPUBChapterInfo, rhs: EPUBChapterInfo) -> Bool {
        lhs.id == rhs.id
    }
}

/// A struct to represent the content of a chapter, including HTML and title
public struct ChapterContent {
    public let html: String
    public let info: EPUBChapterInfo
}

/// Standalone utility for parsing EPUB files
public class EPUBParserUtil {
    // MARK: - Constants & Properties

    private let fileManager = FileManager.default
    private let sourceEPUBPath: URL
    private let unzipDestination: URL
    private let identifier: String

    private var opfRootURL: URL? = nil
    private var tocURL: URL? = nil

    private var cachedChapters: [EPUBChapterInfo] = []

    // MARK: - Initialization

    /// Initialize with the path to an EPUB file
    /// - Parameters:
    ///   - epubPath: Path to the EPUB file
    ///   - identifier: Unique identifier for this EPUB processing operation
    ///   - cacheDirectory: Optional custom directory for unzipping, defaults to documents directory
    public init(epubPath: URL, identifier: String, cacheDirectory: URL? = nil) {
        self.sourceEPUBPath = epubPath
        self.identifier = identifier

        // Determine unzip destination
        if let customDir = cacheDirectory {
            self.unzipDestination = customDir.appendingPathComponent("epub_\(identifier)", isDirectory: true)
        } else {
            let docDir = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
            self.unzipDestination = docDir.appendingPathComponent("epubUnzip/\(identifier)", isDirectory: true)
        }
    }

    // MARK: - Public Methods

    /// Process the EPUB file and extract its chapters
    /// - Returns: Array of EPUBChapterInfo objects representing the chapters
    public func processEPUB() throws {
        // Step 1: Unzip the EPUB if needed
        try unzipIfNeeded()

        // Step 2: Locate the content.opf file
        let containerXML = unzipDestination.appendingPathComponent("META-INF/container.xml")
        guard let contentOPFPath = parseContainerXML(at: containerXML) else {
            throw EPUBParserError.contentOPFNotFound
        }

        // Step 3: Set the OPF root and find toc.ncx
        opfRootURL = contentOPFPath.deletingLastPathComponent()
        tocURL = try findTocNCX(opfURL: contentOPFPath)

        // Step 4: Parse toc.ncx and get chapters
        guard let tocPath = tocURL else {
            throw EPUBParserError.tocNCXNotFound
        }

        let chapters = try parseChapters(at: tocPath)

        cachedChapters = chapters
    }

    /// Get the full path to the HTML file for a specific chapter
    /// - Parameter chapter: The chapter info
    /// - Returns: URL to the HTML file
    public func htmlPathForChapter(id: String) -> URL? {
        guard let opfRoot = opfRootURL else { return nil }

        // Find the chapter with the given id
        // Find the chapter with the given id from the cached chapters
        guard let chapter = cachedChapters.first(where: { $0.id == id }) else {
            return nil
        }

        // Use chapter.contentPath since it contains the actual path to the HTML file
        if chapter.contentPath.starts(with: "/") {
            // Absolute path within EPUB
            return unzipDestination.appendingPathComponent(String(chapter.contentPath.dropFirst()))
        } else {
            // Relative to OPF directory
            return URL(string: chapter.contentPath, relativeTo: opfRoot)
        }
    }

    /// Get the HTML content and title for a chapter
    /// - Parameter id: The chapter id
    /// - Returns: ChapterContent containing HTML content and title
    public func chapterContent(id: String) throws -> ChapterContent {
        guard let chapter = cachedChapters.first(where: { $0.id == id }) else {
            throw EPUBParserError.chapterNotFound(id: id)
        }

        guard let htmlPath = htmlPathForChapter(id: id) else {
            throw EPUBParserError.htmlPathResolutionFailed
        }

        let htmlContent = try String(contentsOf: htmlPath, encoding: .utf8)
        return ChapterContent(html: htmlContent, info: chapter)
    }

    /// Clean up unzipped content to free disk space
    public func cleanup() {
        try? fileManager.removeItem(at: unzipDestination)
    }

    // MARK: - Private Methods

    private func unzipIfNeeded() throws {
        // Check if already unzipped
        if fileManager.fileExists(atPath: unzipDestination.path) {
            return
        }

        // Create directory if needed
        try fileManager.createDirectory(
            at: unzipDestination,
            withIntermediateDirectories: true)

        // Unzip the EPUB file
        try fileManager.unzipItem(at: sourceEPUBPath, to: unzipDestination)
    }

    private func parseContainerXML(at url: URL) -> URL? {
        guard fileManager.fileExists(atPath: url.path) else { return nil }

        let parser = ContainerXMLParser()
        return parser.parseContainerXML(at: url, baseURL: unzipDestination)
    }

    private func findTocNCX(opfURL: URL) throws -> URL {
        let opfParser = OPFParser()
        let ncxPath = try opfParser.parseOPF(at: opfURL)

        let rootURL = opfURL.deletingLastPathComponent()
        return URL(string: ncxPath, relativeTo: rootURL) ?? rootURL.appendingPathComponent(ncxPath)
    }

    private func parseChapters(at tocURL: URL) throws -> [EPUBChapterInfo] {
        let parser = TOCNCXParser()
        return try parser.parseNCX(at: tocURL)
    }
}

// MARK: - Helper Parsers

/// Parser for container.xml
private class ContainerXMLParser: NSObject, XMLParserDelegate {
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
private class OPFParser: NSObject, XMLParserDelegate {
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
private class TOCNCXParser: NSObject, XMLParserDelegate {
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

            assert(chapter.playOrder != 0, "Invalid playOrder for chapter \(chapter.title)")

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

// MARK: - Usage Example

/*
Example usage:

do {
    let epubPath = URL(fileURLWithPath: "/path/to/book.epub")
    let parser = EPUBParserUtil(epubPath: epubPath, identifier: "uniqueID123")

    // Process and get chapters
    let chapters = try parser.processEPUB()

    // Print chapter list
    for chapter in chapters {
        print("Chapter: \(chapter.title)")

        // Get HTML content
        if let html = try? parser.htmlContentForChapter(chapter) {
            print("HTML content length: \(html.count) characters")
        }
    }

    // Clean up when done
    parser.cleanup()
} catch {
    print("Error processing EPUB: \(error)")
}
*/
