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

            guard url.lastPathComponent.firstMatch(of: #/\.x?html?/#) != nil else { return nil }

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

    /**
     Creates a merged HTML document by appending the body content of subsequent HTML files
     into the first HTML file's body.

     - Parameter baseURL: The base URL used to resolve relative paths in the HTML content.
     - Returns: A single HTML document with all body content merged into the first document.
     - Throws: An error if the HTML content cannot be retrieved or processed.
     */
    public func mergedHTML(baseURL: URL) throws -> String {
        let htmlContents = try htmls(baseURL: baseURL)
        guard let firstHTML = htmlContents.first else {
            return ""
        }

        if htmlContents.count == 1 {
            return firstHTML
        }

        // Extract the body content from subsequent HTML files
        let bodyRegex = try NSRegularExpression(pattern: "<body[^>]*>(.*?)</body>", options: [.dotMatchesLineSeparators])
        let subsequentBodies = htmlContents.dropFirst().compactMap { html -> String? in
            let range = NSRange(html.startIndex..<html.endIndex, in: html)
            guard let match = bodyRegex.firstMatch(in: html, options: [], range: range) else {
                return nil
            }
            guard let bodyContentRange = Range(match.range(at: 1), in: html) else {
                return nil
            }
            return String(html[bodyContentRange])
        }.joined(separator: "\n\n")

        // Find where to insert the additional body content in the first HTML
        let insertionRegex = try NSRegularExpression(pattern: "</body>", options: [])
        let range = NSRange(firstHTML.startIndex..<firstHTML.endIndex, in: firstHTML)

        guard let match = insertionRegex.firstMatch(in: firstHTML, options: [], range: range),
            let insertionRange = Range(match.range, in: firstHTML)
        else {
            return firstHTML
        }

        // Insert the additional body content
        let mergedHTML = firstHTML.replacingCharacters(
            in: insertionRange,
            with: "\n<!-- Content merged from additional chapter files -->\n\(subsequentBodies)\n</body>"
        )

        return mergedHTML
    }
}

extension Array: @retroactive Identifiable where Element == EPUBChapter {
    public var id: String {
        self.map { $0.id }.joined(separator: ",")
    }
}
