import Foundation
import Testing

@testable import EPUBParser

/// Basic EPUB document parsing tests
@Suite("EPUB Document Parsing")
struct EPUBDocumentTests {

    @Test("Parser initialization")
    func testParserInitialization() async {
        guard let testEPUBPath = TestConfiguration.findTestEPUBFile() else {
            Issue.record("No test EPUB file found. Please add an EPUB file to Downloads directory.")
            return
        }

        let parser = EPUBParser(epubPath: testEPUBPath, identifier: UUID().uuidString)

        // Verify parser starts without cached document
        let document = await parser.document()
        #expect(document == nil, "Parser should start with nil document before processing")
    }

    @Test("EPUB processing and document structure")
    func testEPUBProcessing() async throws {
        guard let testEPUBPath = TestConfiguration.findTestEPUBFile() else {
            Issue.record("No test EPUB file found")
            return
        }

        let parser = EPUBParser(epubPath: testEPUBPath, identifier: "test_processing")
        defer { parser.cleanup() }

        // Process the EPUB
        let document = try await parser.processEPUB()

        // Verify core document structure
        #expect(!document.manifest.isEmpty, "Document should have manifest items")
        #expect(!document.spine.isEmpty, "Document should have spine items")
        #expect(!document.tableOfContents.isEmpty, "Document should have table of contents")

        print("📚 EPUB Document Structure:")
        print("  - Manifest: \(document.manifest.count) items")
        print("  - Spine: \(document.spine.count) items")
        print("  - TOC: \(document.tableOfContents.count) entries")

        // Verify document can be accessed via parser
        let cachedDoc = await parser.document()
        #expect(cachedDoc != nil, "Document should be cached after processing")
    }

    @Test("Invalid EPUB handling")
    func testInvalidEPUBHandling() async {
        let tempDir = FileManager.default.temporaryDirectory
        let invalidPath = tempDir.appendingPathComponent("nonexistent.epub")

        let parser = EPUBParser(epubPath: invalidPath, identifier: "invalid_test")
        defer { parser.cleanup() }

        // Should throw an error when processing non-existent file
        await #expect(throws: Error.self) {
            try await parser.processEPUB()
        }
    }

    @Test("Parser cleanup")
    func testParserCleanup() async throws {
        guard let testEPUBPath = TestConfiguration.findTestEPUBFile() else {
            Issue.record("No test EPUB file found")
            return
        }

        let testDir = try TestConfiguration.createTestDirectory()
        defer {
            try? FileManager.default.removeItem(at: testDir)
        }

        let parser = EPUBParser(
            epubPath: testEPUBPath,
            identifier: "cleanup_test",
            cacheDirectory: testDir
        )

        // Process EPUB to create cache files
        _ = try await parser.processEPUB()

        // Verify cache directory exists
        let cacheDir = testDir.appendingPathComponent("epub_cleanup_test")
        #expect(FileManager.default.fileExists(atPath: cacheDir.path), "Cache directory should exist after processing")

        // Cleanup
        parser.cleanup()

        // Verify cache directory was removed
        #expect(!FileManager.default.fileExists(atPath: cacheDir.path), "Cache directory should be removed after cleanup")
    }

    @Test("Spine item ID lookup by href")
    func testSpineItemIdLookup() async throws {
        guard let testEPUBPath = TestConfiguration.findTestEPUBFile() else {
            Issue.record("No test EPUB file found")
            return
        }

        let parser = EPUBParser(epubPath: testEPUBPath, identifier: "spine_lookup_test")
        defer { parser.cleanup() }

        // Process the EPUB
        let document = try await parser.processEPUB()

        // Test with actual spine items from the document
        guard let firstSpineItem = document.spineItems.first else {
            Issue.record("Document should have at least one spine item")
            return
        }

        let manifestPath = firstSpineItem.manifestItem.path
        print("📋 Testing spine item ID lookup with path: \(manifestPath)")

        // Test 1: Direct path match
        let foundId1 = document.spineItemId(for: manifestPath)
        #expect(foundId1 == firstSpineItem.id, "Should find spine item by direct path match")

        // Test 2: Path with fragment
        let pathWithFragment = "\(manifestPath)#section1"
        let foundId2 = document.spineItemId(for: pathWithFragment)
        #expect(foundId2 == firstSpineItem.id, "Should find spine item by path with fragment")

        // Test 3: Filename only
        let filename = URL(fileURLWithPath: manifestPath).lastPathComponent
        let foundId3 = document.spineItemId(for: filename)
        #expect(foundId3 == firstSpineItem.id, "Should find spine item by filename")

        // Test 4: Filename with fragment
        let filenameWithFragment = "\(filename)#anchor"
        let foundId4 = document.spineItemId(for: filenameWithFragment)
        #expect(foundId4 == firstSpineItem.id, "Should find spine item by filename with fragment")

        // Test 5: Absolute URL (simulated)
        let baseUrlString = document.baseURL.absoluteString
        let absoluteUrl = "\(baseUrlString)\(manifestPath)"
        let foundId5 = document.spineItemId(for: absoluteUrl)
        #expect(foundId5 == firstSpineItem.id, "Should find spine item by absolute URL")

        // Test 6: Non-existent file
        let foundId6 = document.spineItemId(for: "nonexistent.html")
        #expect(foundId6 == nil, "Should return nil for non-existent file")

        // Test 7: Empty href
        let foundId7 = document.spineItemId(for: "")
        #expect(foundId7 == nil, "Should return nil for empty href")

        // Test 8: Path with leading slash
        let pathWithSlash = "/\(manifestPath)"
        let foundId8 = document.spineItemId(for: pathWithSlash)
        #expect(foundId8 == firstSpineItem.id, "Should find spine item by path with leading slash")

        print("✅ All spine item ID lookup tests passed")
        print("   - Found spine item: \(firstSpineItem.id) for path: \(manifestPath)")
    }

    @Test("Spine item ID lookup by URL object")
    func testSpineItemIdLookupWithURL() async throws {
        guard let testEPUBPath = TestConfiguration.findTestEPUBFile() else {
            Issue.record("No test EPUB file found")
            return
        }

        let parser = EPUBParser(epubPath: testEPUBPath, identifier: "spine_url_lookup_test")
        defer { parser.cleanup() }

        // Process the EPUB
        let document = try await parser.processEPUB()

        // Test with actual spine items from the document
        guard let firstSpineItem = document.spineItems.first else {
            Issue.record("Document should have at least one spine item")
            return
        }

        let manifestPath = firstSpineItem.manifestItem.path
        print("📋 Testing spine item ID lookup with URL object for path: \(manifestPath)")

        // Test 1: URL from manifest item path
        let manifestURL = URL(fileURLWithPath: manifestPath)
        let foundId1 = document.spineItemId(for: manifestURL)
        #expect(foundId1 == firstSpineItem.id, "Should find spine item by URL object")

        // Test 2: URL with base path
        let fullURL = document.baseURL.appending(path: manifestPath)
        let foundId2 = document.spineItemId(for: fullURL)
        #expect(foundId2 == firstSpineItem.id, "Should find spine item by full URL")

        // Test 3: URL with fragment
        var urlComponents = URLComponents()
        urlComponents.scheme = "file"
        urlComponents.path = "/" + manifestPath
        urlComponents.fragment = "section1"

        if let urlWithFragment = urlComponents.url {
            let foundId3 = document.spineItemId(for: urlWithFragment)
            #expect(foundId3 == firstSpineItem.id, "Should find spine item by URL with fragment")
        }

        print("✅ URL overload spine item ID lookup tests passed")
        print("   - Found spine item: \(firstSpineItem.id) for URL: \(manifestURL)")
    }
}
