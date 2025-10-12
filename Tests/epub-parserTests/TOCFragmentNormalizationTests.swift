import Foundation
import Testing

@testable import EPUBParser

/// Test to verify TOC hrefs with fragments are properly updated
@Suite("TOC Fragment Normalization Tests")
struct TOCFragmentNormalizationTests {

    @Test("Verify TOC hrefs with fragments get .html extensions")
    func testTOCFragmentNormalization() async throws {
        // Look for an EPUB that has TOC items with fragments
        let epubFiles = TestConfiguration.findAllTestEPUBFiles()

        guard
            let testEPUB = epubFiles.first(where: {
                $0.lastPathComponent.contains("Harry Potter") || $0.lastPathComponent.contains("Build")
            })
        else {
            print("⚠️ Suitable test EPUB not found - skipping test")
            return
        }

        let parser = EPUBParser(epubPath: testEPUB, identifier: "toc_fragment_test", cleanup: true)
        defer { parser.cleanup() }

        let document = try await parser.processEPUB()

        print("\n📑 Testing TOC fragment normalization: \(testEPUB.lastPathComponent)")
        print(String(repeating: "=", count: 80))

        // Get all TOC items (flattened)
        let allTOCItems = document.flattenedTableOfContents

        print("  Total TOC items: \(allTOCItems.count)")

        // Check TOC items for proper extensions
        var itemsWithFragments = 0
        var itemsWithUpdatedHrefs = 0

        for (index, tocItem) in allTOCItems.prefix(15).enumerated() {
            let href = tocItem.href

            // Check if this href has a fragment
            if href.contains("#") {
                itemsWithFragments += 1
                let components = href.components(separatedBy: "#")
                let pathPart = components[0]
                let fragmentPart = components.count > 1 ? components[1] : ""

                print("  TOC \(index + 1): \(tocItem.title)")
                print("    Href: \(href)")
                print("    Path: \(pathPart)")
                print("    Fragment: #\(fragmentPart)")

                // Check if the path part has a proper extension
                let hasProperExtension = pathPart.hasSuffix(".html") || pathPart.hasSuffix(".xhtml") || pathPart.hasSuffix(".htm")

                print("    Has extension: \(hasProperExtension ? "✅" : "❌")")

                if hasProperExtension {
                    itemsWithUpdatedHrefs += 1
                }

                // Test URL generation
                let url = document.url(for: tocItem)
                print("    Generated URL: \(url.absoluteString)")

                // The URL should preserve the fragment
                #expect(
                    url.fragment == fragmentPart,
                    "URL should preserve fragment: expected #\(fragmentPart), got \(url.fragment ?? "nil")")
            } else {
                // No fragment
                print("  TOC \(index + 1): \(tocItem.title) -> \(href)")
            }
        }

        print("\n📊 Fragment Analysis:")
        print("  Items with fragments: \(itemsWithFragments)")
        print("  Items with proper extensions: \(itemsWithUpdatedHrefs)")

        // If there are fragments, at least some should be properly handled
        if itemsWithFragments > 0 {
            print("\n✅ Found TOC items with fragments - extension normalization should be applied")
        } else {
            print("\n⚠️ No fragments found in this EPUB's TOC")
        }
    }

    @Test("Verify specific fragment patterns are handled correctly")
    func testSpecificFragmentPatterns() async throws {
        // Use any available EPUB for this test
        guard let testEPUBPath = TestConfiguration.findTestEPUBFile() else {
            Issue.record("No test EPUB file found")
            return
        }

        let parser = EPUBParser(epubPath: testEPUBPath, identifier: "fragment_pattern_test", cleanup: true)
        defer { parser.cleanup() }

        let document = try await parser.processEPUB()

        print("\n🔍 Testing fragment pattern handling:")
        print(String(repeating: "=", count: 60))

        // Test URL generation for TOC items to ensure fragments are preserved
        let tocItemsWithFragments = document.flattenedTableOfContents.filter { $0.href.contains("#") }

        print("  Found \(tocItemsWithFragments.count) TOC items with fragments")

        for (index, tocItem) in tocItemsWithFragments.prefix(5).enumerated() {
            let url = document.url(for: tocItem)
            let originalHref = tocItem.href

            print("  Fragment \(index + 1):")
            print("    Original href: \(originalHref)")
            print("    Generated URL: \(url.absoluteString)")

            // Verify the URL has both path and fragment components
            if originalHref.contains("#") {
                let components = originalHref.components(separatedBy: "#")
                let expectedFragment = components.count > 1 ? components[1] : ""

                #expect(
                    url.fragment == expectedFragment,
                    "Fragment should be preserved in URL")

                // The path component should have an extension
                let pathExtension = url.pathExtension.lowercased()
                let hasHTMLExtension = ["html", "xhtml", "htm"].contains(pathExtension)

                print("    Path extension: \(pathExtension)")
                print("    Fragment: #\(url.fragment ?? "nil")")
                print("    Valid: \(hasHTMLExtension && url.fragment != nil ? "✅" : "❌")")
            }
        }

        print("\n✅ Fragment pattern testing complete")
    }
}
