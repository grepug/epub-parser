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
}
