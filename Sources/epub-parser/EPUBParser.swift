import Foundation
import ZIPFoundation

/// Standalone utility for parsing EPUB files
public actor EPUBParser {
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

        // Filter manifest items to only HTML/XHTML files for chapter content
        let htmlManifestItems = manifestItems.filter { item in
            ["application/xhtml+xml", "text/html"].contains(item.mediaType) || item.path.hasSuffix(".html") || item.path.hasSuffix(".xhtml") || item.path.hasSuffix(".htm")
        }

        for (index, chapter) in basicChapters.enumerated() {
            var chapter = chapter

            // Get the chapter's primary file path (may include fragment identifier)
            let chapterPath = chapter.path
            let chapterPathWithoutFragment = chapterPath.components(separatedBy: "#").first ?? chapterPath

            // Method 1: Direct path matching
            // Find manifest items that match this chapter's path exactly
            let exactMatchItems = htmlManifestItems.filter { item in
                normalizePathForComparison(item.path) == normalizePathForComparison(chapterPathWithoutFragment)
            }

            if !exactMatchItems.isEmpty {
                // Check if this might be a multi-file EPUB where chapters span multiple files
                // Heuristic: If we have many more HTML files than chapters, try range mapping
                let isLikelyMultiFileStructure = htmlManifestItems.count > basicChapters.count * 3

                if isLikelyMultiFileStructure && exactMatchItems.count == 1 {
                    // Try to expand this chapter to include subsequent files until the next chapter
                    let normalizedChapterPath = normalizePathForComparison(chapterPathWithoutFragment)

                    if let startIndex = htmlManifestItems.firstIndex(where: { item in
                        normalizePathForComparison(item.path) == normalizedChapterPath
                    }) {
                        let nextChapter = basicChapters.element(at: index + 1)
                        let endIndex: Int

                        if let nextChapter = nextChapter {
                            let nextChapterPathWithoutFragment = nextChapter.path.components(separatedBy: "#").first ?? nextChapter.path
                            let normalizedNextPath = normalizePathForComparison(nextChapterPathWithoutFragment)

                            if let nextStartIndex = htmlManifestItems.firstIndex(where: { item in
                                normalizePathForComparison(item.path) == normalizedNextPath
                            }) {
                                endIndex = nextStartIndex
                            } else {
                                endIndex = startIndex + 1  // Conservative fallback
                            }
                        } else {
                            // Last chapter - include remaining files, but be conservative
                            endIndex = min(startIndex + 10, htmlManifestItems.count)  // Limit to 10 files max
                        }

                        if endIndex > startIndex + 1 {
                            // We found additional content, use range mapping
                            let rangeItems = Array(htmlManifestItems[startIndex..<endIndex])
                            chapter.manifestItems = rangeItems
                            print("📚 Chapter '\(chapter.title)': Extended range (\(startIndex)..<\(endIndex)) - \(rangeItems.count) items")
                        } else {
                            // Use exact match
                            chapter.manifestItems = exactMatchItems
                            print("📄 Chapter '\(chapter.title)': Found exact match - \(exactMatchItems.count) items")
                        }
                    } else {
                        chapter.manifestItems = exactMatchItems
                        print("📄 Chapter '\(chapter.title)': Found exact match - \(exactMatchItems.count) items")
                    }
                } else {
                    chapter.manifestItems = exactMatchItems
                    print("📄 Chapter '\(chapter.title)': Found exact match - \(exactMatchItems.count) items")
                }
            } else {
                // Method 2: Sequential range mapping for chapters that span multiple files
                // This handles cases where chapters span across multiple HTML files in sequence

                let normalizedChapterPath = normalizePathForComparison(chapterPathWithoutFragment)

                // Find the starting position for this chapter
                if let startIndex = htmlManifestItems.firstIndex(where: { item in
                    normalizePathForComparison(item.path) == normalizedChapterPath
                }) {

                    // Determine the ending position by looking at the next chapter's start
                    let nextChapter = basicChapters.element(at: index + 1)
                    let endIndex: Int

                    if let nextChapter = nextChapter {
                        let nextChapterPathWithoutFragment = nextChapter.path.components(separatedBy: "#").first ?? nextChapter.path
                        let normalizedNextPath = normalizePathForComparison(nextChapterPathWithoutFragment)

                        // Find where the next chapter starts
                        if let nextStartIndex = htmlManifestItems.firstIndex(where: { item in
                            normalizePathForComparison(item.path) == normalizedNextPath
                        }) {
                            endIndex = nextStartIndex
                        } else {
                            // Next chapter not found in sequence, assume this chapter has only its primary file
                            endIndex = startIndex + 1
                        }
                    } else {
                        // This is the last chapter, include all remaining HTML files
                        endIndex = htmlManifestItems.count
                    }

                    // Add all HTML files from start to end (exclusive)
                    let rangeItems = Array(htmlManifestItems[startIndex..<endIndex])
                    chapter.manifestItems = rangeItems

                    print("📚 Chapter '\(chapter.title)': Range mapping (\(startIndex)..<\(endIndex)) - \(rangeItems.count) items")
                    if rangeItems.count > 1 {
                        print("    Multi-file chapter detected:")
                        for (i, item) in rangeItems.enumerated() {
                            print("      [\(i+1)] \(item.path)")
                        }
                    }

                } else {
                    // Method 3: Fragment-based mapping for chapters within same file
                    // This handles cases where multiple chapters exist in the same HTML file
                    if chapterPath.contains("#") {
                        // This chapter references a specific section in an HTML file
                        let baseFile = chapterPathWithoutFragment
                        let normalizedBasePath = normalizePathForComparison(baseFile)

                        if let matchingItem = htmlManifestItems.first(where: { item in
                            normalizePathForComparison(item.path) == normalizedBasePath
                        }) {
                            chapter.manifestItems = [matchingItem]
                            print("🔗 Chapter '\(chapter.title)': Fragment-based mapping - \(chapterPath)")
                        } else {
                            print("❌ Chapter '\(chapter.title)': Fragment base file not found - \(baseFile)")
                            continue
                        }
                    } else {
                        // Method 4: Fallback - try partial path matching
                        let partialMatchItems = htmlManifestItems.filter { item in
                            let itemBaseName = URL(fileURLWithPath: item.path).deletingPathExtension().lastPathComponent.lowercased()
                            let chapterBaseName = URL(fileURLWithPath: chapterPathWithoutFragment).deletingPathExtension().lastPathComponent.lowercased()
                            return itemBaseName.contains(chapterBaseName) || chapterBaseName.contains(itemBaseName)
                        }

                        if !partialMatchItems.isEmpty {
                            chapter.manifestItems = partialMatchItems
                            print("🔍 Chapter '\(chapter.title)': Partial match - \(partialMatchItems.count) items")
                        } else {
                            print("❌ Chapter '\(chapter.title)': No manifest items found")
                            print("   Chapter path: '\(chapterPath)'")
                            print("   Available HTML files: \(htmlManifestItems.prefix(3).map { $0.path })")
                            continue
                        }
                    }
                }
            }  // Skip chapters with no associated content
            guard !chapter.manifestItems.isEmpty else {
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
    nonisolated public func cleanup() {
        try? FileManager.default.removeItem(at: unzipDestination)
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

        do {
            // Try system unarchiver first (more tolerant of minor issues)
            try fileManager.unzipItem(at: sourceEPUBPath, to: unzipDestination)
        } catch {
            print("⚠️ System unarchiver failed: \(String(describing: error))")
            print("🔧 Attempting fallback to ZIPFoundation...")

            // Clean up any partial extraction
            try? fileManager.removeItem(at: unzipDestination)
            try fileManager.createDirectory(at: unzipDestination, withIntermediateDirectories: true)

            // Fallback to ZIPFoundation
            try unzipWithZIPFoundation()
        }
    }

    private func unzipWithZIPFoundation() throws {
        do {
            let archive = try Archive(url: sourceEPUBPath, accessMode: .read)

            // Extract all entries with error tolerance
            var extractedCount = 0
            var totalCount = 0

            for entry in archive {
                totalCount += 1
                do {
                    _ = try archive.extract(entry, to: unzipDestination.appendingPathComponent(entry.path))
                    extractedCount += 1
                } catch {
                    print("⚠️ Failed to extract '\(entry.path)': \(String(describing: error))")
                    // Continue with other files - don't fail the entire operation
                    continue
                }
            }

            print("📦 ZIPFoundation extraction: \(extractedCount)/\(totalCount) files extracted")

            // Check if we got the essential EPUB files
            let essentialFiles = ["META-INF/container.xml", "mimetype"]
            let missingEssential = essentialFiles.filter { file in
                !fileManager.fileExists(atPath: unzipDestination.appendingPathComponent(file).path)
            }

            if !missingEssential.isEmpty {
                print("❌ Missing essential files: \(missingEssential)")
                throw EPUBParserError.contentOPFNotFound
            }

            if extractedCount == 0 {
                throw EPUBParserError.opfParsingFailed
            }

            print("✅ ZIPFoundation fallback successful")

        } catch {
            print("❌ ZIPFoundation extraction failed: \(String(describing: error))")
            throw error
        }
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
        // Determine if this is an NCX file or EPUB3 navigation document
        if tocURL.pathExtension.lowercased() == "ncx" {
            // Use NCX parser for EPUB2
            let parser = TOCNCXParser()
            return try parser.parseNCX(at: tocURL)
        } else {
            // Use navigation parser for EPUB3
            let parser = EPUB3NavParser()
            return try parser.parseNav(at: tocURL)
        }
    }

    private func parseManifestItems(opfURL: URL) throws -> [EPUBManifestItem] {
        let manifestParser = ManifestParser(baseURL: opfURL.deletingLastPathComponent())
        return try manifestParser.parseManifest(at: opfURL)
    }

    /// Normalizes paths for comparison by removing fragments and standardizing separators
    private func normalizePathForComparison(_ path: String) -> String {
        // Remove URL fragments (everything after #)
        let pathWithoutFragment = path.components(separatedBy: "#").first ?? path

        // Remove leading slashes and normalize separators
        return
            pathWithoutFragment
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            .replacingOccurrences(of: "\\", with: "/")
            .lowercased()
    }
}

extension Array {
    func element(at: Int) -> Element? {
        guard at >= 0, at < count else { return nil }
        return self[at]
    }
}
