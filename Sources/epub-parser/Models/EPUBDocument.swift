import Foundation

/// Represents a complete parsed EPUB document with all its components
public struct EPUBDocument: Hashable, Sendable {
    /// Metadata about the publication
    public let metadata: EPUBMetadata

    /// All manifest items (files and resources)
    public let manifest: [EPUBManifestItem]

    /// Spine items (reading order)
    public let spine: [EPUBSpineItem]

    /// Table of contents (hierarchical navigation structure)
    public let tableOfContents: [EPUBTOCItem]

    /// The base URL for resolving relative paths
    public let baseURL: URL

    /// Initialize an EPUB document
    public init(
        metadata: EPUBMetadata,
        manifest: [EPUBManifestItem],
        spine: [EPUBSpineItem],
        tableOfContents: [EPUBTOCItem],
        baseURL: URL
    ) {
        self.metadata = metadata
        self.manifest = manifest
        self.spine = spine
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
        spine.filter { $0.linear }
    }
}
