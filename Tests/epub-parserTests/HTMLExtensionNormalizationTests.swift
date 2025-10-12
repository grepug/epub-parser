import Foundation
import Testing

@testable import EPUBParser

/// Tests for HTML file extension normalization
@Suite("HTML Extension Normalization Tests")
struct HTMLExtensionNormalizationTests {

    @Test("Process EPUB and verify HTML files have .html extension")
    func testHTMLFilesHaveExtension() async throws {
        guard let testEPUBPath = TestConfiguration.findTestEPUBFile() else {
            Issue.record("No test EPUB file found")
            return
        }

        let parser = EPUBParser(epubPath: testEPUBPath, identifier: "html_ext_test", cleanup: true)
        defer { parser.cleanup() }

        let document = try await parser.processEPUB()

        print("\n📋 Checking HTML file extensions:")
        print(String(repeating: "=", count: 60))

        // Get all HTML manifest items
        let htmlItems = document.htmlManifestItems

        print("  Total HTML items: \(htmlItems.count)")

        // Verify all HTML items have proper extensions
        var filesWithoutProperExtension = 0

        for item in htmlItems {
            let path = item.path
            let hasProperExtension = path.hasSuffix(".html") || path.hasSuffix(".xhtml") || path.hasSuffix(".htm")

            if !hasProperExtension {
                filesWithoutProperExtension += 1
                print("  ❌ Missing extension: \(path)")
            } else {
                print("  ✅ \(path)")
            }
        }

        #expect(
            filesWithoutProperExtension == 0,
            "All HTML files should have .html, .xhtml, or .htm extension")

        print("\n✅ All HTML files have proper extensions")
    }

    @Test("URLs generated include .html extension for renamed files")
    func testURLsIncludeHTMLExtension() async throws {
        guard let testEPUBPath = TestConfiguration.findTestEPUBFile() else {
            Issue.record("No test EPUB file found")
            return
        }

        let parser = EPUBParser(epubPath: testEPUBPath, identifier: "html_url_test", cleanup: true)
        defer { parser.cleanup() }

        let document = try await parser.processEPUB()

        print("\n🔗 Checking URLs for HTML files:")
        print(String(repeating: "=", count: 60))

        // Check spine items - these are most likely to be HTML files
        for (index, spineItem) in document.spine.prefix(5).enumerated() {
            let item = spineItem.manifestItem
            let url = document.url(for: item)

            let pathExtension = url.pathExtension.lowercased()
            let hasHTMLExtension = ["html", "xhtml", "htm"].contains(pathExtension)

            print("  Spine \(index + 1): \(url.lastPathComponent)")
            print("    Extension: \(pathExtension)")
            print("    Has HTML ext: \(hasHTMLExtension ? "✅" : "❌")")

            // If it's an HTML content type, it should have HTML extension
            if item.mediaType.contains("html") || item.mediaType.contains("xhtml") {
                #expect(
                    hasHTMLExtension,
                    "HTML content should have HTML extension in URL: \(url.lastPathComponent)")
            }
        }

        print("\n✅ URLs for HTML files include proper extensions")
    }

    @Test("Files can be loaded from URLs with .html extension")
    func testLoadContentFromNormalizedURLs() async throws {
        guard let testEPUBPath = TestConfiguration.findTestEPUBFile() else {
            Issue.record("No test EPUB file found")
            return
        }

        let parser = EPUBParser(epubPath: testEPUBPath, identifier: "load_html_test", cleanup: true)
        defer { parser.cleanup() }

        let document = try await parser.processEPUB()

        print("\n📄 Loading content from normalized URLs:")
        print(String(repeating: "=", count: 60))

        // Try to load content from first few HTML items
        let htmlItems = document.htmlManifestItems.prefix(3)
        var successfulLoads = 0

        for item in htmlItems {
            let url = document.url(for: item)

            do {
                let content = try String(contentsOf: url, encoding: .utf8)
                successfulLoads += 1
                print("  ✅ Loaded \(url.lastPathComponent) (\(content.count) chars)")
            } catch {
                print("  ❌ Failed to load \(url.lastPathComponent): \(error)")
                Issue.record("Failed to load content from normalized URL: \(error)")
            }
        }

        #expect(successfulLoads > 0, "Should successfully load at least one HTML file")

        print("\n✅ Successfully loaded \(successfulLoads) HTML files")
    }
}
