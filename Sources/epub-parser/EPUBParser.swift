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
    private var manifestItems: [EPUBManifestItem] = []

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

    // MARK: - Accessors

    /// Get all chapters in the EPUB
    /// - Returns: Array of EPUBChapter objects
    public func chapters() -> [EPUBChapter] {
        return cachedChapters
    }

    /// Get all manifest items in the EPUB
    /// - Returns: Array of EPUBManifestItem objects
    public func manifest() -> [EPUBManifestItem] {
        return manifestItems
    }

    // MARK: - Public Methods

    /// Process the EPUB file and extract its chapters
    /// - Returns: Array of EPUBChapter objects representing the chapters
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

        // Step 4: Parse manifest items
        try parseManifestItems(opfURL: contentOPFPath)

        // Step 5: Parse toc.ncx and get chapters
        guard let tocPath = tocURL else {
            throw EPUBParserError.tocNCXNotFound
        }

        let chapterInfos = try parseChapters(at: tocPath)

        // Convert chapter infos to full chapters with manifest items
        var chapters: [EPUBChapter] = []
        for chapterInfo in chapterInfos {
            // Find manifest items for this chapter
            let items = manifestItemsForChapter(chapterInfo)

            guard !items.isEmpty else {
                print("No manifest items found for chapter \(chapterInfo.id)")
                continue
            }

            let chapter = EPUBChapter(
                id: chapterInfo.id,
                title: chapterInfo.title,
                playOrder: chapterInfo.playOrder,
                manifestItems: items
            )

            chapters.append(chapter)
        }

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

    private func parseChapters(at tocURL: URL) throws -> [EPUBChapterInfo] {
        let parser = TOCNCXParser()
        return try parser.parseNCX(at: tocURL)
    }

    private func parseManifestItems(opfURL: URL) throws {
        let manifestParser = ManifestParser(baseURL: opfURL.deletingLastPathComponent())
        manifestItems = try manifestParser.parseManifest(at: opfURL)
    }

    // MARK: - Manifest Item Helpers

    /// Find all manifest items associated with a chapter
    /// - Parameter chapterInfo: The temporary chapter info to find manifest items for
    /// - Returns: Array of manifest items belonging to this chapter
    private func manifestItemsForChapter(_ chapterInfo: EPUBChapterInfo) -> [EPUBManifestItem] {
        // Find the starting manifest item that corresponds to this chapter's content path
        let chapterContentPath = chapterInfo.contentPath

        // Extract just the filename from the content path, as manifest items often use just the filename
        let chapterFilename = chapterContentPath.components(separatedBy: "/").last ?? chapterContentPath

        // Find the starting index
        guard
            let startIndex = manifestItems.firstIndex(where: { item in
                return item.path.hasSuffix(chapterFilename)
            })
        else {
            return []
        }

        // Find the ending index (the next chapter's content path, if any)
        var endIndex = manifestItems.count

        // Find the next chapter in reading order
        let allChapterInfos = try? parseChapters(at: tocURL!)  // Get the original ordered list
        if let currentIndex = allChapterInfos?.firstIndex(where: { $0.id == chapterInfo.id }),
            let nextChapter = allChapterInfos?.element(at: currentIndex + 1)
        {
            let nextFilename = nextChapter.contentPath.components(separatedBy: "/").last ?? nextChapter.contentPath

            if let nextIndex = manifestItems.firstIndex(where: { item in
                return item.path.hasSuffix(nextFilename)
            }) {
                endIndex = nextIndex
            }
        }

        // Return the slice of manifest items that belong to this chapter
        return Array(manifestItems[startIndex..<endIndex])
    }
}

// Temporary struct for parsing before conversion to EPUBChapter
internal struct EPUBChapterInfo: Identifiable, Hashable {
    let id: String
    let title: String
    let contentPath: String
    let playOrder: Int

    var identifier: String { id }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    static func == (lhs: EPUBChapterInfo, rhs: EPUBChapterInfo) -> Bool {
        lhs.id == rhs.id
    }
}

extension Array {
    func element(at: Int) -> Element? {
        guard at >= 0, at < count else { return nil }
        return self[at]
    }
}
