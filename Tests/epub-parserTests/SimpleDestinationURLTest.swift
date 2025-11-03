import Foundation
import Testing

@testable import EPUBParser

struct SimpleDestinationURLTest {

    @Test("Test EPUB Processing with Better Error Handling")
    func testEPUBProcessingWithErrorHandling() async throws {
        // Find a test EPUB file
        guard let epubURL = TestConfiguration.findTestEPUBFile() else {
            Issue.record("No test EPUB file found. Please add an EPUB file to the configured test directories.")
            return
        }

        print("Testing with EPUB file: \(epubURL.path)")

        // Verify the EPUB file exists and is readable
        #expect(FileManager.default.fileExists(atPath: epubURL.path))

        // Create a destination URL for this test
        let destinationURL = TestConfiguration.testDestinationURL(for: "simple_test")
        print("Destination URL: \(destinationURL.path)")

        // Initialize the parser
        let parser = EPUBParser(
            epubPath: epubURL,
            destinationURL: destinationURL,
            skipUnzipIfDirectoryExists: true,
            cleanup: false
        )

        // Verify the parser was created
        #expect(await parser.unzipDestination == destinationURL)

        do {
            // Process the EPUB with error handling
            let document = try await parser.processEPUB()
            print("Successfully processed EPUB!")
            print("Title: \(document.metadata.title ?? "No title")")
            print("Manifest items count: \(document.manifest.count)")
            print("Spine items count: \(document.spineItems.count)")

            // Basic validation
            #expect(document.manifest.count > 0)
            #expect(document.spineItems.count > 0)

        } catch {
            print("Error processing EPUB: \(error)")

            // Debug the unzipped directory contents
            if FileManager.default.fileExists(atPath: destinationURL.path) {
                print("\nDebugging unzipped directory contents:")
                do {
                    let contents = try FileManager.default.contentsOfDirectory(atPath: destinationURL.path)
                    print("Root directory contents: \(contents)")

                    // Check for META-INF
                    let metaInfURL = destinationURL.appendingPathComponent("META-INF")
                    if FileManager.default.fileExists(atPath: metaInfURL.path) {
                        let metaContents = try FileManager.default.contentsOfDirectory(atPath: metaInfURL.path)
                        print("META-INF contents: \(metaContents)")

                        // Check container.xml contents
                        let containerURL = metaInfURL.appendingPathComponent("container.xml")
                        if FileManager.default.fileExists(atPath: containerURL.path) {
                            let containerContent = try String(contentsOf: containerURL)
                            print("container.xml content:\n\(containerContent)")
                        }
                    }

                    // Check for OEBPS directory and content.opf
                    let oebpsURL = destinationURL.appendingPathComponent("OEBPS")
                    if FileManager.default.fileExists(atPath: oebpsURL.path) {
                        let oebpsContents = try FileManager.default.contentsOfDirectory(atPath: oebpsURL.path)
                        print("OEBPS contents: \(oebpsContents)")

                        let contentOpfURL = oebpsURL.appendingPathComponent("content.opf")
                        print("content.opf exists: \(FileManager.default.fileExists(atPath: contentOpfURL.path))")
                        print("content.opf path: \(contentOpfURL.path)")
                    } else {
                        print("OEBPS directory does not exist at: \(oebpsURL.path)")
                    }
                } catch {
                    print("Failed to debug directory: \(error)")
                }
            }

            Issue.record("Failed to process EPUB: \(error)")
        }

        // Cleanup
        try? FileManager.default.removeItem(at: destinationURL)
    }

    @Test("Test Multiple EPUB Files")
    func testMultipleEPUBFiles() async throws {
        let epubFiles = TestConfiguration.findAllTestEPUBFiles()

        guard !epubFiles.isEmpty else {
            Issue.record("No EPUB files found in test directories")
            return
        }

        print("Found \(epubFiles.count) EPUB files for testing")

        // Test the first few files to avoid long test runs
        let testFiles = Array(epubFiles.prefix(3))

        for (index, epubURL) in testFiles.enumerated() {
            print("\n--- Testing EPUB \(index + 1): \(epubURL.lastPathComponent) ---")

            let destinationURL = TestConfiguration.testDestinationURL(for: "multi_test_\(index)")

            let parser = EPUBParser(
                epubPath: epubURL,
                destinationURL: destinationURL,
                skipUnzipIfDirectoryExists: true,
                cleanup: false
            )

            do {
                let document = try await parser.processEPUB()
                print("✅ Successfully processed: \(document.metadata.title ?? "No title")")

                // Basic validation
                #expect(document.manifest.count > 0, "Manifest should not be empty")
                #expect(document.spineItems.count > 0, "Spine should not be empty")

            } catch {
                print("❌ Failed to process \(epubURL.lastPathComponent): \(error)")
                // Don't fail the test for individual files, just record issues
                Issue.record("Failed to process \(epubURL.lastPathComponent): \(error)")
            }

            // Cleanup
            try? FileManager.default.removeItem(at: destinationURL)
        }
    }
}
