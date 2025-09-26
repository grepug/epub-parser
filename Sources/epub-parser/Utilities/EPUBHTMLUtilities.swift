import Foundation

// MARK: - HTML Utility Functions

/// Utility function to clean unnecessary line breaks from HTML content
internal func cleanHTMLLineBreaks(_ content: String) throws -> String {
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
