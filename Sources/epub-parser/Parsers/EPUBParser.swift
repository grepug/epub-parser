import Foundation
import ZIPFoundation

/// Standalone utility for parsing EPUB files
public actor EPUBParser {
    // MARK: - Constants & Properties

    private let fileManager = FileManager.default
    private let sourceEPUBPath: URL?
    let unzipDestination: URL
    private let isPreUnzipped: Bool
    private let shouldCleanup: Bool
    private let skipUnzipIfDirectoryExists: Bool

    private var opfRootURL: URL? = nil
    private var tocURL: URL? = nil

    private var cachedDocument: EPUBDocument? = nil

    // MARK: - Static Methods

    public static func parse(
        destinationURL: URL,
        epubSourceURL: URL? = nil,
        cleanup: Bool = false
    ) async throws -> EPUBDocument {
        let parser: EPUBParser

        if let epubSourceURL {
            parser = EPUBParser(
                epubPath: epubSourceURL,
                destinationURL: destinationURL,
                skipUnzipIfDirectoryExists: true,
                cleanup: cleanup
            )
        } else {
            parser = try EPUBParser(
                unzippedPath: destinationURL,
                cleanup: cleanup
            )
        }

        let document = try await parser.processEPUB()

        assert(document.spineItems.isEmpty == false)

        return document
    }

    // MARK: - Initialization

    /// Initialize with the path to an EPUB file
    /// - Parameters:
    ///   - epubPath: Path to the EPUB file
    ///   - destinationURL: Custom destination URL for unzipping the EPUB
    ///   - skipUnzipIfDirectoryExists: Whether to skip unzipping if directory already exists
    ///   - cleanup: Whether to automatically cleanup unzipped files in deinit (defaults to false)
    init(
        epubPath: URL,
        destinationURL: URL,
        skipUnzipIfDirectoryExists: Bool = true,
        cleanup: Bool = false
    ) {
        self.sourceEPUBPath = epubPath
        self.isPreUnzipped = false
        self.shouldCleanup = cleanup
        self.skipUnzipIfDirectoryExists = skipUnzipIfDirectoryExists

        // Use the provided destination URL directly
        self.unzipDestination = destinationURL
    }

    /// Initialize with a pre-unzipped EPUB directory
    /// - Parameters:
    ///   - unzippedPath: Path to the unzipped EPUB directory
    ///   - cleanup: Whether to automatically cleanup the directory in deinit (defaults to false)
    /// - Throws: `EPUBParserError.invalidUnzippedPath` if the path is invalid or doesn't contain required EPUB files
    /// - Throws: `EPUBParserError.cacheNotFound` if the cache file is missing (required for pre-unzipped directories)
    init(unzippedPath: URL, cleanup: Bool = false) throws {
        self.sourceEPUBPath = nil
        self.isPreUnzipped = true
        self.unzipDestination = unzippedPath
        self.shouldCleanup = cleanup
        self.skipUnzipIfDirectoryExists = true  // Always true for pre-unzipped directories

        // Validate the unzipped path
        try validateUnzippedPath(unzippedPath)

        // Require cache file to exist for pre-unzipped directories
        let cacheURL = unzippedPath.appendingPathComponent(".epub_cache.json")
        guard FileManager.default.fileExists(atPath: cacheURL.path) else {
            throw EPUBParserError.cacheNotFound
        }
    }

    deinit {
        if shouldCleanup {
            cleanup()
        }
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

        // Step 1.5: Check for cached EPUBDocument
        if let cachedDocument = try loadCachedDocument() {
            print("📋 Using cached EPUB document")
            self.cachedDocument = cachedDocument
            return cachedDocument
        }

        // Step 2: Locate the content.opf file by parsing container.xml
        var actualBaseURL = unzipDestination
        var containerXML = unzipDestination.appendingPathComponent("META-INF/container.xml")

        assert(FileManager.default.fileExists(atPath: containerXML.path()))

        // Resolve the EPUB directory structure
        let directoryResolver = EPUBDirectoryResolver()
        let structureResult = directoryResolver.resolveEPUBStructure(from: unzipDestination)
        actualBaseURL = structureResult.baseURL
        containerXML = structureResult.containerXMLURL

        guard let contentOPFPath = parseContainerXML(at: containerXML, baseURL: actualBaseURL) else {
            throw EPUBParserError.contentOPFNotFound
        }

        // Verify OPF file exists
        guard FileManager.default.fileExists(atPath: contentOPFPath.path()) else {
            throw EPUBParserError.contentOPFNotFound
        }

        // Step 3: Set the OPF root directory as base for relative paths
        opfRootURL = contentOPFPath.deletingLastPathComponent()

        // Step 4: Parse metadata from the OPF file
        var metadata: EPUBMetadata
        do {
            metadata = try parseMetadata(opfURL: contentOPFPath)
        } catch {
            throw error
        }

        // Step 5: Parse manifest items from the OPF file
        let manifestItems: [EPUBManifestItem]
        do {
            manifestItems = try parseManifestItems(opfURL: contentOPFPath)
        } catch {
            throw error
        }

        // Step 5.5: Find cover image and update metadata
        let coverImagePath = findCoverImage(in: manifestItems, baseURL: contentOPFPath.deletingLastPathComponent(), rootURL: actualBaseURL)
        if let coverPath = coverImagePath {
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
                coverImagePath: coverPath
            )
        }

        // Step 6: Parse spine (reading order)
        let spineItems: [EPUBSpineItem]
        do {
            spineItems = try parseSpine(opfURL: contentOPFPath, manifestItems: manifestItems)
        } catch {
            throw error
        }

        // Step 6.5: Normalize HTML extensions for files without them (only for extracted EPUBs)
        let (updatedManifestItems, updatedSpineItems, pathMappings): ([EPUBManifestItem], [EPUBSpineItem], [String: String])
        if isPreUnzipped {
            // Skip file modifications for pre-unzipped directories
            updatedManifestItems = manifestItems
            updatedSpineItems = spineItems
            pathMappings = [:]
        } else {
            let result = try normalizeHTMLExtensions(
                manifestItems: manifestItems,
                spineItems: spineItems,
                baseURL: opfRootURL ?? unzipDestination
            )
            updatedManifestItems = result.0
            updatedSpineItems = result.1
            pathMappings = result.2
        }

        // Step 7: Parse table of contents
        tocURL = try findTocNCX(opfURL: contentOPFPath)
        guard let tocPath = tocURL else {
            throw EPUBParserError.tocNCXNotFound
        }
        var tableOfContents: [EPUBTOCItem]
        do {
            tableOfContents = try parseTableOfContents(at: tocPath)
        } catch {
            throw error
        }

        // Step 7.5: Apply HTML extension normalization to TOC items (only if we have path mappings)
        if !pathMappings.isEmpty {
            tableOfContents = applyHTMLExtensionNormalizationToTOC(
                tableOfContents: tableOfContents,
                pathMappings: pathMappings
            )
        }

        // Step 7.6: Normalize HTML content (add charset meta tags and clean line breaks) (only for extracted EPUBs)
        if !isPreUnzipped {
            try normalizeHTMLContent(
                spineItems: updatedSpineItems,
                baseURL: opfRootURL ?? unzipDestination
            )
        }

        // Step 8: Create and cache the EPUBDocument
        let document = EPUBDocument(
            metadata: metadata,
            manifest: updatedManifestItems,
            spineItems: updatedSpineItems,
            tableOfContents: tableOfContents,
            baseURL: opfRootURL ?? unzipDestination
        )

        cachedDocument = document

        // Step 8.5: Save document to cache (only for extracted EPUBs, not pre-unzipped directories)
        if !isPreUnzipped {
            try? saveCachedDocument(document)
        }

        return document
    }

    /// Get the base URL for resolving relative paths in this EPUB
    /// - Returns: The OPF root URL if available, or the unzip destination
    public func baseURL() -> URL {
        return opfRootURL ?? unzipDestination
    }

    /// Get the unzipped root directory URL for reconstructing cover image paths
    /// - Returns: The root directory of the unzipped EPUB content
    public func unzippedRootURL() -> URL {
        return unzipDestination
    }

    /// Clean up unzipped content to free disk space
    /// Note: This will not delete pre-unzipped directories provided via `init(unzippedPath:)` unless cleanup parameter was set to true
    /// Can be called manually regardless of the cleanup parameter setting
    nonisolated public func cleanup() {
        // Don't delete pre-unzipped directories that the user provided (unless they explicitly requested cleanup)
        // guard !isPreUnzipped || shouldCleanup else { return }
        // try? FileManager.default.removeItem(at: unzipDestination)
    }

    // MARK: - Private Methods

    /// Normalize HTML extensions for files that don't have them
    private func normalizeHTMLExtensions(
        manifestItems: [EPUBManifestItem],
        spineItems: [EPUBSpineItem],
        baseURL: URL
    ) throws -> ([EPUBManifestItem], [EPUBSpineItem], [String: String]) {
        var pathMappings: [String: String] = [:]

        // Iterate through spine items and check if HTML files need .html extension
        for spineItem in spineItems {
            let manifestItem = spineItem.manifestItem

            // Check if this is an HTML file
            let isHTMLFile =
                ["application/xhtml+xml", "text/html"].contains(manifestItem.mediaType) || manifestItem.path.hasSuffix(".html") || manifestItem.path.hasSuffix(".xhtml")
                || manifestItem.path.hasSuffix(".htm")

            if isHTMLFile {
                // Get the full file URL
                let fileURL = baseURL.appendingPathComponent(manifestItem.path)

                // Check if file exists and doesn't have a proper extension
                let pathExtension = fileURL.pathExtension.lowercased()
                let hasProperExtension = ["html", "xhtml", "htm"].contains(pathExtension)

                if !hasProperExtension && fileManager.fileExists(atPath: fileURL.path) {
                    // Rename the file to add .html extension
                    let newFileURL = fileURL.appendingPathExtension("html")

                    // Skip if target already exists
                    if !fileManager.fileExists(atPath: newFileURL.path) {
                        try fileManager.moveItem(at: fileURL, to: newFileURL)

                        // Store the path mapping
                        let newPath = manifestItem.path + ".html"
                        pathMappings[manifestItem.path] = newPath

                        print("✏️ Renamed HTML file: \(manifestItem.path) → \(newPath)")
                    }
                }
            }
        }

        // Update manifest items with new paths
        let updatedManifestItems = manifestItems.map { item in
            if let newPath = pathMappings[item.path] {
                return EPUBManifestItem(
                    id: item.id,
                    path: newPath,
                    mediaType: item.mediaType,
                    properties: item.properties
                )
            }
            return item
        }

        // Update spine items with updated manifest items
        let updatedSpineItems = spineItems.map { spineItem in
            let manifestItem = spineItem.manifestItem
            if let newPath = pathMappings[manifestItem.path] {
                let updatedManifestItem = EPUBManifestItem(
                    id: manifestItem.id,
                    path: newPath,
                    mediaType: manifestItem.mediaType,
                    properties: manifestItem.properties
                )
                return EPUBSpineItem(
                    id: spineItem.id,
                    index: spineItem.index,
                    linear: spineItem.linear,
                    manifestItem: updatedManifestItem
                )
            }
            return spineItem
        }

        return (updatedManifestItems, updatedSpineItems, pathMappings)
    }

    /// Apply HTML extension normalization to TOC items
    private func applyHTMLExtensionNormalizationToTOC(
        tableOfContents: [EPUBTOCItem],
        pathMappings: [String: String]
    ) -> [EPUBTOCItem] {
        return tableOfContents.map { tocItem in
            var updatedHref = tocItem.href

            // Handle hrefs that may contain fragments (e.g., "chapter1#section2")
            if let hashIndex = tocItem.href.firstIndex(of: "#") {
                let pathPart = String(tocItem.href[..<hashIndex])
                let fragmentPart = String(tocItem.href[tocItem.href.index(after: hashIndex)...])

                // Check if the path part was remapped
                if let newPath = pathMappings[pathPart] {
                    updatedHref = newPath + "#" + fragmentPart
                    print("✏️ Updated TOC href with fragment: \(tocItem.href) → \(updatedHref)")
                }
            } else {
                // No fragment, check direct mapping
                if let newPath = pathMappings[tocItem.href] {
                    updatedHref = newPath
                    print("✏️ Updated TOC href: \(tocItem.href) → \(updatedHref)")
                }
            }

            // Recursively update children
            let updatedChildren = applyHTMLExtensionNormalizationToTOC(
                tableOfContents: tocItem.children ?? [],
                pathMappings: pathMappings
            )

            return EPUBTOCItem(
                id: tocItem.id,
                title: tocItem.title,
                playOrder: tocItem.playOrder,
                href: updatedHref,
                children: updatedChildren
            )
        }
    }

    /// Normalize HTML content by adding charset meta tags and cleaning line breaks
    private func normalizeHTMLContent(
        spineItems: [EPUBSpineItem],
        baseURL: URL
    ) throws {
        print("\n📝 Normalizing HTML content...")

        var normalizedCount = 0
        var charsetAddedCount = 0

        for spineItem in spineItems {
            let manifestItem = spineItem.manifestItem

            // Check if this is an HTML file
            let isHTMLFile =
                ["application/xhtml+xml", "text/html"].contains(manifestItem.mediaType) || manifestItem.path.hasSuffix(".html") || manifestItem.path.hasSuffix(".xhtml")
                || manifestItem.path.hasSuffix(".htm")

            if isHTMLFile {
                let fileURL = baseURL.appendingPathComponent(manifestItem.path)

                // Check if file exists
                guard fileManager.fileExists(atPath: fileURL.path) else {
                    print("⚠️ HTML file not found: \(manifestItem.path)")
                    continue
                }

                do {
                    // Read the HTML content
                    let originalContent = try String(contentsOf: fileURL, encoding: .utf8)

                    // Check if it needs charset meta tag before normalization
                    let needsCharset = !checkForCharsetMeta(in: originalContent)

                    // Normalize the content (add charset if needed and clean line breaks)
                    let normalizedContent = try normalizeHTMLContent(originalContent)

                    // Write back if content changed
                    if normalizedContent != originalContent {
                        try normalizedContent.write(to: fileURL, atomically: true, encoding: String.Encoding.utf8)
                        normalizedCount += 1

                        if needsCharset {
                            charsetAddedCount += 1
                        }

                        print("✏️ Normalized HTML file: \(manifestItem.path)")
                    }

                } catch {
                    print("⚠️ Failed to normalize HTML file \(manifestItem.path): \(error)")
                }
            }
        }

        print("📊 HTML normalization complete:")
        print("  Files processed: \(normalizedCount)")
        print("  Charset meta tags added: \(charsetAddedCount)")
    }

    /// Check if HTML content already contains a charset meta tag in the head section
    private func checkForCharsetMeta(in content: String) -> Bool {
        // Pattern to find <head> section
        guard
            let headRegex = try? NSRegularExpression(
                pattern: "<head[^>]*>(.*?)</head>",
                options: [.caseInsensitive, .dotMatchesLineSeparators]
            )
        else {
            return false
        }

        let range = NSRange(location: 0, length: content.utf16.count)
        guard let headMatch = headRegex.firstMatch(in: content, options: [], range: range),
            let headRange = Range(headMatch.range(at: 1), in: content)
        else {
            return false
        }

        let headContent = String(content[headRange])

        // Check for various charset meta tag patterns
        let charsetPatterns = [
            "<meta\\s+charset\\s*=\\s*[\"']?utf-8[\"']?[^>]*>",
            "<meta\\s+[^>]*charset\\s*=\\s*[\"']?utf-8[\"']?[^>]*>",
            "<meta\\s+http-equiv\\s*=\\s*[\"']?content-type[\"']?[^>]*charset\\s*=\\s*utf-8[^>]*>",
        ]

        for pattern in charsetPatterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
                regex.firstMatch(in: headContent, options: [], range: NSRange(location: 0, length: headContent.utf16.count)) != nil
            {
                return true
            }
        }

        return false
    }

    /// Normalize HTML content by adding charset meta tag if needed and cleaning line breaks
    private func normalizeHTMLContent(_ content: String) throws -> String {
        var normalizedContent = content

        // Check if charset meta tag needs to be added
        if !checkForCharsetMeta(in: content) {
            normalizedContent = try addCharsetMeta(to: normalizedContent)
        }

        // Clean line breaks
        normalizedContent = cleanHTMLLineBreaks(normalizedContent)

        return normalizedContent
    }

    /// Add charset meta tag to HTML content
    private func addCharsetMeta(to content: String) throws -> String {
        // Pattern to find <head> tag
        guard
            let headRegex = try? NSRegularExpression(
                pattern: "(<head[^>]*>)",
                options: .caseInsensitive
            )
        else {
            throw EPUBParserError.invalidEPUBStructure("Failed to parse HTML head tag")
        }

        let range = NSRange(location: 0, length: content.utf16.count)

        // Replace the first <head> tag with <head> + charset meta tag
        let result = headRegex.stringByReplacingMatches(
            in: content,
            options: [],
            range: range,
            withTemplate: "$1\n    <meta charset=\"utf-8\" />"
        )

        return result
    }

    /// Clean line breaks from HTML content
    private func cleanHTMLLineBreaks(_ content: String) -> String {
        // Remove excessive line breaks (more than 2 consecutive newlines)
        let cleanedContent = content.replacingOccurrences(
            of: "\\n\\s*\\n\\s*\\n+",
            with: "\n\n",
            options: .regularExpression
        )

        // Trim leading and trailing whitespace from each line while preserving intentional indentation
        let lines = cleanedContent.components(separatedBy: .newlines)
        let processedLines = lines.map { line in
            // Only trim trailing whitespace, preserve leading whitespace for indentation
            return line.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines.subtracting(CharacterSet.newlines))
        }

        return processedLines.joined(separator: "\n")
    }

    /// Validate that the unzipped path contains required EPUB files
    nonisolated private func validateUnzippedPath(_ path: URL) throws {
        let fileManager = FileManager.default
        var isDirectory: ObjCBool = false

        // Check if path exists and is a directory
        guard fileManager.fileExists(atPath: path.path, isDirectory: &isDirectory) else {
            throw EPUBParserError.invalidUnzippedPath("Path does not exist: \(path.path)")
        }

        guard isDirectory.boolValue else {
            throw EPUBParserError.invalidUnzippedPath("Path is not a directory: \(path.path)")
        }

        // Check for essential EPUB structure
        let directoryResolver = EPUBDirectoryResolver()
        let structureResult = directoryResolver.resolveEPUBStructure(from: path)

        // Verify container.xml exists
        guard fileManager.fileExists(atPath: structureResult.containerXMLURL.path) else {
            throw EPUBParserError.invalidUnzippedPath("Missing META-INF/container.xml")
        }
    }

    private func unzipIfNeeded() throws {
        // If already using a pre-unzipped directory, skip unzipping
        if isPreUnzipped {
            return
        }

        // Ensure we have a source EPUB path
        guard let sourceEPUB = sourceEPUBPath else {
            throw EPUBParserError.invalidUnzippedPath("No source EPUB file specified")
        }

        // Check if already unzipped (only skip if skipUnzipIfDirectoryExists is true)
        if skipUnzipIfDirectoryExists && fileManager.fileExists(atPath: unzipDestination.path) {
            return
        }

        // If directory exists but we want to re-extract, remove it first
        if !skipUnzipIfDirectoryExists && fileManager.fileExists(atPath: unzipDestination.path) {
            try fileManager.removeItem(at: unzipDestination)
        }

        // Create directory if needed
        try fileManager.createDirectory(
            at: unzipDestination,
            withIntermediateDirectories: true)

        do {
            // Try system unarchiver first (more tolerant of minor issues)
            try fileManager.unzipItem(at: sourceEPUB, to: unzipDestination)
        } catch {
            print("⚠️ System unarchiver failed: \(String(describing: error))")
            print("🔧 Attempting fallback to ZIPFoundation...")

            // Clean up any partial extraction
            try? fileManager.removeItem(at: unzipDestination)
            try fileManager.createDirectory(at: unzipDestination, withIntermediateDirectories: true)

            // Fallback to ZIPFoundation
            try unzipWithZIPFoundation(sourceEPUB: sourceEPUB)
        }
    }

    private func unzipWithZIPFoundation(sourceEPUB: URL) throws {
        do {
            let archive = try Archive(url: sourceEPUB, accessMode: .read)

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

    private func findCoverImage(in manifestItems: [EPUBManifestItem], baseURL: URL, rootURL: URL) -> String? {
        var candidateCoverItem: EPUBManifestItem? = nil

        // Strategy 1: Look for item with id="cover-image" (must be an image)
        candidateCoverItem = manifestItems.first(where: {
            ($0.id.lowercased() == "cover-image" || $0.id.lowercased() == "cover") && $0.mediaType.hasPrefix("image/")
        })

        // Strategy 2: Look for properties="cover-image" (must be an image)
        if candidateCoverItem == nil {
            candidateCoverItem = manifestItems.first(where: {
                $0.properties["properties"]?.contains("cover-image") == true && $0.mediaType.hasPrefix("image/")
            })
        }

        // Strategy 3: Look for any item with "cover" in id that's an image
        if candidateCoverItem == nil {
            candidateCoverItem = manifestItems.first(where: {
                $0.id.lowercased().contains("cover") && $0.mediaType.hasPrefix("image/")
            })
        }

        // Strategy 4: Look for first image in manifest
        if candidateCoverItem == nil {
            candidateCoverItem = manifestItems.first(where: {
                $0.mediaType.hasPrefix("image/")
            })
        }

        // Validate and construct URL
        guard let coverItem = candidateCoverItem else { return nil }

        // Ensure path is not empty and contains actual content
        let trimmedPath = coverItem.path.trimmingCharacters(in: .whitespaces)
        guard !trimmedPath.isEmpty else {
            print("⚠️ Cover image found but path is empty: id=\(coverItem.id)")
            return nil
        }

        // Verify the actual file exists by checking the absolute path
        let absoluteCoverURL = baseURL.appendingPathComponent(trimmedPath)
        let fileExists = FileManager.default.fileExists(atPath: absoluteCoverURL.path)

        guard fileExists else {
            print("⚠️ Cover image file not found: \(absoluteCoverURL.path)")
            return nil
        }

        // Calculate relative path from rootURL to the cover image
        // This ensures that unzippedRootURL.appendingPathComponent(coverImagePath) works correctly
        let rootPath = rootURL.path
        let absolutePath = absoluteCoverURL.path

        // Calculate relative path from rootURL to the cover image
        let relativePath: String
        if absolutePath.hasPrefix(rootPath + "/") {
            // Remove rootPath prefix to get relative path
            relativePath = String(absolutePath.dropFirst(rootPath.count + 1))
        } else if absolutePath == rootPath {
            // Edge case: cover image is at root level
            relativePath = absoluteCoverURL.lastPathComponent
        } else {
            // Fallback: use the original trimmed path
            relativePath = trimmedPath
        }

        print("📸 Cover image path created: \(absoluteCoverURL.absoluteString)")
        print("   Path: \(absoluteCoverURL.path)")
        print("   Exists: \(fileExists)")
        print("   Relative to root: \(relativePath)")

        return relativePath
    }

    // MARK: - Caching Methods

    /// Cache file name for storing parsed EPUB document
    private var cacheFileName: String { ".epub_cache.json" }

    /// Full path to the cache file
    private var cacheFileURL: URL {
        unzipDestination.appendingPathComponent(cacheFileName)
    }

    /// Load cached EPUBDocument if available and valid
    private func loadCachedDocument() throws -> EPUBDocument? {
        let cacheURL = cacheFileURL

        // Check if cache file exists
        guard fileManager.fileExists(atPath: cacheURL.path) else {
            return nil
        }

        print("📋 Found cache file at: \(cacheURL.path)")

        do {
            // Load and decode the cached document
            let data = try Data(contentsOf: cacheURL)
            let decoder = JSONDecoder()
            let cachedDocument = try decoder.decode(EPUBDocument.self, from: data)

            // Convert cached relative paths back to absolute paths using current unzipDestination
            let absoluteBaseURL = convertRelativeToAbsolutePath(cachedDocument.baseURL.path)

            // Validate that the cached paths still exist
            guard fileManager.fileExists(atPath: absoluteBaseURL.path) else {
                print("⚠️ Cached base path no longer exists, will reparse")
                try? fileManager.removeItem(at: cacheURL)
                return nil
            }

            // Create document with corrected absolute paths
            // Note: Cover image paths are already relative strings, no conversion needed
            let document = EPUBDocument(
                metadata: cachedDocument.metadata,
                manifest: cachedDocument.manifest,
                spineItems: cachedDocument.spineItems,
                tableOfContents: cachedDocument.tableOfContents,
                baseURL: absoluteBaseURL
            )

            return document
        } catch {
            // Cache is corrupted or format changed, delete it
            print("⚠️ Cache file corrupted, will reparse: \(error)")
            try? fileManager.removeItem(at: cacheURL)
            return nil
        }
    }

    /// Save EPUBDocument to cache
    private func saveCachedDocument(_ document: EPUBDocument) throws {
        let cacheURL = cacheFileURL

        do {
            // Convert absolute baseURL to relative path for caching
            let relativeBaseURL = convertAbsoluteToRelativePath(document.baseURL)

            // Create cacheable document with relative paths
            // Note: Cover image paths are already relative strings, no conversion needed
            let cacheableDocument = EPUBDocument(
                metadata: document.metadata,
                manifest: document.manifest,
                spineItems: document.spineItems,
                tableOfContents: document.tableOfContents,
                baseURL: relativeBaseURL
            )

            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(cacheableDocument)
            try data.write(to: cacheURL)
            print("💾 Saved EPUB document to cache: \(cacheFileName)")
        } catch {
            print("⚠️ Failed to save cache: \(error)")
            // Don't throw - caching failure shouldn't break parsing
        }
    }

    // MARK: - Path Conversion Helpers

    /// Convert absolute path to relative path for caching
    private func convertAbsoluteToRelativePath(_ absoluteURL: URL) -> URL {
        let absolutePath = absoluteURL.path
        let basePath = unzipDestination.path

        // If the absolute path starts with our base path, make it relative
        if absolutePath.hasPrefix(basePath + "/") {
            let relativePath = String(absolutePath.dropFirst(basePath.count + 1))
            return URL(fileURLWithPath: relativePath)
        } else if absolutePath == basePath {
            // Base path itself becomes empty relative path
            return URL(fileURLWithPath: ".")
        }

        // Fallback: return as-is if we can't make it relative
        return absoluteURL
    }

    /// Convert relative path from cache back to absolute path
    private func convertRelativeToAbsolutePath(_ relativePath: String) -> URL {
        if relativePath == "." {
            return unzipDestination
        }
        return unzipDestination.appendingPathComponent(relativePath)
    }
}

extension Array {
    func element(at: Int) -> Element? {
        guard at >= 0, at < count else { return nil }
        return self[at]
    }
}
