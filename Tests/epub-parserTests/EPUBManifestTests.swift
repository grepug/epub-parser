import Foundation
import Testing

@testable import EPUBParser

/// Tests for EPUB manifest
@Suite("EPUB Manifest")
struct EPUBManifestTests {

    @Test("Manifest structure")
    func testManifestStructure() async throws {
        guard let testEPUBPath = TestConfiguration.findTestEPUBFile() else {
            Issue.record("No test EPUB file found")
            return
        }

        let parser = EPUBParser(epubPath: testEPUBPath, identifier: "manifest_test")
        defer { parser.cleanup() }

        let document = try await parser.processEPUB()

        print("📦 Manifest:")
        print("  Total items: \(document.manifest.count)")

        // Verify manifest is not empty
        #expect(!document.manifest.isEmpty, "Manifest should contain at least one item")

        // Test each manifest item
        for item in document.manifest {
            #expect(!item.id.isEmpty, "Manifest item should have an ID")
            #expect(!item.path.isEmpty, "Manifest item should have a path")
            #expect(!item.mediaType.isEmpty, "Manifest item should have a media type")
        }

        // Count by media type
        let mediaTypes = Dictionary(grouping: document.manifest, by: { $0.mediaType })
        print("  Media types:")
        for (mediaType, items) in mediaTypes.sorted(by: { $0.value.count > $1.value.count }) {
            print("    - \(mediaType): \(items.count) items")
        }

        print("✅ Manifest structure validated")
    }

    @Test("HTML manifest items")
    func testHTMLManifestItems() async throws {
        guard let testEPUBPath = TestConfiguration.findTestEPUBFile() else {
            Issue.record("No test EPUB file found")
            return
        }

        let parser = EPUBParser(epubPath: testEPUBPath, identifier: "html_manifest_test")
        defer { parser.cleanup() }

        let document = try await parser.processEPUB()

        let htmlItems = document.htmlManifestItems

        print("📄 HTML Manifest Items:")
        print("  Total HTML files: \(htmlItems.count)")

        // Should have at least one HTML file
        #expect(!htmlItems.isEmpty, "Should have at least one HTML file")

        // Verify HTML items
        for item in htmlItems {
            let isValidMediaType = item.mediaType == "application/xhtml+xml" || item.mediaType == "text/html"
            let hasHTMLExtension = item.path.hasSuffix(".html") || item.path.hasSuffix(".xhtml") || item.path.hasSuffix(".htm")

            #expect(isValidMediaType || hasHTMLExtension, "HTML item should have valid media type or extension")

            print("  - \(item.path) [\(item.mediaType)]")
        }

        print("✅ HTML manifest items validated")
    }

    @Test("Manifest item lookup")
    func testManifestItemLookup() async throws {
        guard let testEPUBPath = TestConfiguration.findTestEPUBFile() else {
            Issue.record("No test EPUB file found")
            return
        }

        let parser = EPUBParser(epubPath: testEPUBPath, identifier: "manifest_lookup_test")
        defer { parser.cleanup() }

        let document = try await parser.processEPUB()

        print("🔍 Manifest Item Lookup:")

        // Test lookup for first few manifest items
        for item in document.manifest.prefix(5) {
            let found = document.manifestItem(withId: item.id)

            #expect(found != nil, "Should find manifest item by ID")
            #expect(found?.id == item.id, "Found item should have matching ID")
            #expect(found?.path == item.path, "Found item should have matching path")

            print("  ✓ Found: \(item.id) -> \(item.path)")
        }

        // Test lookup for non-existent item
        let notFound = document.manifestItem(withId: "nonexistent_id_12345")
        #expect(notFound == nil, "Should return nil for non-existent ID")

        print("✅ Manifest item lookup validated")
    }

    @Test("Manifest URL generation")
    func testManifestURLGeneration() async throws {
        guard let testEPUBPath = TestConfiguration.findTestEPUBFile() else {
            Issue.record("No test EPUB file found")
            return
        }

        let parser = EPUBParser(epubPath: testEPUBPath, identifier: "manifest_url_test")
        defer { parser.cleanup() }

        let document = try await parser.processEPUB()

        print("🔗 Manifest URL Generation:")

        // Test URL generation for manifest items
        for item in document.manifest.prefix(3) {
            let url = document.url(for: item)

            #expect(url.path.contains(item.path) || url.lastPathComponent == item.path.components(separatedBy: "/").last, "URL should relate to item path")

            print("  - \(item.path)")
            print("    URL: \(url.path)")
        }

        print("✅ Manifest URL generation validated")
    }
}
