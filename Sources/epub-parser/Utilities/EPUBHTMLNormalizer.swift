import Foundation

/// Utility for normalizing HTML content in EPUB files
public struct EPUBHTMLNormalizer {
    
    /// Normalize HTML content based on the specified version
    /// - Parameters:
    ///   - content: Original HTML content
    ///   - version: Normalization version to use
    /// - Returns: Normalized HTML content
    public static func normalize(_ content: String, version: EPUBNormalizationVersion) -> String {
        switch version {
        case .v1:
            return normalizeV1(content)
        case .v2:
            return normalizeV2(content)
        }
    }
    
    // MARK: - Version 1 Normalization
    
    /// Version 1: Add charset meta tag + simple line break cleaning
    /// - Only removes excessive newlines (3+ → 2)
    /// - Preserves inline line breaks within element content
    private static func normalizeV1(_ content: String) -> String {
        var normalized = content
        
        // Add charset meta tag if needed
        if !checkForCharsetMeta(in: content) {
            normalized = addCharsetMeta(to: normalized)
        }
        
        // Clean line breaks using v1 algorithm
        normalized = cleanHTMLLineBreaksV1(normalized)
        
        return normalized
    }
    
    /// Version 1: Remove excessive newlines (3+ → 2), trim trailing whitespace
    /// Does NOT remove inline line breaks within element content
    private static func cleanHTMLLineBreaksV1(_ content: String) -> String {
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
    
    // MARK: - Version 2 Normalization
    
    /// Version 2: Add charset meta tag + advanced line break cleaning
    /// - Removes excessive newlines (3+ → 2)
    /// - Removes inline line breaks within HTML elements
    /// - Converts multi-line paragraph content to single lines
    private static func normalizeV2(_ content: String) -> String {
        var normalized = content
        
        // Add charset meta tag if needed
        if !checkForCharsetMeta(in: content) {
            normalized = addCharsetMeta(to: normalized)
        }
        
        // Clean line breaks using v2 algorithm
        normalized = cleanHTMLLineBreaksV2(normalized)
        
        return normalized
    }
    
    /// Version 2: Remove inline line breaks within HTML elements
    /// Converts multi-line paragraph content to single lines
    private static func cleanHTMLLineBreaksV2(_ content: String) -> String {
        // Step 1: Remove line breaks within HTML element content (between > and <)
        // This preserves the HTML structure while making text content continuous
        let pattern = ">([^<]+)<"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else {
            return content
        }
        
        let nsContent = content as NSString
        let range = NSRange(location: 0, length: nsContent.length)
        var cleaned = content
        
        // Process matches in reverse order to maintain indices
        let matches = regex.matches(in: content, options: [], range: range).reversed()
        for match in matches {
            if match.numberOfRanges > 1 {
                let textRange = match.range(at: 1)
                let originalText = nsContent.substring(with: textRange)
                
                // Skip if this is only whitespace (preserve structure between tags)
                let trimmedTest = originalText.trimmingCharacters(in: .whitespacesAndNewlines)
                if trimmedTest.isEmpty {
                    continue
                }
                
                // Replace all whitespace sequences (including newlines) with a single space
                var normalizedText = originalText.replacingOccurrences(
                    of: "\\s+",
                    with: " ",
                    options: .regularExpression
                )
                
                // Only preserve leading/trailing spaces if:
                // - The original had a SINGLE space (not newline/tab)
                // - This indicates intentional spacing (like between inline elements)
                let originalHasSingleLeadingSpace = originalText.first == " " && originalText.count > 1 && !originalText.prefix(2).contains("\n")
                let originalHasSingleTrailingSpace = originalText.last == " " && originalText.count > 1 && !originalText.suffix(2).contains("\n")
                
                // Trim whitespace
                normalizedText = normalizedText.trimmingCharacters(in: .whitespaces)
                
                // Restore single spaces only if they were intentional (not from newlines/indentation)
                if originalHasSingleLeadingSpace && !normalizedText.isEmpty {
                    normalizedText = " " + normalizedText
                }
                if originalHasSingleTrailingSpace && !normalizedText.isEmpty {
                    normalizedText = normalizedText + " "
                }
                
                // Replace in the cleaned string
                let replacement = ">\(normalizedText)<"
                cleaned = (cleaned as NSString).replacingCharacters(in: match.range, with: replacement)
            }
        }
        
        // Step 2: Remove excessive line breaks between HTML tags (more than 2 consecutive newlines)
        cleaned = cleaned.replacingOccurrences(
            of: "\\n\\s*\\n\\s*\\n+",
            with: "\n\n",
            options: .regularExpression
        )

        // Step 3: Trim trailing whitespace from each line
        let lines = cleaned.components(separatedBy: CharacterSet.newlines)
        let processedLines = lines.map { $0.trimmingCharacters(in: CharacterSet.whitespaces) }

        return processedLines.joined(separator: "\n")
    }
    
    // MARK: - Charset Meta Tag Utilities
    
    /// Check if HTML content already contains a charset meta tag in the head section
    private static func checkForCharsetMeta(in content: String) -> Bool {
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
    private static func addCharsetMeta(to content: String) -> String {
        // Pattern to find <head> tag
        guard
            let headRegex = try? NSRegularExpression(
                pattern: "(<head[^>]*>)",
                options: .caseInsensitive
            )
        else {
            return content
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
}
