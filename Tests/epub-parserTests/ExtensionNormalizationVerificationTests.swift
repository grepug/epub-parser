import Foundation
import Testing

@testable import EPUBParser

/// Test to verify URLs include .html extensions for renamed files
@Suite("Extension Normalization Verification")
struct ExtensionNormalizationVerificationTests {

    @Test("Verify Harry Potter EPUB gets .html extensions added")
    func testHarryPotterHTMLExtensions() async throws {
        // Look for Harry Potter EPUB specifically since we know it has files without extensions
        let epubFiles = TestConfiguration.findAllTestEPUBFiles()

        guard let harryPotterEPUB = epubFiles.first(where: { $0.lastPathComponent.contains("Harry Potter") }) else {
            print("⚠️ Harry Potter EPUB not found - skipping test")
            return
        }

        let parser = EPUBParser(epubPath: harryPotterEPUB, identifier: "harry_potter_test", cleanup: true)
        defer { parser.cleanup() }

        let document = try await parser.processEPUB()

        print("\n📚 Testing Harry Potter EPUB: \(harryPotterEPUB.lastPathComponent)")
        print(String(repeating: "=", count: 80))

        // Check spine items for files with proper extensions
        var renamedFilesFound = 0

        for (index, spineItem) in document.spine.enumerated() {
            let manifestItem = spineItem.manifestItem
            let url = document.url(for: manifestItem)

            // Check if this looks like a renamed file (ends with .html but the original didn't)
            if manifestItem.path.hasSuffix(".html") && manifestItem.path.contains("hp07_watermark") {
                renamedFilesFound += 1

                if index < 5 {  // Print first few for debugging
                    print("  ✅ Renamed file: \(manifestItem.path)")
                    print("      URL: \(url.lastPathComponent)")
                    print("      Extension: \(url.pathExtension)")

                    // Verify the URL has the .html extension
                    #expect(
                        url.pathExtension == "html",
                        "Renamed file URL should have .html extension: \(url.lastPathComponent)")
                }
            }
        }

        print("\n📊 Found \(renamedFilesFound) files that were renamed to add .html extensions")

        // We expect to find some renamed files in Harry Potter EPUB
        #expect(renamedFilesFound > 0, "Should find renamed HTML files in Harry Potter EPUB")

        // Test that we can load content from one of the renamed files
        if let renamedSpineItem = document.spine.first(where: {
            $0.manifestItem.path.contains("hp07_watermark") && $0.manifestItem.path.hasSuffix(".html")
        }) {
            let url = document.url(for: renamedSpineItem.manifestItem)

            do {
                let content = try String(contentsOf: url, encoding: .utf8)
                print("  ✅ Successfully loaded content from renamed file: \(url.lastPathComponent) (\(content.count) chars)")
                #expect(!content.isEmpty, "Content should not be empty")
            } catch {
                Issue.record("Failed to load content from renamed file: \(error)")
            }
        }

        print("\n✅ HTML extension normalization working correctly!")
    }

    @Test("Verify manifest items have updated paths")
    func testManifestItemsUpdated() async throws {
        let epubFiles = TestConfiguration.findAllTestEPUBFiles()

        guard let harryPotterEPUB = epubFiles.first(where: { $0.lastPathComponent.contains("Harry Potter") }) else {
            print("⚠️ Harry Potter EPUB not found - skipping test")
            return
        }

        let parser = EPUBParser(epubPath: harryPotterEPUB, identifier: "manifest_update_test", cleanup: true)
        defer { parser.cleanup() }

        let document = try await parser.processEPUB()

        print("\n📋 Checking manifest items for updated paths:")
        print(String(repeating: "=", count: 60))

        // Look for manifest items that should have been renamed
        let renamedManifestItems = document.manifest.filter {
            $0.path.contains("hp07_watermark") && $0.path.hasSuffix(".html")
        }

        print("  Found \(renamedManifestItems.count) renamed manifest items")

        for (index, item) in renamedManifestItems.prefix(3).enumerated() {
            print("  \(index + 1). ID: \(item.id)")
            print("      Path: \(item.path)")
            print("      Media Type: \(item.mediaType)")

            // Verify the path has .html extension
            #expect(item.path.hasSuffix(".html"), "Manifest item path should end with .html")
        }

        #expect(renamedManifestItems.count > 0, "Should find renamed manifest items")

        print("\n✅ Manifest items updated correctly!")
    }
}
