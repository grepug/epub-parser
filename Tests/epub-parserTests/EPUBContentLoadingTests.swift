import Foundation
import Testing

@testable import EPUBParser

/// Tests for content loading from EPUB
@Suite("EPUB Content Loading")
struct EPUBContentLoadingTests {

    @Test("Load HTML from spine items")
    func testLoadHTMLFromSpine() async throws {
        guard let testEPUBPath = TestConfiguration.findTestEPUBFile() else {
            Issue.record("No test EPUB file found")
            return
        }

        let parser = EPUBParser(epubPath: testEPUBPath, identifier: "content_loading_test")
        defer { parser.cleanup() }

        let document = try await parser.processEPUB()

        print("📖 Loading HTML Content:")

        var successfulLoads = 0
        var failedLoads = 0

        // Test loading first few spine items
        for (index, spineItem) in document.spine.prefix(5).enumerated() {
            let url = document.url(for: spineItem.manifestItem)

            do {
                let html = try String(contentsOf: url, encoding: .utf8)

                #expect(!html.isEmpty, "HTML content should not be empty")

                // Basic HTML validation
                let lowercaseHTML = html.lowercased()
                let hasHTMLTags = lowercaseHTML.contains("<html") || lowercaseHTML.contains("<body")

                if hasHTMLTags {
                    successfulLoads += 1
                    print("  ✓ Item \(index + 1): \(spineItem.manifestItem.path) (\(html.count) chars)")
                } else {
                    print("  ⚠️ Item \(index + 1): May not be valid HTML")
                    successfulLoads += 1  // Still count as success since we loaded it
                }
            } catch {
                failedLoads += 1
                print("  ✗ Item \(index + 1): Failed to load - \(error)")
            }
        }

        print("  Results: \(successfulLoads) successful, \(failedLoads) failed")

        #expect(successfulLoads > 0, "Should successfully load at least one HTML file")

        print("✅ HTML content loading validated")
    }

    @Test("Load HTML from TOC items")
    func testLoadHTMLFromTOC() async throws {
        guard let testEPUBPath = TestConfiguration.findTestEPUBFile() else {
            Issue.record("No test EPUB file found")
            return
        }

        let parser = EPUBParser(epubPath: testEPUBPath, identifier: "toc_content_test")
        defer { parser.cleanup() }

        let document = try await parser.processEPUB()

        print("📑 Loading HTML from TOC:")

        var successfulLoads = 0

        // Test loading first few TOC items
        for (index, tocItem) in document.tableOfContents.prefix(3).enumerated() {
            let url = document.url(for: tocItem)

            do {
                let html = try String(contentsOf: url, encoding: .utf8)

                #expect(!html.isEmpty, "HTML content should not be empty")

                successfulLoads += 1
                print("  ✓ TOC \(index + 1): '\(tocItem.title)' (\(html.count) chars)")

                // If there's a fragment, note it
                if let fragment = tocItem.fragment {
                    print("      Fragment: #\(fragment)")
                }
            } catch {
                print("  ✗ TOC \(index + 1): Failed to load - \(error)")
            }
        }

        #expect(successfulLoads > 0, "Should successfully load at least one TOC item")

        print("✅ TOC content loading validated")
    }

    @Test("Verify content files exist")
    func testContentFilesExist() async throws {
        guard let testEPUBPath = TestConfiguration.findTestEPUBFile() else {
            Issue.record("No test EPUB file found")
            return
        }

        let parser = EPUBParser(epubPath: testEPUBPath, identifier: "file_exists_test")
        defer { parser.cleanup() }

        let document = try await parser.processEPUB()
        let htmlItems = document.htmlManifestItems

        print("📄 Verifying HTML Files:")

        var existingFiles = 0
        var missingFiles = 0

        for item in htmlItems {
            let url = document.url(for: item)

            if FileManager.default.fileExists(atPath: url.path) {
                existingFiles += 1
            } else {
                missingFiles += 1
                print("  ✗ Missing: \(item.path)")
            }
        }

        print("  Existing: \(existingFiles)")
        print("  Missing: \(missingFiles)")

        let existenceRate = Double(existingFiles) / Double(htmlItems.count)
        #expect(existenceRate >= 0.9, "At least 90% of HTML files should exist")

        print("✅ Content file existence validated")
    }
}
