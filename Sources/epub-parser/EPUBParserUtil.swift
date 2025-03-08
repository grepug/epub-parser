import Foundation
import ZIPFoundation

/// Standalone utility for parsing EPUB files
public class EPUBParser {
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
