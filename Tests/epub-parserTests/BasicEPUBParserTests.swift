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
        let document = await parser.document()
        #expect(document == nil, "Parser should start with nil document before processing")
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
        let document: EPUBDocument
        do {
            document = try await parser.processEPUB()
        } catch {
            Issue.record("Failed to process EPUB: \(String(describing: error))")
            return
        }

        // Verify document structure
        #expect(!document.manifest.isEmpty, "EPUB should have manifest items")
        #expect(!document.spine.isEmpty, "EPUB should have spine items")
        #expect(!document.tableOfContents.isEmpty, "EPUB should have table of contents")

        print("📚 Successfully processed EPUB:")
        print("  - Manifest: \(document.manifest.count) items")
        print("  - Spine: \(document.spine.count) items")
        print("  - TOC: \(document.tableOfContents.count) top-level items")

        // Test metadata
        if let title = document.metadata.title {
            print("  - Title: \(title)")
        }
        if !document.metadata.creators.isEmpty {
            print("  - Authors: \(document.metadata.creatorsString)")
        }

        // Test manifest items
        let htmlItems = document.htmlManifestItems
        #expect(!htmlItems.isEmpty, "EPUB should have HTML content files")
        print("  - HTML files: \(htmlItems.count)")

        // Test spine items
        let linearItems = document.linearSpineItems
        #expect(!linearItems.isEmpty, "EPUB should have linear reading order")
        print("  - Linear spine items: \(linearItems.count)")

        // Test TOC structure
        let flatTOC = document.flattenedTableOfContents
        print("  - Total TOC items (including nested): \(flatTOC.count)")

        // Verify TOC items have valid data
        for (index, tocItem) in document.tableOfContents.enumerated() {
            #expect(!tocItem.id.isEmpty, "TOC item \(index + 1) should have a valid ID")
            #expect(!tocItem.title.isEmpty, "TOC item \(index + 1) should have a valid title")
            #expect(!tocItem.href.isEmpty, "TOC item \(index + 1) should have a valid href")

            print("  ✓ TOC \(index + 1): '\(tocItem.title)' -> \(tocItem.href)")

            // Check nested items if any
            if !tocItem.children.isEmpty {
                print("    └─ \(tocItem.children.count) sub-items")
            }
        }

        // Test that we can load HTML content from spine items
        let baseURL = await parser.baseURL()
        var successfulLoads = 0

        for (index, spineItem) in document.spine.prefix(3).enumerated() {
            let url = document.url(for: spineItem.manifestItem)

            do {
                let html = try String(contentsOf: url, encoding: .utf8)
                #expect(!html.isEmpty, "Spine item \(index + 1) should have HTML content")
                successfulLoads += 1
                print("  ✓ Loaded HTML from spine item \(index + 1) (\(html.count) chars)")
            } catch {
                Issue.record("Failed to load HTML from spine item \(index + 1): \(error)")
            }
        }

        #expect(successfulLoads > 0, "Should be able to load at least one HTML file")

        _ = baseURL  // Suppress unused variable warning

        print("🎉 Successfully validated EPUB document structure")
    }

    @Test func testEPUBMetadata() async throws {
        guard let testEPUBPath = TestConfiguration.findTestEPUBFile() else {
            Issue.record("No test EPUB file found")
            return
        }

        let parser = EPUBParser(epubPath: testEPUBPath, identifier: "metadataTest")
        defer {
            parser.cleanup()
        }

        let document = try await parser.processEPUB()
        let metadata = document.metadata

        print("📖 EPUB Metadata:")

        // Test title
        if let title = metadata.title {
            print("  - Title: \(title)")
            #expect(!title.isEmpty, "Title should not be empty if present")
        } else {
            print("  - Title: (not specified)")
        }

        // Test creators/authors
        if !metadata.creators.isEmpty {
            print("  - Creators: \(metadata.creatorsString)")
            for creator in metadata.creators {
                #expect(!creator.isEmpty, "Creator name should not be empty")
            }
        } else {
            print("  - Creators: (none)")
        }

        // Test language
        if let language = metadata.language {
            print("  - Language: \(language)")
            #expect(!language.isEmpty, "Language should not be empty if present")
        }

        // Test identifier
        if let identifier = metadata.identifier {
            print("  - Identifier: \(identifier)")
        }

        // Test publisher
        if let publisher = metadata.publisher {
            print("  - Publisher: \(publisher)")
        }

        // Test other fields
        if !metadata.subjects.isEmpty {
            print("  - Subjects: \(metadata.subjectsString)")
        }

        print("✅ Metadata validation complete")
    }

    @Test func testEPUBSpineOrder() async throws {
        guard let testEPUBPath = TestConfiguration.findTestEPUBFile() else {
            Issue.record("No test EPUB file found")
            return
        }

        let parser = EPUBParser(epubPath: testEPUBPath, identifier: "spineTest")
        defer {
            parser.cleanup()
        }

        let document = try await parser.processEPUB()

        print("📖 Spine Reading Order:")

        // Verify spine items
        #expect(!document.spine.isEmpty, "Spine should not be empty")

        for (index, spineItem) in document.spine.enumerated() {
            #expect(!spineItem.id.isEmpty, "Spine item should have ID")
            #expect(!spineItem.idref.isEmpty, "Spine item should have idref")

            // Verify we can find the manifest item
            let manifestItem = document.manifestItem(withId: spineItem.idref)
            #expect(manifestItem != nil, "Spine item should reference valid manifest item")

            let linearFlag = spineItem.linear ? "linear" : "non-linear"
            print("  \(index + 1). [\(linearFlag)] \(spineItem.manifestItem.path)")
        }

        // Check linear vs non-linear
        let linearCount = document.linearSpineItems.count
        let totalCount = document.spine.count
        print("  - Linear items: \(linearCount)/\(totalCount)")

        print("✅ Spine order validation complete")
    }

    @Test func testEPUBTableOfContents() async throws {
        guard let testEPUBPath = TestConfiguration.findTestEPUBFile() else {
            Issue.record("No test EPUB file found")
            return
        }

        let parser = EPUBParser(epubPath: testEPUBPath, identifier: "tocTest")
        defer {
            parser.cleanup()
        }

        let document = try await parser.processEPUB()

        print("📑 Table of Contents:")

        #expect(!document.tableOfContents.isEmpty, "TOC should not be empty")

        // Test hierarchical structure
        func printTOC(_ items: [EPUBTOCItem], indent: String = "") {
            for item in items {
                print("\(indent)- '\(item.title)' -> \(item.href)")

                // Verify href structure
                #expect(!item.href.isEmpty, "TOC item should have href")

                // Check for fragment
                if let fragment = item.fragment {
                    print("\(indent)  (fragment: #\(fragment))")
                }

                // Recursively print children
                if !item.children.isEmpty {
                    printTOC(item.children, indent: indent + "  ")
                }
            }
        }

        printTOC(document.tableOfContents)

        // Test flattened TOC
        let flatTOC = document.flattenedTableOfContents
        print("  - Total items (flat): \(flatTOC.count)")
        #expect(flatTOC.count >= document.tableOfContents.count, "Flattened TOC should have at least as many items as top-level")

        print("✅ TOC validation complete")
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
        _ = try await parser.processEPUB()

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
