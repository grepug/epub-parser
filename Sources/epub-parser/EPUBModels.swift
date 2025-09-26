import Foundation
import SwiftSoup

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
            var fragmentId: String? = nil

            // Check if this is a fragment-based reference (like book_0005.xhtml#auto-toc0)
            if path.contains("#") && item.path == path.components(separatedBy: "#").first {
                fragmentId = path.components(separatedBy: "#").last
            }

            if item.path.starts(with: "/") {
                // Handle absolute paths by removing the leading slash and appending to the EPUB root
                url = baseURL.deletingLastPathComponent().appendingPathComponent(String(item.path.dropFirst()))
            } else {
                // Handle relative paths by resolving against the baseURL
                url = URL(string: item.path, relativeTo: baseURL) ?? baseURL.appendingPathComponent(item.path)
            }

            guard url.lastPathComponent.firstMatch(of: #/\.x?html?/#) != nil else { return nil }

            var content = try String(contentsOf: url, encoding: .utf8)

            // If this is a fragment-based chapter, try to extract the specific section
            if let fragmentId = fragmentId, !fragmentId.isEmpty {
                content = extractFragmentContent(from: content, fragmentId: fragmentId, currentFileURL: url)
            }

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
    private func extractPlainText(from html: String) -> String {
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
    private func countWords(in text: String) -> Int {
        let words = text.components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
        return words.count
    }

    /// Extracts content for a specific fragment/section from HTML using SwiftSoup
    private func extractFragmentContent(from html: String, fragmentId: String, currentFileURL: URL) -> String {
        // Debug info for troubleshooting
        print("🔍 Extracting fragment '\(fragmentId)' from HTML (\(html.count) chars)")

        do {
            let doc = try SwiftSoup.parse(html)

            // Strategy 1: Find element with exact ID match
            if let fragmentElement = try doc.select("#\(fragmentId)").first() {
                // If it's just an anchor tag, it's likely just a navigation marker
                // Check if this is a title page (small content) and we need to get the next file
                if fragmentElement.tagName() == "a" {
                    if let bodyElement = try doc.select("body").first() {
                        let bodyContent = try bodyElement.html()

                        // Check if this appears to be a title page rather than substantial content
                        if isTitlePageContent(bodyContent) {
                            print("📄 Detected title page, looking for related content file...")

                            // Try to get content from a related file
                            if let nextContent = tryGetNextContentFile(currentFileURL: currentFileURL) {
                                return nextContent
                            }
                        }

                        return bodyContent
                    }
                } else {
                    let content = try extractSectionContent(from: fragmentElement, in: doc)
                    print("✅ Found fragment by ID, content length: \(content.count)")
                    return content
                }
            } else {
                print("❌ No element found with ID '\(fragmentId)'")
            }

            // Strategy 2: Find anchor with name attribute
            if let anchorElement = try doc.select("a[name=\(fragmentId)]").first() {
                let content = try extractSectionContent(from: anchorElement, in: doc)
                print("✅ Found fragment by name attribute, content length: \(content.count)")
                return content
            } else {
                print("❌ No anchor found with name '\(fragmentId)'")
            }

            // Strategy 3: For indexed fragments (auto-toc, toc, chapter, etc.), try to find by index
            let indexPatterns = [
                (#/auto-toc(\d+)/#, "auto-toc"),
                (#/toc-?(\d+)/#, "toc"),
                (#/chapter-?(\d+)/#, "chapter"),
                (#/section-?(\d+)/#, "section"),
                (#/part-?(\d+)/#, "part"),
            ]

            for (pattern, patternName) in indexPatterns {
                if let match = fragmentId.firstMatch(of: pattern) {
                    let numberString = String(match.1)
                    if let sectionIndex = Int(numberString) {
                        let content = try extractContentByIndex(sectionIndex, from: doc)
                        print("✅ Found content by \(patternName) index \(sectionIndex), content length: \(content.count)")
                        return content
                    } else {
                        print("❌ Could not parse index from '\(fragmentId)' using pattern \(patternName)")
                    }
                }
            }

            // Strategy 4: Fallback - return body content
            if let bodyElement = try doc.select("body").first() {
                let bodyContent = try bodyElement.html()
                print("⚠️ Using fallback body content, length: \(bodyContent.count)")
                return bodyContent
            } else {
                print("❌ No body element found")
            }

        } catch {
            print("❌ SwiftSoup parsing failed: \(error)")
            // If SwiftSoup parsing fails, fall back to regex approach
            return extractFragmentContentWithRegex(from: html, fragmentId: fragmentId)
        }

        // Final fallback - return original content
        print("⚠️ Using final fallback - original HTML")
        return html
    }

    /// Extracts content from a specific element and its following siblings until next major element
    private func extractSectionContent(from element: Element, in doc: Document) throws -> String {
        var content = try element.outerHtml()

        // Get following siblings until we hit another heading or element with ID
        var currentElement = element
        while let nextSibling = try currentElement.nextElementSibling() {
            let tagName = nextSibling.tagName()

            // Stop if we hit another heading, element with ID, or major structural element
            if tagName.lowercased().starts(with: "h") || nextSibling.hasAttr("id") || ["div", "section", "article"].contains(tagName.lowercased()) {
                break
            }

            content += try nextSibling.outerHtml()
            currentElement = nextSibling
        }

        return content
    }

    /// Extracts content by section index (for auto-toc style fragments)
    private func extractContentByIndex(_ index: Int, from doc: Document) throws -> String {
        // Try different strategies to find the nth section

        // Strategy 1: Find by headings
        let headings = try doc.select("h1, h2, h3, h4, h5, h6")
        if index < headings.count {
            let heading = headings[index]
            return try extractSectionContent(from: heading, in: doc)
        }

        // Strategy 2: Find by divs or sections with content
        let sections = try doc.select("div, section, article").filter { element in
            ((try? element.text().count) ?? 0) > 50  // Only substantial content
        }
        if index < sections.count {
            return try sections[index].outerHtml()
        }

        // Strategy 3: Find by paragraphs groups
        let paragraphs = try doc.select("p")
        let chunkSize = max(1, paragraphs.count / 10)  // Divide into roughly 10 sections
        let startIndex = index * chunkSize
        let endIndex = min(startIndex + chunkSize, paragraphs.count)

        if startIndex < paragraphs.count {
            let selectedParagraphs = Array(paragraphs[startIndex..<endIndex])
            return selectedParagraphs.compactMap { try? $0.outerHtml() }.joined(separator: "\n")
        }

        // Fallback: return body content
        if let bodyElement = try doc.select("body").first() {
            return try bodyElement.html()
        }

        return ""
    }

    /// Fallback regex-based fragment extraction (simplified version of original)
    private func extractFragmentContentWithRegex(from html: String, fragmentId: String) -> String {
        // Simple fallback - just return body content if available
        do {
            let bodyRegex = try NSRegularExpression(pattern: #"<body[^>]*>(.*?)</body>"#, options: [.caseInsensitive, .dotMatchesLineSeparators])
            let range = NSRange(location: 0, length: html.utf16.count)
            if let match = bodyRegex.firstMatch(in: html, options: [], range: range),
                let bodyRange = Range(match.range(at: 1), in: html)
            {
                return String(html[bodyRange])
            }
        } catch {
            // Continue to final fallback
        }

        return html
    }

    /// Gets all content following an element (useful for anchor tags that mark positions)
    private func getAllFollowingContent(from element: Element, in doc: Document) throws -> String {
        var content = ""
        var currentElement = element

        // Get all following siblings
        while let nextSibling = try currentElement.nextElementSibling() {
            content += try nextSibling.outerHtml()
            currentElement = nextSibling
        }

        // If no siblings found, try to get parent's remaining content
        if content.isEmpty, let parent = element.parent() {
            let parentHTML = try parent.html()
            let elementHTML = try element.outerHtml()

            if let elementRange = parentHTML.range(of: elementHTML) {
                let remainingContent = String(parentHTML[elementRange.upperBound...])
                return remainingContent
            }
        }

        return content
    }

    /// Tries to get content from related files when current file appears to be a title page
    /// This handles EPUBs where chapters are split between title pages and content files
    /// Uses multiple strategies to find related content files
    private func tryGetNextContentFile(currentFileURL: URL) -> String? {
        let currentFileName = currentFileURL.lastPathComponent
        print("🔎 Current file: \(currentFileName)")
        print("🔎 Current URL: \(currentFileURL)")

        // Strategy 1: Common numbered file patterns
        let numberPatterns = [
            #/(\w+_)(\d+)(\.x?html?)/#,  // book_0005.xhtml, chapter_01.html, etc.
            #/(\w+)(\d+)(\.x?html?)/#,  // book5.xhtml, chapter1.html, etc.
            #/(\w+-)(\d+)(\.x?html?)/#,  // book-05.xhtml, chapter-1.html, etc.
        ]

        for pattern in numberPatterns {
            if let match = currentFileName.firstMatch(of: pattern) {
                let prefix = String(match.1)
                let numberString = String(match.2)
                let suffix = String(match.3)

                if let currentNumber = Int(numberString) {
                    // Try several sequential files (not just +1)
                    for offset in [1, 2, 3] {
                        let nextNumber = currentNumber + offset

                        // Preserve original number formatting (zero-padding)
                        let formattedNumber: String
                        if numberString.hasPrefix("0") && numberString.count > 1 {
                            // Zero-padded format
                            formattedNumber = String(format: "%0\(numberString.count)d", nextNumber)
                        } else {
                            // Simple number format
                            formattedNumber = String(nextNumber)
                        }

                        let nextFileName = "\(prefix)\(formattedNumber)\(suffix)"
                        let nextURL = currentFileURL.deletingLastPathComponent().appendingPathComponent(nextFileName)

                        if let content = tryLoadContentFile(url: nextURL, fileName: nextFileName) {
                            return content
                        }
                    }
                }
            }
        }

        // Strategy 2: Look for files with similar names but different suffixes
        // e.g., chapter1_title.html -> chapter1_content.html, chapter1.html
        let baseFileName = currentFileName.replacingOccurrences(of: #"\.x?html?$"#, with: "", options: .regularExpression)
        let fileExtension = String(currentFileName.suffix(from: currentFileName.lastIndex(of: ".") ?? currentFileName.endIndex))

        let commonSuffixes = ["", "_content", "_text", "_body", "_full"]
        let commonPrefixes = ["", "content_", "text_", "body_"]

        for prefix in commonPrefixes {
            for suffix in commonSuffixes {
                let candidateFileName = "\(prefix)\(baseFileName)\(suffix)\(fileExtension)"
                if candidateFileName != currentFileName {
                    let candidateURL = currentFileURL.deletingLastPathComponent().appendingPathComponent(candidateFileName)
                    if let content = tryLoadContentFile(url: candidateURL, fileName: candidateFileName) {
                        return content
                    }
                }
            }
        }

        print("❌ No related content files found for pattern: \(currentFileName)")
        return nil
    }

    /// Determines if content appears to be a title page rather than substantial chapter content
    private func isTitlePageContent(_ htmlContent: String) -> Bool {
        // Convert to plain text for analysis
        let plainText = extractPlainText(from: htmlContent)

        // Multiple criteria for title page detection
        let wordCount = countWords(in: plainText)
        let charCount = htmlContent.count

        // Size-based detection
        if charCount < 500 && wordCount < 20 {
            return true
        }

        // Content pattern analysis (common title page indicators)
        let lowercaseText = plainText.lowercased()
        let titlePageKeywords = [
            "chapter", "part", "section", "book",
            "first day", "second day", "third day",  // Common in this EPUB
            "prologue", "epilogue", "introduction",
        ]

        // If content is mostly just title/chapter markers
        let hasOnlyTitleKeywords = titlePageKeywords.contains { keyword in
            lowercaseText.contains(keyword) && wordCount <= 10
        }

        // If content has very few sentences (likely just a title)
        let sentenceCount = plainText.components(separatedBy: CharacterSet(charactersIn: ".!?")).count - 1
        let hasFewSentences = sentenceCount <= 2 && wordCount < 15

        return hasOnlyTitleKeywords || hasFewSentences
    }

    /// Helper method to try loading content from a URL and extract body content
    private func tryLoadContentFile(url: URL, fileName: String) -> String? {
        do {
            let content = try String(contentsOf: url, encoding: .utf8)
            print("📖 Found candidate file: \(fileName) (\(content.count) chars)")

            // Only return if the content is substantially larger (indicating real content vs title page)
            if content.count > 1000 {  // Configurable threshold
                // Extract body content using SwiftSoup
                let doc = try SwiftSoup.parse(content)
                if let bodyElement = try doc.select("body").first() {
                    let bodyHTML = try bodyElement.html()

                    // Double-check it's not another title page
                    if !isTitlePageContent(bodyHTML) {
                        print("✅ Using substantial content from \(fileName)")
                        return bodyHTML
                    } else {
                        print("⚠️ File \(fileName) is also a title page, continuing search")
                    }
                }
            } else {
                print("⚠️ File \(fileName) too small (\(content.count) chars), skipping")
            }
        } catch {
            // File doesn't exist or can't be read - this is expected during search
            // print("🔍 File \(fileName) not found, continuing search")
        }
        return nil
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
