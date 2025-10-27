import Foundation

/// Represents a complete parsed EPUB document with all its components
public struct EPUBDocument: Hashable, Sendable, Codable {
    /// Metadata about the publication
    public let metadata: EPUBMetadata

    /// All manifest items (files and resources)
    public let manifest: [EPUBManifestItem]

    /// Spine items (reading order)
    public let spineItems: [EPUBSpineItem]

    /// Table of contents (hierarchical navigation structure)
    public let tableOfContents: [EPUBTOCItem]

    /// The base URL for resolving relative paths
    public let baseURL: URL

    /// Initialize an EPUB document
    public init(
        metadata: EPUBMetadata,
        manifest: [EPUBManifestItem],
        spineItems: [EPUBSpineItem],
        tableOfContents: [EPUBTOCItem],
        baseURL: URL
    ) {
        self.metadata = metadata
        self.manifest = manifest
        self.spineItems = spineItems
        self.tableOfContents = tableOfContents
        self.baseURL = baseURL
    }
}

extension EPUBDocument {
    /// Get a manifest item by its ID
    public func manifestItem(withId id: String) -> EPUBManifestItem? {
        manifest.first { $0.id == id }
    }

    /// Get all HTML/XHTML manifest items
    public var htmlManifestItems: [EPUBManifestItem] {
        manifest.filter { item in
            ["application/xhtml+xml", "text/html"].contains(item.mediaType) || item.path.hasSuffix(".html") || item.path.hasSuffix(".xhtml") || item.path.hasSuffix(".htm")
        }
    }

    /// Get the full URL for a manifest item
    public func url(for item: EPUBManifestItem) -> URL {
        baseURL.appending(path: item.path)
    }

    /// Get the full URL for a TOC item
    public func url(for tocItem: EPUBTOCItem) -> URL {
        // Handle hrefs that may contain fragments (e.g., "chapter1.html#section2")
        if let hashIndex = tocItem.href.firstIndex(of: "#") {
            let pathPart = String(tocItem.href[..<hashIndex])
            let fragmentPart = String(tocItem.href[tocItem.href.index(after: hashIndex)...])

            var urlComponents = URLComponents()
            urlComponents.scheme = baseURL.scheme
            urlComponents.path = baseURL.appendingPathComponent(pathPart).path
            urlComponents.fragment = fragmentPart

            return urlComponents.url ?? baseURL.appendingPathComponent(tocItem.href)
        }

        return baseURL.appendingPathComponent(tocItem.href)
    }

    /// Get a flattened array of all TOC items (including nested ones)
    public var flattenedTableOfContents: [EPUBTOCItem] {
        EPUBTOCItem.flattenAll(tableOfContents)
    }

    /// Get only the spine items that are part of linear reading order
    public var linearSpineItems: [EPUBSpineItem] {
        spineItems.filter { $0.linear }
    }

    /// Get the full URL for the cover image
    /// Returns nil if no cover image path is available in metadata
    /// Note: Cover image paths are relative to the unzipped EPUB root, not the OPF directory
    public var coverURL: URL? {
        guard let coverImagePath = metadata.coverImagePath else {
            return nil
        }

        // Cover image paths are calculated relative to the unzipped root directory
        // If baseURL is an OPF directory (like /epub/ops/), we need to go up to the root
        let unzippedRoot = findUnzippedRoot(from: baseURL)
        return unzippedRoot.appendingPathComponent(coverImagePath)
    }

    /// Find the unzipped root directory from the current baseURL
    /// This handles cases where baseURL points to an OPF subdirectory
    private func findUnzippedRoot(from baseURL: URL) -> URL {
        // Check if this looks like an OPF subdirectory (contains META-INF at parent level)
        var testURL = baseURL

        // Go up directories until we find the one containing META-INF
        while !testURL.path.isEmpty && testURL.path != "/" {
            let metaInfURL = testURL.appendingPathComponent("META-INF")
            if FileManager.default.fileExists(atPath: metaInfURL.path) {
                return testURL
            }
            testURL = testURL.deletingLastPathComponent()
        }

        // Fallback: return the original baseURL if we can't find META-INF
        return baseURL
    }

    /// Find the spine item ID for a given href (path or URL string)
    /// This method handles both relative and absolute URLs, with or without fragments
    /// Returns nil if no matching spine item is found
    public func spineItemId(for href: String) -> String? {
        // Handle empty or invalid hrefs
        guard !href.isEmpty else { return nil }

        // Remove fragment part if present (e.g., "chapter1.html#section2" -> "chapter1.html")
        let pathWithoutFragment: String
        if let hashIndex = href.firstIndex(of: "#") {
            pathWithoutFragment = String(href[..<hashIndex])
        } else {
            pathWithoutFragment = href
        }

        // Handle absolute URLs by extracting the path component
        let targetPath: String
        if let url = URL(string: pathWithoutFragment), url.scheme != nil {
            // This is an absolute URL, extract the path relative to baseURL
            if pathWithoutFragment.hasPrefix(baseURL.absoluteString) {
                targetPath = String(pathWithoutFragment.dropFirst(baseURL.absoluteString.count))
            } else {
                // Different base URL, try to extract just the filename
                targetPath = url.lastPathComponent
            }
        } else {
            // This is a relative path
            targetPath = pathWithoutFragment
        }

        // Normalize the path by removing leading slashes and resolving relative components
        let normalizedPath = targetPath.hasPrefix("/") ? String(targetPath.dropFirst()) : targetPath

        // Find matching spine item by comparing paths
        for spineItem in spineItems {
            let manifestPath = spineItem.manifestItem.path

            // Direct path match
            if manifestPath == normalizedPath {
                return spineItem.id
            }

            // Match by filename if full path doesn't match
            let manifestFileName = URL(fileURLWithPath: manifestPath).lastPathComponent
            let targetFileName = URL(fileURLWithPath: normalizedPath).lastPathComponent

            if manifestFileName == targetFileName {
                return spineItem.id
            }
        }

        // Additional fallback: Try path extension variations for HTML files
        // This handles cases where navigation uses .html but spine items have .xhtml or vice versa
        if normalizedPath.hasSuffix(".html") || normalizedPath.hasSuffix(".xhtml") || normalizedPath.hasSuffix(".htm") {
            // Use string manipulation to preserve relative path structure
            let pathExtension = URL(fileURLWithPath: normalizedPath).pathExtension
            let basePath = String(normalizedPath.dropLast(pathExtension.count + 1))  // Remove .extension
            let htmlExtensions = ["html", "xhtml", "htm"]

            for ext in htmlExtensions {
                let testPath = basePath + "." + ext
                for spineItem in spineItems {
                    if spineItem.manifestItem.path == testPath {
                        return spineItem.id
                    }
                }
            }
        }

        return nil
    }

    /// Find the spine item ID for a given URL
    /// This method handles both relative and absolute URLs, with or without fragments
    /// Returns nil if no matching spine item is found
    public func spineItemId(for url: URL) -> String? {
        return spineItemId(for: url.absoluteString)
    }
}
