import Foundation
import Testing

@testable import EPUBParser

/// Tests for EPUB table of contents
@Suite("EPUB Table of Contents")
struct EPUBTableOfContentsTests {

    @Test("TOC structure")
    func testTOCStructure() async throws {
        guard let testEPUBPath = TestConfiguration.findTestEPUBFile() else {
            Issue.record("No test EPUB file found")
            return
        }

        let parser = EPUBParser(epubPath: testEPUBPath, identifier: "toc_test")
        defer { parser.cleanup() }

        let document = try await parser.processEPUB()

        print("📑 Table of Contents:")

        // Verify TOC is not empty
        #expect(!document.tableOfContents.isEmpty, "TOC should contain at least one item")

        print("  Top-level items: \(document.tableOfContents.count)")

        // Test each TOC item
        for (index, tocItem) in document.tableOfContents.enumerated() {
            #expect(!tocItem.id.isEmpty, "TOC item \(index + 1) should have an ID")
            #expect(!tocItem.title.isEmpty, "TOC item \(index + 1) should have a title")
            #expect(!tocItem.href.isEmpty, "TOC item \(index + 1) should have an href")

            print("  \(index + 1). '\(tocItem.title)' -> \(tocItem.href)")

            if !tocItem.children.isEmpty {
                print("      └─ \(tocItem.children.count) sub-items")
            }
        }

        print("✅ TOC structure validated")
    }

    @Test("TOC hierarchical structure")
    func testTOCHierarchy() async throws {
        guard let testEPUBPath = TestConfiguration.findTestEPUBFile() else {
            Issue.record("No test EPUB file found")
            return
        }

        let parser = EPUBParser(epubPath: testEPUBPath, identifier: "toc_hierarchy_test")
        defer { parser.cleanup() }

        let document = try await parser.processEPUB()

        print("📑 TOC Hierarchy:")

        // Recursive function to validate and print hierarchy
        func validateTOCLevel(_ items: [EPUBTOCItem], level: Int = 0) {
            let indent = String(repeating: "  ", count: level)

            for item in items {
                #expect(!item.id.isEmpty, "TOC item should have ID")
                #expect(!item.title.isEmpty, "TOC item should have title")
                #expect(!item.href.isEmpty, "TOC item should have href")

                print("\(indent)- \(item.title)")

                if !item.children.isEmpty {
                    print("\(indent)  (\(item.children.count) children)")
                    validateTOCLevel(item.children, level: level + 1)
                }
            }
        }

        validateTOCLevel(document.tableOfContents)

        print("✅ TOC hierarchy validated")
    }

    @Test("TOC flattening")
    func testTOCFlattening() async throws {
        guard let testEPUBPath = TestConfiguration.findTestEPUBFile() else {
            Issue.record("No test EPUB file found")
            return
        }

        let parser = EPUBParser(epubPath: testEPUBPath, identifier: "toc_flatten_test")
        defer { parser.cleanup() }

        let document = try await parser.processEPUB()

        let flatTOC = document.flattenedTableOfContents

        print("📑 TOC Flattening:")
        print("  Top-level items: \(document.tableOfContents.count)")
        print("  Flattened items: \(flatTOC.count)")

        // Flattened TOC should have at least as many items as top-level
        #expect(flatTOC.count >= document.tableOfContents.count, "Flattened TOC should include all items")

        // Verify all flattened items are valid
        for item in flatTOC {
            #expect(!item.id.isEmpty, "Flattened item should have ID")
            #expect(!item.title.isEmpty, "Flattened item should have title")
            #expect(!item.href.isEmpty, "Flattened item should have href")
        }

        print("✅ TOC flattening validated")
    }

    @Test("TOC href and fragment parsing")
    func testTOCHrefParsing() async throws {
        guard let testEPUBPath = TestConfiguration.findTestEPUBFile() else {
            Issue.record("No test EPUB file found")
            return
        }

        let parser = EPUBParser(epubPath: testEPUBPath, identifier: "toc_href_test")
        defer { parser.cleanup() }

        let document = try await parser.processEPUB()
        let flatTOC = document.flattenedTableOfContents

        print("📑 TOC Href Analysis:")

        var withFragments = 0
        var withoutFragments = 0

        for item in flatTOC {
            #expect(!item.href.isEmpty, "TOC item should have href")
            #expect(!item.filePath.isEmpty, "TOC item should have file path")

            if let fragment = item.fragment {
                withFragments += 1
                #expect(!fragment.isEmpty, "Fragment should not be empty if present")
                #expect(item.href.contains("#\(fragment)"), "Href should contain fragment")
                print("  '\(item.title)' -> \(item.filePath)#\(fragment)")
            } else {
                withoutFragments += 1
                #expect(!item.href.contains("#"), "Href without fragment should not contain #")
            }
        }

        print("  Items with fragments: \(withFragments)")
        print("  Items without fragments: \(withoutFragments)")

        print("✅ TOC href parsing validated")
    }

    @Test("TOC item URL generation")
    func testTOCURLGeneration() async throws {
        guard let testEPUBPath = TestConfiguration.findTestEPUBFile() else {
            Issue.record("No test EPUB file found")
            return
        }

        let parser = EPUBParser(epubPath: testEPUBPath, identifier: "toc_url_test")
        defer { parser.cleanup() }

        let document = try await parser.processEPUB()

        print("📑 TOC URL Generation:")

        // Test URL generation for TOC items
        for (index, tocItem) in document.tableOfContents.prefix(5).enumerated() {
            let url = document.url(for: tocItem)

            #expect(url.path.contains(tocItem.filePath), "URL should contain file path")

            print("  \(index + 1). '\(tocItem.title)'")
            print("      Href: \(tocItem.href)")
            print("      URL: \(url.path)")
        }

        print("✅ TOC URL generation validated")
    }
}
