import Foundation
import Testing

@testable import EPUBParser

/// Tests specifically for URL generation and validation
@Suite("EPUB URL Generation")
struct EPUBURLTests {

    @Test("Document baseURL is absolute")
    func testBaseURLIsAbsolute() async throws {
        guard let testEPUBPath = TestConfiguration.findTestEPUBFile() else {
            Issue.record("No test EPUB file found")
            return
        }

        let parser = EPUBParser(epubPath: testEPUBPath, identifier: "baseurl_test")
        defer { parser.cleanup() }

        let document = try await parser.processEPUB()

        print("📍 Base URL: \(document.baseURL)")
        print("   Scheme: \(document.baseURL.scheme ?? "none")")
        print("   Path: \(document.baseURL.path)")

        // Base URL must be absolute
        #expect(document.baseURL.scheme == "file", "Base URL should have 'file' scheme")
        #expect(document.baseURL.path.hasPrefix("/"), "Base URL path should be absolute")

        print("✅ Base URL is absolute")
    }

    @Test("Spine item URLs are absolute")
    func testSpineItemURLsAreAbsolute() async throws {
        guard let testEPUBPath = TestConfiguration.findTestEPUBFile() else {
            Issue.record("No test EPUB file found")
            return
        }

        print("testEpubPath: \(testEPUBPath)")

        let parser = EPUBParser(epubPath: testEPUBPath, identifier: "spine_url_test")
        defer { parser.cleanup() }

        let document = try await parser.processEPUB()

        print("📚 Testing Spine Item URLs:")

        var invalidURLs: [(Int, String, URL)] = []

        for (index, spineItem) in document.spine.enumerated() {
            let url = document.url(for: spineItem.manifestItem)

            print("  Item \(index + 1): \(spineItem.manifestItem.path)")
            print("    Generated URL: \(url)")
            print("    Scheme: \(url.scheme ?? "none")")
            print("    Path: \(url.path)")

            // Validate URL is absolute
            if url.scheme != "file" {
                invalidURLs.append((index, "Missing 'file' scheme", url))
            }

            if !url.path.hasPrefix("/") {
                invalidURLs.append((index, "Path is not absolute", url))
            }

            // Validate file exists
            if !FileManager.default.fileExists(atPath: url.path) {
                invalidURLs.append((index, "File does not exist", url))
            }
        }

        if !invalidURLs.isEmpty {
            print("\n❌ Invalid URLs found:")
            for (index, reason, url) in invalidURLs {
                print("  Item \(index + 1): \(reason) - \(url)")
            }
        }

        #expect(invalidURLs.isEmpty, "All spine item URLs should be valid absolute file URLs")

        print("✅ All spine item URLs are absolute and valid")
    }

    @Test("TOC item URLs are absolute")
    func testTOCItemURLsAreAbsolute() async throws {
        guard let testEPUBPath = TestConfiguration.findTestEPUBFile() else {
            Issue.record("No test EPUB file found")
            return
        }

        let parser = EPUBParser(epubPath: testEPUBPath, identifier: "toc_url_test")
        defer { parser.cleanup() }

        let document = try await parser.processEPUB()
        let flatTOC = document.flattenedTableOfContents

        guard !flatTOC.isEmpty else {
            print("⚠️ No TOC items to test")
            return
        }

        print("📑 Testing TOC Item URLs:")

        var invalidURLs: [(Int, String, URL)] = []

        for (index, tocItem) in flatTOC.enumerated() {
            let url = document.url(for: tocItem)

            print("  TOC \(index + 1): '\(tocItem.title)'")
            print("    Href: \(tocItem.href)")
            print("    Generated URL: \(url)")
            print("    Scheme: \(url.scheme ?? "none")")
            print("    Path: \(url.path)")

            // Validate URL is absolute
            if url.scheme != "file" {
                invalidURLs.append((index, "Missing 'file' scheme", url))
            }

            if !url.path.hasPrefix("/") {
                invalidURLs.append((index, "Path is not absolute", url))
            }

            // For TOC items, we need to check the base file (without fragment)
            var fileURL = url
            if fileURL.fragment != nil {
                fileURL = URL(fileURLWithPath: fileURL.path)
            }

            if !FileManager.default.fileExists(atPath: fileURL.path) {
                invalidURLs.append((index, "File does not exist", fileURL))
            }
        }

        if !invalidURLs.isEmpty {
            print("\n❌ Invalid URLs found:")
            for (index, reason, url) in invalidURLs {
                print("  TOC \(index + 1): \(reason) - \(url)")
            }
        }

        #expect(invalidURLs.isEmpty, "All TOC item URLs should be valid absolute file URLs")

        print("✅ All TOC item URLs are absolute and valid")
    }

    @Test("Manifest item URLs are absolute")
    func testManifestItemURLsAreAbsolute() async throws {
        guard let testEPUBPath = TestConfiguration.findTestEPUBFile() else {
            Issue.record("No test EPUB file found")
            return
        }

        let parser = EPUBParser(epubPath: testEPUBPath, identifier: "manifest_url_test")
        defer { parser.cleanup() }

        let document = try await parser.processEPUB()

        print("📦 Testing Manifest Item URLs:")

        var invalidURLs: [(String, String, URL)] = []
        var validCount = 0

        for item in document.manifest {
            let url = document.url(for: item)

            // Only print first 5 for brevity
            if validCount < 5 {
                print("  \(item.id): \(item.path)")
                print("    Generated URL: \(url)")
                print("    Scheme: \(url.scheme ?? "none")")
            }

            // Validate URL is absolute
            if url.scheme != "file" {
                invalidURLs.append((item.id, "Missing 'file' scheme", url))
            }

            if !url.path.hasPrefix("/") {
                invalidURLs.append((item.id, "Path is not absolute", url))
            }

            // Validate file exists
            if !FileManager.default.fileExists(atPath: url.path) {
                invalidURLs.append((item.id, "File does not exist", url))
            } else {
                validCount += 1
            }
        }

        print("  ... (\(document.manifest.count) total items)")
        print("  Valid: \(validCount)")

        if !invalidURLs.isEmpty {
            print("\n❌ Invalid URLs found:")
            for (id, reason, url) in invalidURLs.prefix(10) {
                print("  \(id): \(reason) - \(url)")
            }
            if invalidURLs.count > 10 {
                print("  ... and \(invalidURLs.count - 10) more")
            }
        }

        #expect(invalidURLs.isEmpty, "All manifest item URLs should be valid absolute file URLs")

        print("✅ All manifest item URLs are absolute and valid")
    }

    @Test("URLs can load actual content")
    func testURLsCanLoadContent() async throws {
        guard let testEPUBPath = TestConfiguration.findTestEPUBFile() else {
            Issue.record("No test EPUB file found")
            return
        }

        let parser = EPUBParser(epubPath: testEPUBPath, identifier: "content_load_test")
        defer { parser.cleanup() }

        let document = try await parser.processEPUB()

        print("📖 Testing Content Loading via URLs:")

        // Test loading from first spine item
        guard let firstSpine = document.spine.first else {
            Issue.record("No spine items found")
            return
        }

        let url = document.url(for: firstSpine.manifestItem)

        print("  URL: \(url)")

        // This is the critical test - it should work without errors
        do {
            let content = try String(contentsOf: url, encoding: .utf8)
            print("  ✓ Loaded \(content.count) characters")
            #expect(!content.isEmpty, "Content should not be empty")
        } catch {
            print("  ✗ Failed to load: \(error)")
            Issue.record("Failed to load content from URL: \(error)")
        }

        print("✅ Content loading works via generated URLs")
    }

    @Test("Multiple EPUBs have valid URLs")
    func testMultipleEPUBsHaveValidURLs() async throws {
        let epubFiles = TestConfiguration.findAllTestEPUBFiles()

        guard !epubFiles.isEmpty else {
            Issue.record("No test EPUB files found")
            return
        }

        print("📚 Testing URLs for \(epubFiles.count) EPUB files:")

        var totalInvalidURLs = 0

        for (index, epubPath) in epubFiles.enumerated() {
            let parser = EPUBParser(epubPath: epubPath, identifier: "multi_url_test_\(index)")
            defer { parser.cleanup() }

            do {
                let document = try await parser.processEPUB()

                // Quick validation of first spine item
                if let firstSpine = document.spine.first {
                    let url = document.url(for: firstSpine.manifestItem)

                    if url.scheme != "file" || !url.path.hasPrefix("/") {
                        totalInvalidURLs += 1
                        print("  ✗ \(epubPath.lastPathComponent): Invalid URL - \(url)")
                    } else {
                        print("  ✓ \(epubPath.lastPathComponent): Valid")
                    }
                }
            } catch {
                print("  ⚠️ \(epubPath.lastPathComponent): Failed to parse - \(error)")
            }
        }

        #expect(totalInvalidURLs == 0, "All EPUBs should generate valid absolute URLs")

        print("✅ All \(epubFiles.count) EPUBs generate valid URLs")
    }
}
