import Foundation

/// A model to represent an EPUB chapter with its content
public struct EPUBChapter: Identifiable, Hashable {
    public let id: String
    public let title: String
    public let playOrder: Int
    /// All manifest items associated with this chapter
    public let manifestItems: [EPUBManifestItem]

    public func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    public static func == (lhs: EPUBChapter, rhs: EPUBChapter) -> Bool {
        lhs.id == rhs.id
    }

    /// Get the HTML content for this chapter
    /// - Parameter baseURL: The base URL to resolve relative paths against
    /// - Returns: Array of HTML content strings for all manifest items
    public func htmls(baseURL: URL) throws -> [String] {
        try manifestItems.compactMap { item -> String? in
            let url: URL

            if item.path.starts(with: "/") {
                // Handle absolute paths by removing the leading slash and appending to the EPUB root
                url = baseURL.deletingLastPathComponent().appendingPathComponent(String(item.path.dropFirst()))
            } else {
                // Handle relative paths by resolving against the baseURL
                url = URL(string: item.path, relativeTo: baseURL) ?? baseURL.appendingPathComponent(item.path)
            }

            guard url.lastPathComponent.contains(".html") else { return nil }

            return try String(contentsOf: url, encoding: .utf8)
        }
    }

    /**
     Combines all HTML content into a single string.

     This method concatenates all HTML content from the EPUB files with line breaks between each content section.

     - Parameter baseURL: The base URL used to resolve relative paths in the HTML content.
     - Returns: A single string containing all combined HTML content.
     - Throws: An error if the HTML content cannot be retrieved or processed.
     */
    public func combinedHTML(baseURL: URL) throws -> String {
        try htmls(baseURL: baseURL).joined(separator: "\n\n")
    }
}

extension Array: @retroactive Identifiable where Element == EPUBChapter {
    public var id: String {
        self.map { $0.id }.joined(separator: ",")
    }
}
