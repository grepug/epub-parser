import Foundation

// MARK: - EPUBChapter Text Processing

extension EPUBChapter {
    /// Extracts plain text from HTML content and counts words
    /// - Parameters:
    ///   - baseURL: The base URL to resolve relative paths against
    ///   - cleanLineBreaks: Whether to remove unnecessary line breaks from HTML elements
    /// - Returns: Word count for the chapter content
    public func wordCount(baseURL: URL, cleanLineBreaks: Bool = true) throws -> Int {
        let htmlContent = try combinedHTML(baseURL: baseURL, cleanLineBreaks: cleanLineBreaks)
        let plainText = extractPlainText(from: htmlContent)
        return countWords(in: plainText)
    }

    /// Extracts plain text from HTML content by removing tags and decoding entities
    internal func extractPlainText(from html: String) -> String {
        var text = html

        // Remove script and style content completely
        let scriptStyleRegex = try! NSRegularExpression(pattern: "<(script|style)[^>]*>.*?</\\1>", options: [.caseInsensitive, .dotMatchesLineSeparators])
        text = scriptStyleRegex.stringByReplacingMatches(in: text, options: [], range: NSRange(location: 0, length: text.utf16.count), withTemplate: "")

        // Remove HTML tags but preserve content
        let tagRegex = try! NSRegularExpression(pattern: "<[^>]*>", options: [])
        text = tagRegex.stringByReplacingMatches(in: text, options: [], range: NSRange(location: 0, length: text.utf16.count), withTemplate: "")

        // Decode common HTML entities
        text =
            text
            .replacingOccurrences(of: "&nbsp;", with: " ")
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#39;", with: "'")
            .replacingOccurrences(of: "&apos;", with: "'")

        // Normalize whitespace
        text =
            text
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\r", with: " ")
            .replacingOccurrences(of: "\t", with: " ")
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        return text
    }

    /// Counts words in a plain text string
    internal func countWords(in text: String) -> Int {
        let words = text.components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
        return words.count
    }
}
