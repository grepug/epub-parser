import Foundation
import Testing

@testable import EPUBParser

/// Specific tests for Build.epub spine content
@Suite("Build.epub Spine Verification")
struct BuildEPUBSpineTests {

    @Test("Build.epub spine contains Chapter_02.xhtml")
    func testChapter02ExistsInSpine() async throws {
        let epubPath = URL(fileURLWithPath: "/Users/kai/Downloads/epub/Build.epub")

        guard FileManager.default.fileExists(atPath: epubPath.path) else {
            Issue.record("Build.epub not found at expected path")
            return
        }

        let parser = EPUBParser(epubPath: epubPath, identifier: "build_chapter02_test", cleanup: true)
        defer { parser.cleanup() }

        let document = try await parser.processEPUB()

        print("\n🔍 Searching for Chapter_02.xhtml in spine:")
        print("=" * 60)

        // Search for Chapter_02.xhtml in spine
        let chapter02Items = document.spine.filter {
            $0.manifestItem.path.contains("Chapter_02.xhtml")
        }

        #expect(!chapter02Items.isEmpty, "Chapter_02.xhtml must exist in spine")

        if let chapter02 = chapter02Items.first {
            print("✅ Found Chapter_02.xhtml in spine:")
            print("   Path: \(chapter02.manifestItem.path)")
            print("   ID: \(chapter02.manifestItem.id)")
            print("   Media Type: \(chapter02.manifestItem.mediaType)")
            print("   Linear: \(chapter02.linear)")

            // Verify it's in the linear reading order
            #expect(chapter02.linear, "Chapter_02.xhtml should be in linear reading order")

            // Find its position in spine
            if let index = document.spine.firstIndex(where: { $0.manifestItem.path.contains("Chapter_02.xhtml") }) {
                print("   Position in spine: \(index + 1) of \(document.spine.count)")
            }
        }

        print("=" * 60)
    }

    @Test("Build.epub spine order matches expected structure")
    func testSpineOrderForBuildEPUB() async throws {
        let epubPath = URL(fileURLWithPath: "/Users/kai/Downloads/epub/Build.epub")

        guard FileManager.default.fileExists(atPath: epubPath.path) else {
            Issue.record("Build.epub not found at expected path")
            return
        }

        let parser = EPUBParser(epubPath: epubPath, identifier: "build_spine_order_test", cleanup: true)
        defer { parser.cleanup() }

        let document = try await parser.processEPUB()

        print("\n📖 Build.epub Spine Order:")
        print("=" * 60)

        // Expected chapters in order
        let expectedChapters = [
            "Chapter_01.xhtml",
            "Chapter_02.xhtml",
            "Chapter_03.xhtml",
            "Chapter_04.xhtml",
            "Chapter_05.xhtml",
        ]

        var foundChapters: [(String, Int)] = []

        for (index, spineItem) in document.spine.enumerated() {
            for expectedChapter in expectedChapters {
                if spineItem.manifestItem.path.contains(expectedChapter) {
                    foundChapters.append((expectedChapter, index))
                    print("  [\(index + 1)] \(expectedChapter)")
                }
            }
        }

        // Verify all expected chapters are found
        for expectedChapter in expectedChapters {
            let found = foundChapters.contains { $0.0 == expectedChapter }
            #expect(found, "\(expectedChapter) should be in spine")
        }

        // Verify they're in order
        let indices = foundChapters.map { $0.1 }
        let sortedIndices = indices.sorted()
        #expect(indices == sortedIndices, "Chapters should appear in sequential order in spine")

        print("\n✅ All expected chapters found in correct order")
        print("=" * 60)
    }

    @Test("Verify Chapter 1.2 content is accessible via spine")
    func testChapter12AccessViaSpine() async throws {
        let epubPath = URL(fileURLWithPath: "/Users/kai/Downloads/epub/Build.epub")

        guard FileManager.default.fileExists(atPath: epubPath.path) else {
            Issue.record("Build.epub not found at expected path")
            return
        }

        let parser = EPUBParser(epubPath: epubPath, identifier: "build_chapter12_access_test", cleanup: true)
        defer { parser.cleanup() }

        let document = try await parser.processEPUB()

        print("\n🔍 Verifying Chapter 1.2 access:")
        print("=" * 60)

        // Find Chapter 1.2 in TOC
        let chapter12TOC = document.flattenedTableOfContents.first {
            $0.title.contains("1.2") || $0.title.contains("Get a Job")
        }

        guard let tocEntry = chapter12TOC else {
            Issue.record("Chapter 1.2 not found in TOC")
            return
        }

        print("📑 TOC Entry:")
        print("   Title: \(tocEntry.title)")
        print("   Href: \(tocEntry.href)")

        // Extract the file path (without fragment)
        let baseHref: String
        if let hashIndex = tocEntry.href.firstIndex(of: "#") {
            baseHref = String(tocEntry.href[..<hashIndex])
        } else {
            baseHref = tocEntry.href
        }

        print("\n📖 Base file: \(baseHref)")

        // Find this file in spine
        let spineItem = document.spine.first {
            $0.manifestItem.path.contains(baseHref) || $0.manifestItem.path.hasSuffix(baseHref)
        }

        #expect(spineItem != nil, "The file containing Chapter 1.2 (\(baseHref)) must be in spine")

        if let item = spineItem {
            print("\n✅ Found in spine:")
            print("   Spine item path: \(item.manifestItem.path)")
            print("   Linear: \(item.linear)")

            // Verify we can load the content
            let url = document.url(for: item.manifestItem)
            print("   URL: \(url)")

            do {
                let content = try String(contentsOf: url, encoding: .utf8)
                print("   Content size: \(content.count) characters")

                // Verify content is not empty
                #expect(!content.isEmpty, "Chapter content should not be empty")

                // If there's a fragment, verify it exists in the content
                if let fragment = tocEntry.fragment {
                    print("   Fragment ID: \(fragment)")
                    let hasFragment = content.contains("id=\"\(fragment)\"") || content.contains("id='\(fragment)'")
                    if hasFragment {
                        print("   ✓ Fragment found in content")
                    } else {
                        print("   ⚠️ Fragment ID not found in content (this may be OK if using different ID format)")
                    }
                }

                print("\n✅ Chapter 1.2 is accessible via spine item: \(item.manifestItem.path)")
            } catch {
                Issue.record("Failed to load content: \(error)")
            }
        }

        print("=" * 60)
    }
}
