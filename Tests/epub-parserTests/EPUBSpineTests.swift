import Foundation
import Testing

@testable import EPUBParser

/// Tests for EPUB spine (reading order)
@Suite("EPUB Spine")
struct EPUBSpineTests {

    @Test("Spine structure")
    func testSpineStructure() async throws {
        guard let testEPUBPath = TestConfiguration.findTestEPUBFile() else {
            Issue.record("No test EPUB file found")
            return
        }

        let parser = EPUBParser(epubPath: testEPUBPath, identifier: "spine_test")
        defer { parser.cleanup() }

        let document = try await parser.processEPUB()

        print("📖 Spine Structure:")
        print("  Total items: \(document.spine.count)")

        // Verify spine is not empty
        #expect(!document.spine.isEmpty, "Spine should contain at least one item")

        // Test each spine item
        for (index, spineItem) in document.spine.enumerated() {
            #expect(!spineItem.id.isEmpty, "Spine item \(index + 1) should have an ID")
            #expect(!spineItem.idref.isEmpty, "Spine item \(index + 1) should have an idref")

            // Verify manifest item exists
            #expect(!spineItem.manifestItem.id.isEmpty, "Spine item should reference valid manifest item")
            #expect(!spineItem.manifestItem.path.isEmpty, "Manifest item should have a path")

            let linearFlag = spineItem.linear ? "linear" : "non-linear"
            print("  \(index + 1). [\(linearFlag)] \(spineItem.manifestItem.path)")
        }

        // Test linear spine items
        let linearItems = document.linearSpineItems
        print("  Linear items: \(linearItems.count)/\(document.spine.count)")

        #expect(!linearItems.isEmpty, "Should have at least one linear spine item")
        #expect(linearItems.count <= document.spine.count, "Linear items should not exceed total spine items")

        print("✅ Spine structure validated")
    }

    @Test("Spine to manifest references")
    func testSpineManifestReferences() async throws {
        guard let testEPUBPath = TestConfiguration.findTestEPUBFile() else {
            Issue.record("No test EPUB file found")
            return
        }

        let parser = EPUBParser(epubPath: testEPUBPath, identifier: "spine_manifest_test")
        defer { parser.cleanup() }

        let document = try await parser.processEPUB()

        // Verify all spine items reference valid manifest items
        for spineItem in document.spine {
            let manifestItem = document.manifestItem(withId: spineItem.idref)
            #expect(manifestItem != nil, "Spine item '\(spineItem.idref)' should reference existing manifest item")

            if let item = manifestItem {
                #expect(item.id == spineItem.idref, "Manifest item ID should match spine idref")
                #expect(item.id == spineItem.manifestItem.id, "Referenced manifest item should match embedded item")
            }
        }

        print("✅ All spine items reference valid manifest items")
    }

    @Test("Reading order sequence")
    func testReadingOrderSequence() async throws {
        guard let testEPUBPath = TestConfiguration.findTestEPUBFile() else {
            Issue.record("No test EPUB file found")
            return
        }

        let parser = EPUBParser(epubPath: testEPUBPath, identifier: "reading_order_test")
        defer { parser.cleanup() }

        let document = try await parser.processEPUB()

        print("📚 Reading Order:")

        // Test that spine maintains order
        var previousIndex = -1
        for (index, _) in document.spine.enumerated() {
            #expect(index == previousIndex + 1, "Spine items should be sequential")
            previousIndex = index
        }

        // Test linear reading order
        let linearItems = document.linearSpineItems
        print("  Linear reading sequence: \(linearItems.count) items")

        for (index, item) in linearItems.enumerated() {
            #expect(item.linear, "Linear spine items should have linear flag set")
            print("    \(index + 1). \(item.manifestItem.path)")
        }

        print("✅ Reading order validated")
    }
}
