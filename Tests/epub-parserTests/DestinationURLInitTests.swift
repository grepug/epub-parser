import Foundation
import Testing

@testable import EPUBParser

struct DestinationURLInitTests {

    // MARK: - Basic Initialization Tests

    @Test("Initialize EPUBParser with destinationURL")
    func testBasicInitialization() async throws {
        // Find a test EPUB file
        guard let epubURL = TestConfiguration.findTestEPUBFile() else {
            Issue.record("No test EPUB file found. Please add an EPUB file to the configured test directories.")
            return
        }

        // Create a destination URL for this test
        let destinationURL = TestConfiguration.testDestinationURL(for: "basic_init")

        // Initialize the parser
        let parser = EPUBParser(
            epubPath: epubURL,
            destinationURL: destinationURL,
            skipUnzipIfDirectoryExists: true,
            cleanup: false
        )

        // Verify the parser was created
        #expect(await parser.unzipDestination == destinationURL)

        // Cleanup
        try? FileManager.default.removeItem(at: destinationURL)
    }

    @Test("Process EPUB with destinationURL")
    func testProcessEPUB() async throws {
        // Find a test EPUB file
        guard let epubURL = TestConfiguration.findTestEPUBFile() else {
            Issue.record("No test EPUB file found. Please add an EPUB file to the configured test directories.")
            return
        }

        // Create a destination URL for this test
        let destinationURL = TestConfiguration.testDestinationURL(for: "process_epub")

        // Initialize and process
        let parser = EPUBParser(
            epubPath: epubURL,
            destinationURL: destinationURL,
            skipUnzipIfDirectoryExists: true,
            cleanup: false
        )

        // Process the EPUB
        let document = try await parser.processEPUB()

        // Verify document was created
        #expect(document.metadata.title?.isEmpty == false)
        #expect(document.spine.isEmpty == false)

        // Verify destination directory exists
        var isDirectory: ObjCBool = false
        let exists = FileManager.default.fileExists(atPath: destinationURL.path, isDirectory: &isDirectory)
        #expect(exists)
        #expect(isDirectory.boolValue)

        // Verify document is cached
        let cachedDocument = await parser.document()
        #expect(cachedDocument != nil)
        #expect(cachedDocument?.metadata.title == document.metadata.title)

        // Cleanup
        try? FileManager.default.removeItem(at: destinationURL)
    }

    @Test("Skip unzip if directory exists")
    func testSkipUnzipIfDirectoryExists() async throws {
        // Find a test EPUB file
        guard let epubURL = TestConfiguration.findTestEPUBFile() else {
            Issue.record("No test EPUB file found. Please add an EPUB file to the configured test directories.")
            return
        }

        // Create a destination URL for this test
        let destinationURL = TestConfiguration.testDestinationURL(for: "skip_unzip")

        // First pass - process normally
        let parser1 = EPUBParser(
            epubPath: epubURL,
            destinationURL: destinationURL,
            skipUnzipIfDirectoryExists: true,
            cleanup: false
        )

        let document1 = try await parser1.processEPUB()
        #expect(document1.metadata.title?.isEmpty == false)

        // Get modification time of a file in the destination
        let containerURL = destinationURL.appendingPathComponent("META-INF/container.xml")
        let attributes1 = try FileManager.default.attributesOfItem(atPath: containerURL.path)
        let modTime1 = attributes1[.modificationDate] as? Date

        // Wait a moment to ensure different timestamps
        try await Task.sleep(for: .milliseconds(100))

        // Second pass - should skip unzip
        let parser2 = EPUBParser(
            epubPath: epubURL,
            destinationURL: destinationURL,
            skipUnzipIfDirectoryExists: true,
            cleanup: false
        )

        let document2 = try await parser2.processEPUB()
        #expect(document2.metadata.title == document1.metadata.title)

        // Verify file wasn't overwritten (same modification time)
        let attributes2 = try FileManager.default.attributesOfItem(atPath: containerURL.path)
        let modTime2 = attributes2[.modificationDate] as? Date

        #expect(modTime1 == modTime2, "File should not have been overwritten")

        // Cleanup
        try? FileManager.default.removeItem(at: destinationURL)
    }

    @Test("Force unzip when directory exists but skipUnzipIfDirectoryExists is false")
    func testForceUnzipWhenDirectoryExists() async throws {
        // Find a test EPUB file
        guard let epubURL = TestConfiguration.findTestEPUBFile() else {
            Issue.record("No test EPUB file found. Please add an EPUB file to the configured test directories.")
            return
        }

        // Create a destination URL for this test
        let destinationURL = TestConfiguration.testDestinationURL(for: "force_unzip")

        // First pass - process normally
        let parser1 = EPUBParser(
            epubPath: epubURL,
            destinationURL: destinationURL,
            skipUnzipIfDirectoryExists: true,
            cleanup: false
        )

        let document1 = try await parser1.processEPUB()
        #expect(document1.metadata.title?.isEmpty == false)
        #expect(document1.manifest.count > 0)

        // Wait a moment before second parsing
        try await Task.sleep(for: .milliseconds(100))

        // Second pass - force unzip (skipUnzipIfDirectoryExists = false)
        let parser2 = EPUBParser(
            epubPath: epubURL,
            destinationURL: destinationURL,
            skipUnzipIfDirectoryExists: false,
            cleanup: false
        )

        let document2 = try await parser2.processEPUB()

        // Verify that both parsings were successful
        #expect(document2.metadata.title == document1.metadata.title)
        #expect(document2.manifest.count == document1.manifest.count)
        print("Force unzip test passed: both documents processed successfully")

        // Cleanup
        try? FileManager.default.removeItem(at: destinationURL)
    }

    // MARK: - HTML Processing Tests

    @Test("Verify HTML extension normalization")
    func testHTMLExtensionNormalization() async throws {
        // Find a test EPUB file
        guard let epubURL = TestConfiguration.findTestEPUBFile() else {
            Issue.record("No test EPUB file found. Please add an EPUB file to the configured test directories.")
            return
        }

        // Create a destination URL for this test
        let destinationURL = TestConfiguration.testDestinationURL(for: "html_extensions")

        // Initialize and process
        let parser = EPUBParser(
            epubPath: epubURL,
            destinationURL: destinationURL,
            skipUnzipIfDirectoryExists: true,
            cleanup: false
        )

        let document = try await parser.processEPUB()

        // Check that HTML files in the manifest have proper extensions
        for item in document.manifest {
            if item.mediaType == "application/xhtml+xml" {
                let url = URL(string: item.path)!
                let hasHTMLExtension = url.pathExtension.lowercased() == "html" || url.pathExtension.lowercased() == "xhtml"

                // If it's an HTML file, it should have the proper extension after processing
                if !hasHTMLExtension {
                    // Check if the actual file exists with .html extension
                    let baseURL = destinationURL.appendingPathComponent(item.path)
                    let htmlURL = baseURL.appendingPathExtension("html")
                    let fileExists = FileManager.default.fileExists(atPath: htmlURL.path)
                    #expect(fileExists, "HTML file should have .html extension: \(item.path)")
                }
            }
        }

        // Cleanup
        try? FileManager.default.removeItem(at: destinationURL)
    }

    @Test("Verify HTML content normalization with charset meta tags")
    func testHTMLContentNormalization() async throws {
        // Find a test EPUB file
        guard let epubURL = TestConfiguration.findTestEPUBFile() else {
            Issue.record("No test EPUB file found. Please add an EPUB file to the configured test directories.")
            return
        }

        // Create a destination URL for this test
        let destinationURL = TestConfiguration.testDestinationURL(for: "html_charset")

        // Initialize and process
        let parser = EPUBParser(
            epubPath: epubURL,
            destinationURL: destinationURL,
            skipUnzipIfDirectoryExists: true,
            cleanup: false
        )

        let document = try await parser.processEPUB()

        // Check HTML files for charset meta tags
        for item in document.manifest {
            if item.mediaType == "application/xhtml+xml" {
                let fileURL = destinationURL.appendingPathComponent(item.path)

                // Try with original path first, then with .html extension
                var actualFileURL = fileURL
                if !FileManager.default.fileExists(atPath: fileURL.path) {
                    actualFileURL = fileURL.appendingPathExtension("html")
                }

                if FileManager.default.fileExists(atPath: actualFileURL.path) {
                    let content = try String(contentsOf: actualFileURL, encoding: .utf8)
                    let hasCharsetMeta = content.contains("<meta charset=\"utf-8\"") || content.contains("<meta charset='utf-8'")

                    #expect(hasCharsetMeta, "HTML file should contain charset meta tag: \(item.path)")
                }
            }
        }

        // Cleanup
        try? FileManager.default.removeItem(at: destinationURL)
    }

    // MARK: - Document Access Tests

    @Test("Spine item ID lookup by URL")
    func testSpineItemIDLookup() async throws {
        // Find a test EPUB file
        guard let epubURL = TestConfiguration.findTestEPUBFile() else {
            Issue.record("No test EPUB file found. Please add an EPUB file to the configured test directories.")
            return
        }

        // Create a destination URL for this test
        let destinationURL = TestConfiguration.testDestinationURL(for: "spine_lookup")

        // Initialize and process
        let parser = EPUBParser(
            epubPath: epubURL,
            destinationURL: destinationURL,
            skipUnzipIfDirectoryExists: true,
            cleanup: false
        )

        let document = try await parser.processEPUB()

        // Test spine item lookup
        if let firstSpineItem = document.spine.first,
            let manifestItem = document.manifestItem(withId: firstSpineItem.id)
        {

            // Test string-based lookup
            let spineId1 = document.spineItemId(for: manifestItem.path)
            #expect(spineId1 == firstSpineItem.id)

            // Test URL-based lookup
            let itemURL = URL(string: manifestItem.path)!
            let spineId2 = document.spineItemId(for: itemURL)
            #expect(spineId2 == firstSpineItem.id)

            // Test with fragment
            let urlWithFragment = URL(string: manifestItem.path + "#section1")!
            let spineId3 = document.spineItemId(for: urlWithFragment)
            #expect(spineId3 == firstSpineItem.id)
        }

        // Cleanup
        try? FileManager.default.removeItem(at: destinationURL)
    }
}
