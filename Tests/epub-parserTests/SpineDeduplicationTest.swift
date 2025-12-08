import Foundation
import Testing

@testable import EPUBParser

struct SpineDeduplicationTest {
    /// Test that duplicate spine item IDs are properly deduplicated
    @Test
    func testSpineDuplicateIDDeduplication() async throws {
        // This test verifies that when an EPUB has duplicate itemref IDs in the spine,
        // only the first occurrence is kept and subsequent duplicates are removed

        let testEPUBs = [
            "/Users/kai/Downloads/epub/TheEconomist.2025.11.01.epub",
            "/Users/kai/Downloads/epub/考研英语黄皮书 2015.12~2016.5.epub",
        ]

        for epubPath in testEPUBs {
            guard FileManager.default.fileExists(atPath: epubPath) else {
                print("⏭️  Skipping \(epubPath) - file not found")
                continue
            }

            print("\n🔍 Testing spine deduplication for: \(URL(fileURLWithPath: epubPath).lastPathComponent)")

            let document = try await EPUBParser.parse(
                destinationURL: FileManager.default.temporaryDirectory.appendingPathComponent("epub_test_\(UUID().uuidString)/v2"),
                epubSourceURL: URL(fileURLWithPath: epubPath)
            )

            // Check for duplicate IDs in spine items
            var seenIds = Set<String>()
            var duplicateCount = 0

            for item in document.spineItems {
                if seenIds.contains(item.id) {
                    duplicateCount += 1
                    print("  ⚠️  Found duplicate ID: \(item.id) at index \(item.index)")
                } else {
                    seenIds.insert(item.id)
                }
            }

            print("  📊 Spine item statistics:")
            print("     Total items: \(document.spineItems.count)")
            print("     Unique IDs: \(seenIds.count)")
            print("     Duplicate IDs found: \(duplicateCount)")

            // After deduplication, there should be no duplicates
            #expect(duplicateCount == 0, "Spine items should have no duplicate IDs")

            // Verify indices are sequential (0-based)
            for (index, item) in document.spineItems.enumerated() {
                #expect(item.index == index, "Spine item indices should be sequential starting from 0")
            }

            print("  ✅ Deduplication verified - no duplicate IDs found")
        }
    }
}
