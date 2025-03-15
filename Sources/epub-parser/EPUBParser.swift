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

    private var cachedChapters: [EPUBChapter] = []

    // MARK: - Initialization

    /// Initialize with the path to an EPUB file
    /// - Parameters:
    ///   - epubPath: Path to the EPUB file
    ///   - identifier: Unique identifier for this EPUB processing operation
    ///   - cacheDirectory: Optional custom directory for unzipping, defaults to documents directory
    public init(epubPath: URL, identifier: String = UUID().uuidString, cacheDirectory: URL? = nil) {
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

    deinit {
        cleanup()
    }

    // MARK: - Accessors

    /// Get all chapters in the EPUB
    /// - Returns: Array of EPUBChapter objects
    public func chapters() -> [EPUBChapter] {
        return cachedChapters
    }

    // MARK: - Public Methods

    /// Process the EPUB file and extract its chapters
    /// - Returns: Array of EPUBChapter objects representing the chapters
    public func processEPUB() throws {
        // Step 1: Unzip the EPUB file if not already unzipped
        // This extracts the EPUB contents to the designated directory
        try unzipIfNeeded()

        // Step 2: Locate the content.opf file by parsing container.xml
        // container.xml indicates where the primary OPF file is located
        let containerXML = unzipDestination.appendingPathComponent("META-INF/container.xml")
        guard let contentOPFPath = parseContainerXML(at: containerXML) else {
            throw EPUBParserError.contentOPFNotFound
        }

        // Step 3: Set the OPF root directory as base for relative paths
        // and locate the toc.ncx file which contains the table of contents
        opfRootURL = contentOPFPath.deletingLastPathComponent()
        tocURL = try findTocNCX(opfURL: contentOPFPath)

        // Step 4: Parse all manifest items from the OPF file
        // These represent all resources (HTML files, images, etc.) in the EPUB
        let manifestItems = try parseManifestItems(opfURL: contentOPFPath)

        // Step 5: Parse the table of contents to get chapter information
        guard let tocPath = tocURL else {
            throw EPUBParserError.tocNCXNotFound
        }

        // Get basic chapter information from the NCX file
        let basicChapters = try parseChapters(at: tocPath)

        // Step 6: Enhance basic chapters with their associated manifest items
        // This creates a hierarchical structure connecting chapters to their content
        var chapters: [EPUBChapter] = []

        for (index, chapter) in basicChapters.enumerated() {
            // Look ahead to find the next chapter boundary
            let nextChapter = basicChapters.element(at: index + 1)
            var chapter = chapter
            // var items: [EPUBManifestItem] = []

            // Find the starting manifest item for this chapter
            if var j = manifestItems.firstIndex(where: { $0.path == chapter.path }) {
                chapter.manifestItems.append(manifestItems[j])

                // Add all subsequent items until the next chapter's starting item
                while j < manifestItems.count - 1 {
                    j += 1

                    if manifestItems[j].path == nextChapter?.path {
                        break
                    }

                    chapter.manifestItems.append(manifestItems[j])
                }
            }

            // Skip chapters with no associated content
            guard !chapter.manifestItems.isEmpty else {
                print("No manifest items found for chapter \(chapter.id)")
                continue
            }

            chapters.append(chapter)
        }

        // Store the processed chapters in the cache
        cachedChapters = chapters
    }

    /// Get the base URL for resolving relative paths in this EPUB
    /// - Returns: The OPF root URL if available, or the unzip destination
    public func baseURL() -> URL {
        return opfRootURL ?? unzipDestination
    }

    /// Get the chapter by ID
    /// - Parameter id: The chapter id
    /// - Returns: EPUBChapter object
    public func chapter(id: String) throws -> EPUBChapter {
        guard let chapter = cachedChapters.first(where: { $0.id == id }) else {
            throw EPUBParserError.chapterNotFound(id: id)
        }

        return chapter
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

    private func parseChapters(at tocURL: URL) throws -> [EPUBChapter] {
        let parser = TOCNCXParser()
        return try parser.parseNCX(at: tocURL)
    }

    private func parseManifestItems(opfURL: URL) throws -> [EPUBManifestItem] {
        let manifestParser = ManifestParser(baseURL: opfURL.deletingLastPathComponent())
        return try manifestParser.parseManifest(at: opfURL)
    }
}

extension Array {
    func element(at: Int) -> Element? {
        guard at >= 0, at < count else { return nil }
        return self[at]
    }
}
