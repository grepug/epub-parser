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

/// Normalize HTML content by ensuring charset meta tag and cleaning line breaks
internal func normalizeHTMLContent(_ content: String) throws -> String {
    var normalizedContent = content

    // First, clean line breaks
    normalizedContent = try cleanHTMLLineBreaks(normalizedContent)

    // Check if charset meta tag exists in head section
    let hasCharsetMeta = checkForCharsetMeta(in: normalizedContent)

    if !hasCharsetMeta {
        normalizedContent = try addCharsetMeta(to: normalizedContent)
    }

    return normalizedContent
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

/// Add charset meta tag to HTML content
private func addCharsetMeta(to content: String) throws -> String {
    // Pattern to find <head> tag and insert after it
    guard
        let headRegex = try? NSRegularExpression(
            pattern: "(<head[^>]*>)",
            options: .caseInsensitive
        )
    else {
        throw NSError(domain: "HTMLNormalization", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to create head regex"])
    }

    let range = NSRange(location: 0, length: content.utf16.count)

    if let match = headRegex.firstMatch(in: content, options: [], range: range),
        let matchRange = Range(match.range, in: content)
    {

        // Insert charset meta tag right after <head> tag
        let charsetMeta = "\n    <meta charset=\"utf-8\" />"
        var modifiedContent = content
        let insertionPoint = matchRange.upperBound
        modifiedContent.insert(contentsOf: charsetMeta, at: insertionPoint)

        print("✏️ Added charset meta tag to HTML file")
        return modifiedContent
    }

    // If no <head> tag found, return content as-is
    print("⚠️ No <head> tag found in HTML file - skipping charset meta tag addition")
    return content
}
