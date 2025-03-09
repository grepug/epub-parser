import Foundation
import Testing

@testable import EPUBParser

// Define a variable for test EPUB paths
let testEPUBPath = URL(fileURLWithPath: "/Users/kai/Downloads/Steve_Jobs-by_Walter_Isaacson.epub")

struct EPUBParserTests {
    @Test func testEPUBParserInit() {
        let parser = EPUBParser(epubPath: testEPUBPath, identifier: UUID().uuidString)

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
            try parser.processEPUB()

            // Access the cached chapters
            let chapters = parser.chapters()
            #expect(chapters.isEmpty == false)

            // Verify we have chapters to test
            #expect(chapters.isEmpty == false, "No chapters found")

            let path = "/Users/kai/Developer/packages/epub-parser/test"
            let url = URL(fileURLWithPath: path)

            // Test each chapter
            for chapter in chapters {
                #expect(chapter.manifestItems.isEmpty == false, "Chapter manifest items should not be empty, title: \(chapter.title)")
                #expect(chapter.title.isEmpty == false, "Chapter title should not be empty, title: \(chapter.title)")

                let content = try parser.chapter(id: chapter.id)
                let baseURL = parser.baseURL()
                let html = try! content.combinedHTML(baseURL: baseURL)

                let chapterUrl = url.appending(component: chapter.title)
                try html.write(to: chapterUrl, atomically: true, encoding: .utf8)

                #expect(html.isEmpty == false, "HTML content should not be empty for chapter \(chapter.id), url: \(chapterUrl)")
            }

            print("Successfully tested all \(chapters.count) chapters")
        } catch {
            print(error)

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
        #expect(Bool(true))
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
