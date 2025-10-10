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

    private var cachedDocument: EPUBDocument? = nil

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

    /// Get the parsed EPUB document
    /// - Returns: EPUBDocument object containing all parsed information
    public func document() -> EPUBDocument? {
        return cachedDocument
    }

    // MARK: - Public Methods

    /// Process the EPUB file and extract its structure
    /// - Returns: EPUBDocument containing metadata, manifest, spine, and table of contents
    @discardableResult
    public func processEPUB() throws -> EPUBDocument {
        // Step 1: Unzip the EPUB file if not already unzipped
        try unzipIfNeeded()

        // Step 2: Locate the content.opf file by parsing container.xml
        var actualBaseURL = unzipDestination
        var containerXML = unzipDestination.appendingPathComponent("META-INF/container.xml")

        // Resolve the EPUB directory structure
        let directoryResolver = EPUBDirectoryResolver()
        let structureResult = directoryResolver.resolveEPUBStructure(from: unzipDestination)
        actualBaseURL = structureResult.baseURL
        containerXML = structureResult.containerXMLURL

        guard let contentOPFPath = parseContainerXML(at: containerXML, baseURL: actualBaseURL) else {
            throw EPUBParserError.contentOPFNotFound
        }

        // Step 3: Set the OPF root directory as base for relative paths
        opfRootURL = contentOPFPath.deletingLastPathComponent()

        // Step 4: Parse metadata from the OPF file
        var metadata = try parseMetadata(opfURL: contentOPFPath)

        // Step 5: Parse all manifest items from the OPF file
        let manifestItems = try parseManifestItems(opfURL: contentOPFPath)

        // Step 5.5: Find cover image and update metadata
        let coverImageURL = findCoverImage(in: manifestItems, baseURL: contentOPFPath.deletingLastPathComponent())
        if let coverURL = coverImageURL {
            metadata = EPUBMetadata(
                title: metadata.title,
                creators: metadata.creators,
                contributors: metadata.contributors,
                language: metadata.language,
                identifier: metadata.identifier,
                publisher: metadata.publisher,
                date: metadata.date,
                description: metadata.description,
                subjects: metadata.subjects,
                rights: metadata.rights,
                type: metadata.type,
                source: metadata.source,
                coverage: metadata.coverage,
                coverImageURL: coverURL
            )
        }

        // Step 6: Parse spine (reading order)
        let spineItems = try parseSpine(opfURL: contentOPFPath, manifestItems: manifestItems)

        // Step 7: Parse table of contents
        tocURL = try findTocNCX(opfURL: contentOPFPath)
        guard let tocPath = tocURL else {
            throw EPUBParserError.tocNCXNotFound
        }
        let tableOfContents = try parseTableOfContents(at: tocPath)

        // Step 8: Create and cache the EPUBDocument
        let document = EPUBDocument(
            metadata: metadata,
            manifest: manifestItems,
            spine: spineItems,
            tableOfContents: tableOfContents,
            baseURL: opfRootURL ?? unzipDestination
        )

        cachedDocument = document
        return document
    }

    /// Get the base URL for resolving relative paths in this EPUB
    /// - Returns: The OPF root URL if available, or the unzip destination
    public func baseURL() -> URL {
        return opfRootURL ?? unzipDestination
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

    private func parseContainerXML(at url: URL, baseURL: URL? = nil) -> URL? {
        guard fileManager.fileExists(atPath: url.path) else { return nil }

        let parser = ContainerXMLParser()
        return parser.parseContainerXML(at: url, baseURL: baseURL ?? unzipDestination)
    }

    private func findTocNCX(opfURL: URL) throws -> URL {
        let opfParser = OPFParser()
        let ncxPath = try opfParser.parseOPF(at: opfURL)

        let rootURL = opfURL.deletingLastPathComponent()
        return URL(string: ncxPath, relativeTo: rootURL) ?? rootURL.appendingPathComponent(ncxPath)
    }

    private func parseTableOfContents(at tocURL: URL) throws -> [EPUBTOCItem] {
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

    private func parseSpine(opfURL: URL, manifestItems: [EPUBManifestItem]) throws -> [EPUBSpineItem] {
        let spineParser = SpineParser(manifestItems: manifestItems)
        return try spineParser.parseSpine(at: opfURL)
    }

    private func parseMetadata(opfURL: URL) throws -> EPUBMetadata {
        let metadataParser = MetadataParser()
        return try metadataParser.parseMetadata(at: opfURL)
    }

    private func findCoverImage(in manifestItems: [EPUBManifestItem], baseURL: URL) -> URL? {
        // Strategy 1: Look for item with id="cover-image" or id="cover"
        if let coverItem = manifestItems.first(where: {
            $0.id.lowercased() == "cover-image" || $0.id.lowercased() == "cover" || $0.id.lowercased().contains("cover") && $0.mediaType.hasPrefix("image/")
        }) {
            return URL(string: coverItem.path, relativeTo: baseURL) ?? baseURL.appendingPathComponent(coverItem.path)
        }

        // Strategy 2: Look for properties="cover-image"
        if let coverItem = manifestItems.first(where: {
            $0.properties["properties"]?.contains("cover-image") == true
        }) {
            return URL(string: coverItem.path, relativeTo: baseURL) ?? baseURL.appendingPathComponent(coverItem.path)
        }

        // Strategy 3: Look for first image in manifest
        if let firstImage = manifestItems.first(where: { $0.mediaType.hasPrefix("image/") }) {
            return URL(string: firstImage.path, relativeTo: baseURL) ?? baseURL.appendingPathComponent(firstImage.path)
        }

        return nil
    }
}

extension Array {
    func element(at: Int) -> Element? {
        guard at >= 0, at < count else { return nil }
        return self[at]
    }
}
