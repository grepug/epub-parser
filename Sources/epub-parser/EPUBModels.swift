import Foundation

/// A model to represent an EPUB chapter with its content
public struct EPUBChapter: Identifiable, Hashable, Sendable {
    public let id: String
    public let title: String
    public let playOrder: Int
    /// The source path of the chapter in the EPUB
    public let path: String
    /// All manifest items associated with this chapter
    public var manifestItems: [EPUBManifestItem]

    /// Initialize a complete chapter with manifest items
    public init(id: String, title: String, playOrder: Int, path: String, manifestItems: [EPUBManifestItem] = []) {
        self.id = id
        self.title = title
        self.playOrder = playOrder
        self.path = path
        self.manifestItems = manifestItems
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    public static func == (lhs: EPUBChapter, rhs: EPUBChapter) -> Bool {
        lhs.id == rhs.id
    }

    /// Get the HTML content for this chapter
    /// - Parameters:
    ///   - baseURL: The base URL to resolve relative paths against
    ///   - cleanLineBreaks: Whether to remove unnecessary line breaks from HTML elements
    /// - Returns: Array of HTML content strings for all manifest items
    public func htmls(baseURL: URL, cleanLineBreaks: Bool = true) throws -> [String] {
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

            var content = try String(contentsOf: url, encoding: .utf8)

            if cleanLineBreaks {
                content = try cleanHTMLLineBreaks(content)
            }

            return content
        }
    }

    /**
     Combines all HTML content into a single string.
    
     This method concatenates all HTML content from the EPUB files with line breaks between each content section.
    
     - Parameters:
       - baseURL: The base URL used to resolve relative paths in the HTML content.
       - cleanLineBreaks: Whether to remove unnecessary line breaks from HTML elements
     - Returns: A single string containing all combined HTML content.
     - Throws: An error if the HTML content cannot be retrieved or processed.
     */
    public func combinedHTML(baseURL: URL, cleanLineBreaks: Bool = true) throws -> String {
        try htmls(baseURL: baseURL, cleanLineBreaks: cleanLineBreaks).joined(separator: "\n\n")
    }

    /**
     Creates a merged HTML document by appending the body content of subsequent HTML files
     into the first HTML file's body.
    
     - Parameters:
       - baseURL: The base URL used to resolve relative paths in the HTML content.
       - cleanLineBreaks: Whether to remove unnecessary line breaks from HTML elements
     - Returns: A single HTML document with all body content merged into the first document.
     - Throws: An error if the HTML content cannot be retrieved or processed.
     */
    public func mergedHTML(baseURL: URL, cleanLineBreaks: Bool = true) throws -> String {
        let htmlContents = try htmls(baseURL: baseURL, cleanLineBreaks: cleanLineBreaks)
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

/// Utility function to clean unnecessary line breaks from HTML content
private func cleanHTMLLineBreaks(_ content: String) throws -> String {
    var cleanedContent = content

    // Elements where we want to remove line breaks from content
    let elements = ["p", "span", "em", "strong", "i", "b", "h1", "h2", "h3", "h4", "h5", "h6", "title", "a", "li", "td", "th"]

    // First, protect content that should preserve line breaks (like <pre>, <code> blocks)
    var protectedRanges: [(original: String, placeholder: String)] = []
    let protectedElements = ["pre", "code", "script", "style"]

    for element in protectedElements {
        let pattern = "<\(element)[^>]*>.*?</\(element)>"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive, .dotMatchesLineSeparators]) else {
            continue
        }

        let matches = regex.matches(in: cleanedContent, options: [], range: NSRange(location: 0, length: cleanedContent.utf16.count))
        for (index, match) in matches.enumerated().reversed() {
            if let range = Range(match.range, in: cleanedContent) {
                let original = String(cleanedContent[range])
                let placeholder = "___PROTECTED_\(element.uppercased())_\(index)___"
                protectedRanges.append((original: original, placeholder: placeholder))
                cleanedContent.replaceSubrange(range, with: placeholder)
            }
        }
    }

    // Clean line breaks in target elements
    for element in elements {
        // Pattern to match opening tag (with optional attributes), content, and closing tag
        let pattern = "<(\(element))([^>]*)>(.*?)</\(element)>"

        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive, .dotMatchesLineSeparators]) else {
            continue
        }

        // Replace matches
        let range = NSRange(location: 0, length: cleanedContent.utf16.count)
        let matches = regex.matches(in: cleanedContent, options: [], range: range)

        // Process matches in reverse order to avoid index shifting
        for match in matches.reversed() {
            guard let fullRange = Range(match.range, in: cleanedContent),
                let tagRange = Range(match.range(at: 1), in: cleanedContent),
                let attributesRange = Range(match.range(at: 2), in: cleanedContent),
                let contentRange = Range(match.range(at: 3), in: cleanedContent)
            else {
                continue
            }

            let tagName = String(cleanedContent[tagRange])
            let attributes = String(cleanedContent[attributesRange])
            let elementContent = String(cleanedContent[contentRange])

            // Clean the content: remove line breaks and normalize whitespace
            let cleaned =
                elementContent
                .replacingOccurrences(of: "\n", with: " ")
                .replacingOccurrences(of: "\r", with: " ")
                .replacingOccurrences(of: "\t", with: " ")
                // Replace multiple spaces with single space
                .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
                .trimmingCharacters(in: .whitespaces)

            // Reconstruct the element
            let replacement = "<\(tagName)\(attributes)>\(cleaned)</\(tagName)>"
            cleanedContent.replaceSubrange(fullRange, with: replacement)
        }
    }

    // Restore protected content
    for protected in protectedRanges.reversed() {
        if let range = cleanedContent.range(of: protected.placeholder) {
            cleanedContent.replaceSubrange(range, with: protected.original)
        }
    }

    return cleanedContent
}

extension Array: @retroactive Identifiable where Element == EPUBChapter {
    public var id: String {
        self.map { $0.id }.joined(separator: ",")
    }
}
