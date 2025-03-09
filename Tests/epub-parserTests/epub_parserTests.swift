import Foundation
import Testing

@testable import epub_parser

// Define a variable for test EPUB paths
let testEPUBPath = URL(fileURLWithPath: "/Users/kai/Downloads/epub/88874.epub")

struct EPUBParserTests {
    @Test func testEPUBParserInit() {
        let parser = EPUBParser(epubPath: testEPUBPath, identifier: "testID")

        #expect(parser != nil)
    }

    @Test func testProcessEPUB() async throws {
        // Create a temporary test EPUB file
        let tempDir = FileManager.default.temporaryDirectory
        let testProcessingEPUBPath = tempDir.appendingPathComponent("test.epub")

        // Skip test if can't create test EPUB file
        guard createTestEPUB(at: testEPUBPath) else {
            #expect(Bool(false), "Failed to create test EPUB file")
            return
        }

        let parser = EPUBParser(epubPath: testProcessingEPUBPath, identifier: "testID")

        do {
            try parser.processEPUB()  // Now returns void instead of chapters

            // Access the cached chapters through private property (using reflection for testing)
            let chaptersProperty = Mirror(reflecting: parser).children.first(where: { $0.label == "cachedChapters" })?.value as? [EPUBChapterInfo]
            #expect(chaptersProperty?.isEmpty == false)

            // Verify we have chapters to test
            #expect(chaptersProperty?.isEmpty == false, "No chapters found")

            // Test each chapter
            if let chapters = chaptersProperty {
                for chapter in chapters {
                    #expect(chapter.title.isEmpty == false, "Chapter title should not be empty, id: \(chapter)")

                    let content = try parser.chapterContent(id: chapter.id)
                    let html = content.html

                    #expect(html.isEmpty == false, "HTML content should not be empty for chapter \(chapter.id)")

                    let htmlPath = parser.htmlPathForChapter(id: chapter.id)
                    #expect(htmlPath != nil, "HTML path should not be nil for chapter \(chapter.id)")
                }

                print("Successfully tested all \(chapters.count) chapters")
            }
        } catch {
            #expect(Bool(false), "EPUB processing failed with error: \(error)")
        }

        // Clean up
        parser.cleanup()
        try? FileManager.default.removeItem(at: testProcessingEPUBPath)
    }

    @Test func testCleanup() {
        let parser = EPUBParser(epubPath: testEPUBPath, identifier: "cleanupTest")

        // Just verify this doesn't crash
        parser.cleanup()
        #expect(true)
    }

    @Test func testHtmlPathForChapter() {
        let parser = EPUBParser(epubPath: testEPUBPath, identifier: "pathTest")

        // Since we haven't processed EPUB, attempting to get the HTML path for any ID should return nil
        #expect(parser.htmlPathForChapter(id: "ch1") == nil)
        #expect(parser.htmlPathForChapter(id: "ch2") == nil)
    }

    // Helper function to create a test EPUB file
    func createTestEPUB(at path: URL) -> Bool {
        // Copy the existing EPUB file to the temporary test location
        do {
            let tempDir = FileManager.default.temporaryDirectory
            let testProcessingEPUBPath = tempDir.appendingPathComponent("test.epub")

            // Remove existing file if it exists
            if FileManager.default.fileExists(atPath: testProcessingEPUBPath.path) {
                try FileManager.default.removeItem(at: testProcessingEPUBPath)
            }

            try FileManager.default.copyItem(at: path, to: testProcessingEPUBPath)
            return true
        } catch {
            print("Error creating test EPUB: \(error)")
            return false
        }
    }
}
