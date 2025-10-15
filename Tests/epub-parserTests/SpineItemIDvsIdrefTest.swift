import Foundation
import Testing

@testable import EPUBParser

struct SpineItemIDvsIndexTest {

    @Test("Debug spine item ID vs index confusion")
    func testSpineItemIDvsIndex() async throws {
        // Find a test EPUB file
        guard let epubURL = TestConfiguration.findTestEPUBFile() else {
            Issue.record("No test EPUB file found. Please add an EPUB file to the configured test directories.")
            return
        }

        // Create a destination URL for this test
        let destinationURL = TestConfiguration.testDestinationURL(for: "spine_id_vs_index")

        // Initialize and process
        let parser = EPUBParser(
            epubPath: epubURL,
            destinationURL: destinationURL,
            skipUnzipIfDirectoryExists: true,
            cleanup: false
        )

        let document = try await parser.processEPUB()

        print("\n=== SPINE ITEM ID vs INDEX DEBUG ===")

        // Debug the first few spine items to understand the structure
        for (index, spineItem) in document.spine.prefix(5).enumerated() {
            print("[\(index)] Spine Item:")
            print("  spineItem.id: '\(spineItem.id)'")  // Now contains EPUB manifest ID (e.g., "ch01" or "cover")
            print("  spineItem.index: \(spineItem.index)")  // Sequential index (e.g., 0, 1, 2)
            print("  manifestItem.id: '\(spineItem.manifestItem.id)'")  // Should match spineItem.id
            print("  manifestItem.path: '\(spineItem.manifestItem.path)'")
            print("")
        }

        // Test what spineItemId() currently returns
        if let firstSpineItem = document.spine.first {
            let manifestPath = firstSpineItem.manifestItem.path
            let result = document.spineItemId(for: manifestPath)

            print("spineItemId(for: '\(manifestPath)') returns: '\(result ?? "nil")'")
            print("This matches spineItem.id: \(result == firstSpineItem.id)")
            print("")
        }

        // Check what the user might be looking for
        print("Now spine IDs contain the EPUB manifest identifiers:")
        let spineIds = document.spine.map { $0.id }
        print("spineItems.map { $0.id }: \(spineIds)")

        let spineIndices = document.spine.map { $0.index }
        print("spineItems.map { $0.index }: \(spineIndices)")

        // Check if "ch01" is in the IDs
        if spineIds.contains("ch01") {
            print("✅ 'ch01' found in spine IDs - spineItemId() correctly returns spine item id")
        } else {
            print("❓ 'ch01' not found in spine IDs")
        }

        print("\n=== END DEBUG ===\n")

        // Cleanup
        try? FileManager.default.removeItem(at: destinationURL)
    }
}
