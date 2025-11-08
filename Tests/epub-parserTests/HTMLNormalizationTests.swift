import Foundation
import Testing

@testable import EPUBParser

@Suite("HTML Normalization Tests")
struct HTMLNormalizationTests {
    
    @Test("Test Hobbit HTML file normalization")
    func testHobbitHTMLNormalization() async throws {
        let hobbitHTMLPath = "/Users/kai/Downloads/epubtest/The Hobbit (Tolkien, J R R) (Z-Library)/OPS/Hobbit_chap-1.html"
        
        guard FileManager.default.fileExists(atPath: hobbitHTMLPath) else {
            print("ℹ️ Hobbit HTML file not found - skipping test")
            return
        }
        
        print("🔍 Testing HTML normalization with Hobbit file...")
        
        // Read the original content
        let originalContent = try String(contentsOfFile: hobbitHTMLPath, encoding: .utf8)
        
        print("\n📄 Original content sample (first 500 chars):")
        print(String(originalContent.prefix(500)))
        
        // Apply normalization using the actual normalizer
        let normalizedContent = EPUBParser.testNormalizeHTML(originalContent)
        
        print("\n✨ Normalized content sample (first 500 chars):")
        print(String(normalizedContent.prefix(500)))
        
        // Check that we didn't add extra line breaks
        let originalLineCount = originalContent.components(separatedBy: .newlines).count
        let normalizedLineCount = normalizedContent.components(separatedBy: .newlines).count
        
        print("\n📊 Statistics:")
        print("   Original lines: \(originalLineCount)")
        print("   Normalized lines: \(normalizedLineCount)")
        print("   Difference: \(normalizedLineCount - originalLineCount)")
        
        // Check specific patterns
        let originalParagraphPattern = #"<p[^>]*>.*?</p>"#
        let originalPMatches = originalContent.ranges(of: try Regex(originalParagraphPattern))
        let normalizedPMatches = normalizedContent.ranges(of: try Regex(originalParagraphPattern))
        
        print("   Paragraph tags: \(originalPMatches.count) -> \(normalizedPMatches.count)")
        
        // Verify normalization didn't break HTML structure
        #expect(normalizedContent.contains("<html"), "HTML structure should be preserved")
        #expect(normalizedContent.contains("<body"), "Body tag should be preserved")
        #expect(normalizedContent.contains("</html>"), "HTML closing tag should be preserved")
        
        // Check that multiple consecutive newlines are reduced
        let hasExcessiveNewlines = normalizedContent.contains("\n\n\n")
        #expect(!hasExcessiveNewlines, "Should not have 3+ consecutive newlines")
        
        print("\n✅ HTML normalization test completed")
    }
    
    @Test("Test simple line break cleaning")
    func testSimpleLineBreakCleaning() throws {
        let input = """
        <p>This is a test


        with excessive newlines</p>
        
        <p>Another paragraph    </p>
        """
        
        let output = EPUBParser.testNormalizeHTML(input)
        
        // Should reduce 3+ newlines to 2
        #expect(!output.contains("\n\n\n"), "Should not have 3+ consecutive newlines")
        
        // Should trim trailing whitespace from text content
        #expect(!output.contains("paragraph    "), "Should trim trailing whitespace")
        
        print("✅ Simple line break cleaning test passed")
    }
    
    @Test("Test paragraph content line breaks")
    func testParagraphContentLineBreaks() throws {
        let input = """
        <p>This paragraph has
        line breaks in the
        middle of sentences that
        should be removed.</p>
        """
        
        // Test v1 - should preserve inline breaks
        let outputV1 = EPUBParser.testNormalizeHTML(input, version: .v1)
        let hasInlineBreaksV1 = outputV1.contains("has\n")
        print("V1 has inline breaks: \(hasInlineBreaksV1)")
        #expect(hasInlineBreaksV1, "V1 should preserve line breaks within paragraph content")
        
        // Test v2 - should remove inline breaks
        let outputV2 = EPUBParser.testNormalizeHTML(input, version: .v2)
        
        print("\nInput:")
        print(input)
        print("\nV2 Output:")
        print(outputV2)
        
        let hasInlineBreaksV2 = outputV2.contains("has\n")
        print("\nV2 has inline breaks: \(hasInlineBreaksV2)")
        
        // With v2, inline breaks should be removed
        #expect(!hasInlineBreaksV2, "V2 should remove line breaks within paragraph content")
    }
}
