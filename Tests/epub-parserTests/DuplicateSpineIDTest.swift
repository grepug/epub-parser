import Foundation
import Testing

@testable import EPUBParser

struct DuplicateSpineIDTest {
    /// Test that duplicate spine item IDs are properly deduplicated
    @Test
    func testAEpubDuplicateSpineIDs() async throws {
        let epubPath = "/Users/kai/Downloads/epub/a.epub"
        
        guard FileManager.default.fileExists(atPath: epubPath) else {
            print("⏭️  Skipping test - a.epub not found")
            return
        }
        
        print("\n🔍 Testing duplicate spine IDs in a.epub")
        
        let document = try await EPUBParser.parse(
            destinationURL: FileManager.default.temporaryDirectory.appendingPathComponent("a_epub_test_\(UUID().uuidString)/v2"),
            epubSourceURL: URL(fileURLWithPath: epubPath)
        )
        
        print("\n📊 Spine items analysis:")
        print("   Total spine items: \(document.spineItems.count)")
        
        // Find duplicates
        var idCounts: [String: Int] = [:]
        for item in document.spineItems {
            idCounts[item.id, default: 0] += 1
        }
        
        let duplicateIds = idCounts.filter { $0.value > 1 }
        print("   Duplicate IDs found: \(duplicateIds.count)")
        
        if !duplicateIds.isEmpty {
            print("\n   ⚠️  Duplicates:")
            for (id, count) in duplicateIds.sorted(by: { $0.key < $1.key }) {
                print("      - id: \"\(id)\" appears \(count) times")
                // Show indices
                let indices = document.spineItems.enumerated()
                    .filter { $0.element.id == id }
                    .map { String($0.offset) }
                print("        indices: [\(indices.joined(separator: ", "))]")
            }
        }
        
        // Verify first few items
        print("\n   First 5 spine items:")
        for (i, item) in document.spineItems.prefix(5).enumerated() {
            print("      [\(i)] id=\"\(item.id)\" index=\(item.index)")
        }
        
        // Verify deduplication - should have no duplicates
        #expect(duplicateIds.isEmpty, "Spine should have no duplicate IDs after deduplication")
        
        // Verify indices are sequential
        for (i, item) in document.spineItems.enumerated() {
            #expect(item.index == i, "Index should match position in array")
        }
    }
}
