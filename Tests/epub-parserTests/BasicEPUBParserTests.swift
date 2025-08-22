import Foundation
import Testing

@testable import EPUBParser

/// Basic EPUB parser functionality tests
struct BasicEPUBParserTests {

    @Test func testEPUBParserInitialization() async {
        guard let testEPUBPath = TestConfiguration.findTestEPUBFile() else {
            Issue.record("No test EPUB file found. Please ensure there's an EPUB file in Downloads directory.")
            return
        }

        let parser = EPUBParser(epubPath: testEPUBPath, identifier: UUID().uuidString)

        // Verify parser was created successfully
        let chapters = await parser.chapters()
        #expect(chapters.isEmpty, "Parser should start with empty chapters before processing")
    }

    @Test func testEPUBProcessing() async throws {
        guard let originalEPUBPath = TestConfiguration.findTestEPUBFile() else {
            Issue.record("No test EPUB file found. Please ensure there's an EPUB file in Downloads directory.")
            return
        }

        let testDir = try TestConfiguration.createTestDirectory()
        defer {
            try? FileManager.default.removeItem(at: testDir)
        }

        let testEPUBPath = testDir.appendingPathComponent("test.epub")

        // Copy the test file to a temporary location
        try FileManager.default.copyItem(at: originalEPUBPath, to: testEPUBPath)

        let parser = EPUBParser(epubPath: testEPUBPath, identifier: "testProcessing")
        defer {
            parser.cleanup()
        }

        // Process the EPUB
        do {
            try await parser.processEPUB()
        } catch {
            Issue.record("Failed to process EPUB: \(error.localizedDescription)")
            return
        }

        // Verify chapters were extracted
        let chapters = await parser.chapters()
        #expect(!chapters.isEmpty, "EPUB should contain at least one chapter")

        print("📚 Successfully processed EPUB with \(chapters.count) chapters")

        // Test each chapter
        for (index, chapter) in chapters.enumerated() {
            #expect(!chapter.id.isEmpty, "Chapter \(index + 1) should have a valid ID")
            #expect(!chapter.title.isEmpty, "Chapter \(index + 1) should have a valid title")
            #expect(!chapter.path.isEmpty, "Chapter \(index + 1) should have a valid path")

            // Verify chapter has content
            do {
                let chapterContent = try await parser.chapter(id: chapter.id)
                #expect(!chapterContent.manifestItems.isEmpty, "Chapter '\(chapter.title)' should have manifest items")

                let baseURL = await parser.baseURL()
                let html = try chapterContent.combinedHTML(baseURL: baseURL)
                #expect(!html.isEmpty, "Chapter '\(chapter.title)' should generate non-empty HTML")

                print("  ✓ Chapter \(index + 1): '\(chapter.title)' (\(chapterContent.manifestItems.count) items)")

            } catch {
                Issue.record("Failed to process chapter '\(chapter.title)': \(error.localizedDescription)")
            }
        }

        print("🎉 Successfully validated all chapters")
    }

    @Test func testEPUBParserCleanup() async throws {
        guard let testEPUBPath = TestConfiguration.findTestEPUBFile() else {
            Issue.record("No test EPUB file found for cleanup test")
            return
        }

        let testDir = try TestConfiguration.createTestDirectory()
        defer {
            try? FileManager.default.removeItem(at: testDir)
        }

        let parser = EPUBParser(
            epubPath: testEPUBPath,
            identifier: "cleanupTest",
            cacheDirectory: testDir
        )

        // Process EPUB to create cache files
        try await parser.processEPUB()

        // Verify cache directory was created
        let cacheDir = testDir.appendingPathComponent("epub_cleanupTest")
        #expect(FileManager.default.fileExists(atPath: cacheDir.path), "Cache directory should exist after processing")

        // Test cleanup
        parser.cleanup()

        // Verify cache directory was removed
        #expect(!FileManager.default.fileExists(atPath: cacheDir.path), "Cache directory should be removed after cleanup")
    }

    @Test func testInvalidEPUBHandling() async {
        let tempDir = FileManager.default.temporaryDirectory
        let invalidPath = tempDir.appendingPathComponent("nonexistent.epub")

        let parser = EPUBParser(epubPath: invalidPath, identifier: "invalidTest")
        defer {
            parser.cleanup()
        }

        // Should throw an error when trying to process non-existent file
        await #expect(throws: Error.self) {
            try await parser.processEPUB()
        }
    }
}
