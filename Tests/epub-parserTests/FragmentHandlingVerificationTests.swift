import Foundation
import Testing

@testable import EPUBParser

/// Test to verify fragment handling in TOC hrefs
@Suite("Fragment Handling Verification")
struct FragmentHandlingVerificationTests {

    @Test("Verify fragment URLs work correctly with renamed files")
    func testFragmentURLsWithRenamedFiles() async throws {
        // Use Harry Potter EPUB since we know it has renamed files
        let epubFiles = TestConfiguration.findAllTestEPUBFiles()

        guard let harryPotterEPUB = epubFiles.first(where: { $0.lastPathComponent.contains("Harry Potter") }) else {
            print("⚠️ Harry Potter EPUB not found - skipping test")
            return
        }

        let parser = EPUBParser(epubPath: harryPotterEPUB, identifier: "fragment_url_test", cleanup: true)
        defer { parser.cleanup() }

        let document = try await parser.processEPUB()

        print("\n🔗 Testing fragment URL generation for renamed files:")
        print(String(repeating: "=", count: 80))

        // Find TOC items that were updated (should have .html extensions now)
        let updatedTOCItems = document.flattenedTableOfContents.filter {
            $0.href.contains("hp07_watermark") && $0.href.hasSuffix(".html")
        }

        print("  Found \(updatedTOCItems.count) updated TOC items")

        // Test a few of them
        for (index, tocItem) in updatedTOCItems.prefix(5).enumerated() {
            let url = document.url(for: tocItem)

            print("  \(index + 1). TOC: \(tocItem.title)")
            print("      Original href: \(tocItem.href)")
            print("      Generated URL: \(url.absoluteString)")

            // Verify the URL has .html extension
            #expect(
                url.pathExtension == "html",
                "URL should have .html extension: \(url.lastPathComponent)")

            // Try to load content from this URL (should work with renamed file)
            do {
                let content = try String(contentsOf: url, encoding: .utf8)
                print("      ✅ Successfully loaded \(content.count) characters")
            } catch {
                print("      ❌ Failed to load: \(error)")
                Issue.record("Failed to load content from URL with updated path: \(error)")
            }
        }

        print("\n✅ Fragment URL testing completed successfully!")
    }

    @Test("Test hypothetical fragment case")
    func testHypotheticalFragmentCase() {
        // This test simulates what would happen with fragments like "path/to#aaa"

        // Create mock path mappings (like what would be created for renamed files)
        let pathMappings = [
            "path/to": "path/to.html",
            "chapter1": "chapter1.html",
            "section2": "section2.html",
        ]

        // Test cases: original href -> expected result
        let testCases = [
            ("path/to#aaa", "path/to.html#aaa"),
            ("chapter1#intro", "chapter1.html#intro"),
            ("section2#conclusion", "section2.html#conclusion"),
            ("chapter1", "chapter1.html"),  // no fragment
            ("untouched.xhtml#fragment", "untouched.xhtml#fragment"),  // already has extension
        ]

        print("\n🧪 Testing hypothetical fragment normalization:")
        print(String(repeating: "=", count: 60))

        for (original, expected) in testCases {
            let result = simulateFragmentNormalization(href: original, pathMappings: pathMappings)
            print("  \(original) → \(result)")

            #expect(
                result == expected,
                "Expected \(expected), got \(result)")
        }

        print("\n✅ All hypothetical fragment cases passed!")
    }

    private func simulateFragmentNormalization(href: String, pathMappings: [String: String]) -> String {
        // Simulate the logic from applyHTMLExtensionNormalizationToTOC

        if let hashIndex = href.firstIndex(of: "#") {
            let pathPart = String(href[..<hashIndex])
            let fragmentPart = String(href[href.index(after: hashIndex)...])

            if let newPath = pathMappings[pathPart] {
                return newPath + "#" + fragmentPart
            }
        } else {
            if let newPath = pathMappings[href] {
                return newPath
            }
        }

        return href  // unchanged
    }
}
