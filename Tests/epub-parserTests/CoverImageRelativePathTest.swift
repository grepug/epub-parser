import Foundation
import Testing

@testable import EPUBParser

/// Test cover image URL relative path functionality
struct CoverImageRelativePathTest {

    @Test("Verify cover image URL is stored as relative path")
    func testCoverImageRelativePath() async throws {
        // Find a test EPUB file
        guard let epubPath = findFirstEPUB() else {
            Issue.record("No test EPUB files found")
            return
        }

        let destinationURL = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("EPUBParser_cover_test_\(UUID())")

        let parser = EPUBParser(epubPath: epubPath, destinationURL: destinationURL)
        let document = try await parser.processEPUB()

        // Check if cover image path exists and is relative
        if let coverImagePath = document.metadata.coverImagePath {
            // Should be a relative path, not absolute
            #expect(!coverImagePath.hasPrefix("/var/folders/"), "Cover image path should be relative, not absolute: \(coverImagePath)")
            #expect(!coverImagePath.hasPrefix("/tmp/"), "Cover image path should be relative, not absolute: \(coverImagePath)")
            #expect(!coverImagePath.hasPrefix("/Users/"), "Cover image path should be relative, not absolute: \(coverImagePath)")

            // Should be a valid relative path (no scheme)
            #expect(!coverImagePath.hasPrefix("file://"), "Cover image path should not have file:// scheme")

            print("✅ Cover image path is correctly stored as relative path: \(coverImagePath)")
        } else {
            print("⚠️ No cover image found in this EPUB")
        }

        // Clean up
        try? FileManager.default.removeItem(at: destinationURL)
    }

    // Helper function to find the first EPUB file
    private func findFirstEPUB() -> URL? {
        // Try to find EPUB files in common test directories
        let testPaths = [
            "/Users/kai/Downloads",
            "/Users/kai/Desktop",
            "/Users/kai/Documents",
            FileManager.default.currentDirectoryPath,
        ]

        for basePath in testPaths {
            let enumerator = FileManager.default.enumerator(atPath: basePath)
            while let file = enumerator?.nextObject() as? String {
                if file.lowercased().hasSuffix(".epub") {
                    return URL(fileURLWithPath: basePath).appendingPathComponent(file)
                }
            }
        }

        return nil
    }
}
