import Foundation
import Testing

@testable import EPUBParser

@Suite("Cover Image URL")
struct CoverImageTests {

    @Test("Cover image URL is valid and points to an actual image file")
    func testCoverImageURLIsValid() async throws {
        guard let epubURL = TestConfiguration.findTestEPUBFile() else {
            print("⚠️ No test EPUB file found - skipping test")
            return
        }

        let tempDir = try TestConfiguration.createTestDirectory()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let parser = EPUBParser(
            epubPath: epubURL,
            identifier: "cover_test",
            cacheDirectory: tempDir
        )

        let document = try await parser.processEPUB()

        if let coverURL = document.metadata.coverImageURL {
            print("📸 Cover image URL: \(coverURL.path)")

            // Test 1: URL should not be a directory
            #expect(!coverURL.hasDirectoryPath, "Cover URL should not be a directory path")

            // Test 2: URL should have a file extension
            let pathExtension = coverURL.pathExtension.lowercased()
            #expect(!pathExtension.isEmpty, "Cover image should have a file extension")

            // Test 3: Extension should be a valid image format
            let validExtensions = ["jpg", "jpeg", "png", "gif", "webp", "svg", "bmp"]
            #expect(
                validExtensions.contains(pathExtension),
                "Cover image extension '\(pathExtension)' should be a valid image format")

            // Test 4: File should exist
            let fileExists = FileManager.default.fileExists(atPath: coverURL.path)
            #expect(fileExists, "Cover image file should exist at path: \(coverURL.path)")

            // Test 5: URL should not end with a slash
            #expect(!coverURL.path.hasSuffix("/"), "Cover URL should not end with a slash")

            // Test 6: URL path should contain the filename
            let filename = coverURL.lastPathComponent
            #expect(!filename.isEmpty, "Cover URL should have a filename")
            #expect(filename != "OEBPS", "Cover URL should not just be the base directory")

            print("✅ Cover image validation passed:")
            print("   - Path: \(coverURL.path)")
            print("   - Filename: \(filename)")
            print("   - Extension: \(pathExtension)")
            print("   - File exists: \(fileExists)")
        } else {
            print("ℹ️ No cover image found in this EPUB (coverImageURL is nil)")
            // This is okay - not all EPUBs have cover images
        }
    }

    @Test("Cover image URL should be absolute, not relative")
    func testCoverImageURLIsAbsolute() async throws {
        guard let epubURL = TestConfiguration.findTestEPUBFile() else {
            print("⚠️ No test EPUB file found - skipping test")
            return
        }

        let tempDir = try TestConfiguration.createTestDirectory()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let parser = EPUBParser(
            epubPath: epubURL,
            identifier: "cover_absolute_test",
            cacheDirectory: tempDir
        )

        let document = try await parser.processEPUB()

        if let coverURL = document.metadata.coverImageURL {
            // Test that URL is absolute
            #expect(coverURL.isFileURL, "Cover URL should be a file URL")
            #expect(coverURL.path.hasPrefix("/"), "Cover URL path should be absolute (start with /)")

            print("✅ Cover image URL is absolute: \(coverURL.path)")
        }
    }

    @Test("Multiple EPUBs with cover images")
    func testMultipleEPUBsCoverImages() async throws {
        let epubFiles = TestConfiguration.findAllTestEPUBFiles()

        guard !epubFiles.isEmpty else {
            print("⚠️ No test EPUB files found - skipping test")
            return
        }

        var successCount = 0
        var withCoverCount = 0
        var invalidCoverCount = 0

        for epubURL in epubFiles.prefix(10) {  // Test first 10 EPUBs
            do {
                let tempDir = try TestConfiguration.createTestDirectory()
                defer { try? FileManager.default.removeItem(at: tempDir) }

                let parser = EPUBParser(
                    epubPath: epubURL,
                    identifier: UUID().uuidString,
                    cacheDirectory: tempDir
                )

                let document = try await parser.processEPUB()
                successCount += 1

                if let coverURL = document.metadata.coverImageURL {
                    withCoverCount += 1

                    // Validate the cover URL
                    if coverURL.hasDirectoryPath || coverURL.pathExtension.isEmpty {
                        invalidCoverCount += 1
                        print("❌ Invalid cover URL in \(epubURL.lastPathComponent): \(coverURL.path)")
                    } else {
                        print("✅ Valid cover in \(epubURL.lastPathComponent): \(coverURL.lastPathComponent)")
                    }
                }

                await parser.cleanup()
            } catch {
                print("⚠️ Failed to process \(epubURL.lastPathComponent): \(error)")
            }
        }

        print("\n📊 Cover Image Test Summary:")
        print("   - EPUBs processed: \(successCount)")
        print("   - EPUBs with cover images: \(withCoverCount)")
        print("   - Invalid cover URLs: \(invalidCoverCount)")

        // Validate that we found no invalid covers
        #expect(invalidCoverCount == 0, "All cover URLs should be valid (found \(invalidCoverCount) invalid)")
    }

    @Test("Cover image URL matches manifest item")
    func testCoverImageMatchesManifest() async throws {
        guard let epubURL = TestConfiguration.findTestEPUBFile() else {
            print("⚠️ No test EPUB file found - skipping test")
            return
        }

        let tempDir = try TestConfiguration.createTestDirectory()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let parser = EPUBParser(
            epubPath: epubURL,
            identifier: "cover_manifest_test",
            cacheDirectory: tempDir
        )

        let document = try await parser.processEPUB()

        if let coverURL = document.metadata.coverImageURL {
            // Find all image items in manifest
            let imageItems = document.manifest.filter { $0.mediaType.hasPrefix("image/") }

            #expect(!imageItems.isEmpty, "EPUB should have at least one image in manifest")

            // Check that cover URL corresponds to one of the manifest items
            let coverFilename = coverURL.lastPathComponent
            let matchingItems = imageItems.filter { item in
                item.path.contains(coverFilename) || coverURL.path.contains(item.path)
            }

            #expect(
                !matchingItems.isEmpty,
                "Cover image URL should match a manifest item. Cover: \(coverFilename), Images: \(imageItems.map { $0.path })")

            print("✅ Cover image matches manifest item:")
            if let match = matchingItems.first {
                print("   - Manifest ID: \(match.id)")
                print("   - Manifest path: \(match.path)")
                print("   - Media type: \(match.mediaType)")
            }
        }
    }

    @Test("Cover image should not be an XHTML or HTML file")
    func testCoverImageIsNotHTML() async throws {
        guard let epubURL = TestConfiguration.findTestEPUBFile() else {
            print("⚠️ No test EPUB file found - skipping test")
            return
        }

        let tempDir = try TestConfiguration.createTestDirectory()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let parser = EPUBParser(
            epubPath: epubURL,
            identifier: "cover_not_html_test",
            cacheDirectory: tempDir
        )

        let document = try await parser.processEPUB()

        if let coverURL = document.metadata.coverImageURL {
            let pathExtension = coverURL.pathExtension.lowercased()
            let htmlExtensions = ["html", "xhtml", "htm", "xml"]

            #expect(
                !htmlExtensions.contains(pathExtension),
                "Cover image should not be an HTML/XHTML file, got: \(pathExtension)")

            print("✅ Cover is not HTML (extension: \(pathExtension))")
        }
    }
}
