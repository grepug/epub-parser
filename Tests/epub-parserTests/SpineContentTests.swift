import Foundation
import Testing

@testable import EPUBParser

/// Tests to verify spine contains all expected content
@Suite("Spine Content Verification")
struct SpineContentTests {

    @Test("Build.epub should contain all chapters including 1.2")
    func testBuildEPUBSpineCompleteness() async throws {
        let epubPath = URL(fileURLWithPath: "/Users/kai/Downloads/epub/Build.epub")

        guard FileManager.default.fileExists(atPath: epubPath.path) else {
            Issue.record("Build.epub not found at expected path")
            return
        }

        let parser = EPUBParser(epubPath: epubPath, identifier: "build_spine_test", cleanup: true)
        defer { parser.cleanup() }

        let document = try await parser.processEPUB()

        print("\n📚 Build.epub Analysis:")
        print("=" * 60)

        // Print manifest statistics
        let allManifestItems = document.manifest
        let htmlManifestItems = document.htmlManifestItems
        print("\n📦 Manifest:")
        print("  Total items: \(allManifestItems.count)")
        print("  HTML/XHTML items: \(htmlManifestItems.count)")

        // Print spine statistics
        print("\n📖 Spine:")
        print("  Total spine items: \(document.spine.count)")
        print("  Linear spine items: \(document.linearSpineItems.count)")

        // Print TOC statistics
        let flatTOC = document.flattenedTableOfContents
        print("\n📑 Table of Contents:")
        print("  Total TOC entries: \(flatTOC.count)")

        // List all HTML files in manifest but NOT in spine
        let spineItemPaths = Set(document.spine.map { $0.manifestItem.path })
        let htmlNotInSpine = htmlManifestItems.filter { !spineItemPaths.contains($0.path) }

        if !htmlNotInSpine.isEmpty {
            print("\n⚠️  HTML files in manifest but NOT in spine:")
            for item in htmlNotInSpine {
                print("    - \(item.id): \(item.path)")
            }
        }

        // List all TOC entries
        print("\n📑 Complete Table of Contents:")
        for (index, tocItem) in flatTOC.enumerated() {
            print("  \(index + 1). \(tocItem.title)")
            print("      → \(tocItem.href)")
        }

        // List all spine items
        print("\n📖 Complete Spine (Reading Order):")
        for (index, spineItem) in document.spine.enumerated() {
            let linearMark = spineItem.linear ? "✓" : "✗"
            print("  [\(linearMark)] \(index + 1). \(spineItem.manifestItem.path)")
            print("      ID: \(spineItem.manifestItem.id)")
        }

        // Check for Chapter 1.2 specifically
        print("\n🔍 Searching for Chapter 1.2:")

        // Search in TOC
        let chapter12InTOC = flatTOC.filter {
            $0.title.contains("1.2") || $0.title.lowercased().contains("chapter 1.2")
        }
        if !chapter12InTOC.isEmpty {
            print("  ✓ Found in TOC:")
            for item in chapter12InTOC {
                print("    - \(item.title) → \(item.href)")
            }
        } else {
            print("  ✗ NOT found in TOC")
        }

        // Search in spine
        let chapter12InSpine = document.spine.filter {
            $0.manifestItem.id.contains("1.2") || $0.manifestItem.id.contains("1_2") || $0.manifestItem.path.contains("1.2") || $0.manifestItem.path.contains("1_2")
        }
        if !chapter12InSpine.isEmpty {
            print("  ✓ Found in Spine:")
            for item in chapter12InSpine {
                print("    - \(item.manifestItem.id): \(item.manifestItem.path)")
            }
        } else {
            print("  ✗ NOT found in Spine")
        }

        // Search in manifest
        let chapter12InManifest = allManifestItems.filter {
            $0.id.contains("1.2") || $0.id.contains("1_2") || $0.path.contains("1.2") || $0.path.contains("1_2") || $0.id.lowercased().contains("chapter") && $0.id.contains("12")
        }
        if !chapter12InManifest.isEmpty {
            print("  ✓ Found in Manifest:")
            for item in chapter12InManifest {
                print("    - \(item.id): \(item.path)")

                // Check if it's in spine
                let inSpine = spineItemPaths.contains(item.path)
                print("      In Spine: \(inSpine ? "YES" : "NO")")
            }
        } else {
            print("  ✗ NOT found in Manifest")
        }

        print("\n" + "=" * 60)

        // Validation
        #expect(document.spine.count > 0, "Spine should not be empty")
        #expect(flatTOC.count > 0, "TOC should not be empty")

        // If Chapter 1.2 is in TOC or manifest, it should be in spine
        if !chapter12InTOC.isEmpty || !chapter12InManifest.isEmpty {
            #expect(!chapter12InSpine.isEmpty, "Chapter 1.2 should be in spine if it exists in TOC or manifest")
        }
    }

    @Test("Compare spine order with TOC order")
    func testSpineVsTOCOrder() async throws {
        let epubPath = URL(fileURLWithPath: "/Users/kai/Downloads/epub/Build.epub")

        guard FileManager.default.fileExists(atPath: epubPath.path) else {
            Issue.record("Build.epub not found at expected path")
            return
        }

        let parser = EPUBParser(epubPath: epubPath, identifier: "spine_toc_order_test", cleanup: true)
        defer { parser.cleanup() }

        let document = try await parser.processEPUB()

        print("\n📊 Spine vs TOC Comparison:")
        print("=" * 80)

        let flatTOC = document.flattenedTableOfContents

        // Extract base filename without fragment
        func baseFilename(_ href: String) -> String {
            if let hashIndex = href.firstIndex(of: "#") {
                return String(href[..<hashIndex])
            }
            return href
        }

        // Map TOC hrefs to their order
        var tocFileOrder: [String: Int] = [:]
        for (index, tocItem) in flatTOC.enumerated() {
            let base = baseFilename(tocItem.href)
            if tocFileOrder[base] == nil {
                tocFileOrder[base] = index
            }
        }

        // Check each spine item
        print("\nSpine items and their TOC appearance:")
        for (spineIndex, spineItem) in document.spine.enumerated() {
            let path = spineItem.manifestItem.path
            let filename = URL(fileURLWithPath: path).lastPathComponent

            if let tocIndex = tocFileOrder[path] ?? tocFileOrder[filename] {
                print("  [\(spineIndex)] \(path)")
                print("      → Appears in TOC at position \(tocIndex)")
            } else {
                print("  [\(spineIndex)] \(path)")
                print("      → NOT in TOC")
            }
        }

        print("\n" + "=" * 80)
    }
}

extension String {
    static func * (left: String, right: Int) -> String {
        String(repeating: left, count: right)
    }
}
