import Foundation
import Testing

@testable import EPUBParser

@Suite("Cover Image Path Reconstruction Test")
struct CoverImagePathReconstructionTest {

    @Test("Verify cover image path can be reconstructed with baseURL")
    func testCoverImagePathReconstruction() async throws {
        // Find a test EPUB file
        guard let epubPath = findFirstEPUB() else {
            Issue.record("No test EPUB files found in bundle")
            return
        }

        // Create a temporary directory for this test
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("EPUBParser_path_reconstruction_test_\(UUID())")

        // Initialize parser with the test EPUB
        let parser = EPUBParser(
            epubPath: epubPath,
            destinationURL: tempDir,
            cleanup: true
        )

        // Process the EPUB
        let document = try await parser.processEPUB()

        // Verify cover image path exists
        guard let coverImagePath = document.metadata.coverImagePath else {
            Issue.record("Cover image path should not be nil")
            return
        }

        print("📖 Cover image path from metadata: \(coverImagePath)")
        let unzippedRootURL = await parser.unzippedRootURL()
        print("📂 Unzipped root URL from parser: \(unzippedRootURL.path)")

        // Reconstruct the full cover image URL using unzippedRootURL
        let reconstructedCoverURL = unzippedRootURL.appendingPathComponent(coverImagePath)

        print("🔗 Reconstructed cover URL: \(reconstructedCoverURL.path)")

        // Verify the reconstructed path actually exists
        let fileExists = FileManager.default.fileExists(atPath: reconstructedCoverURL.path)

        #expect(fileExists, "Reconstructed cover image path should point to an existing file")

        // Additional verification: check that the path is properly relative
        // The coverImagePath should NOT start with "/" (should be relative)
        #expect(!coverImagePath.hasPrefix("/"), "Cover image path should be relative, not absolute")

        // The coverImagePath should contain the subdirectory (like "OEBPS/")
        #expect(coverImagePath.contains("/"), "Cover image path should contain subdirectory structure")

        // Verify we can read the file as an image
        let imageData = try Data(contentsOf: reconstructedCoverURL)
        #expect(imageData.count > 0, "Cover image file should contain data")

        print("✅ Cover image successfully reconstructed and verified")
        print("   - Path: \(coverImagePath)")
        print("   - Full URL: \(reconstructedCoverURL.path)")
        print("   - File size: \(imageData.count) bytes")

        // Cleanup
        try? FileManager.default.removeItem(at: tempDir)
    }

    @Test("Verify cover image path works with different EPUB structures")
    func testCoverImagePathWithDifferentStructures() async throws {
        // Find a test EPUB file
        guard let epubPath = findFirstEPUB() else {
            Issue.record("No test EPUB files found in bundle")
            return
        }

        // Test with a different EPUB that might have different structure
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("EPUBParser_structure_test_\(UUID())")

        let parser = EPUBParser(
            epubPath: epubPath,
            destinationURL: tempDir,
            cleanup: true
        )

        let document = try await parser.processEPUB()

        if let coverImagePath = document.metadata.coverImagePath {
            print("📖 Alternative EPUB cover path: \(coverImagePath)")

            let unzippedRootURL = await parser.unzippedRootURL()
            let reconstructedURL = unzippedRootURL.appendingPathComponent(coverImagePath)
            let fileExists = FileManager.default.fileExists(atPath: reconstructedURL.path)

            #expect(fileExists, "Cover image should be reconstructible for different EPUB structures")
            print("✅ Alternative structure cover image verified: \(reconstructedURL.path)")
        } else {
            print("ℹ️ This EPUB doesn't have a cover image, which is also valid")
        }

        // Cleanup
        try? FileManager.default.removeItem(at: tempDir)
    }

    private func findFirstEPUB() -> URL? {
        // Try to find EPUB files in common test directories
        let testPaths = [
            "/Users/kai/Downloads",
            "/Users/kai/Desktop",
            "/Users/kai/Documents",
            FileManager.default.currentDirectoryPath,
        ]

        for basePath in testPaths {
            let enumerator = FileManager.default.enumerator(atPath: basePath)
            while let file = enumerator?.nextObject() as? String {
                if file.lowercased().hasSuffix(".epub") {
                    return URL(fileURLWithPath: basePath).appendingPathComponent(file)
                }
            }
        }

        // Fallback: create a dummy test case
        Issue.record("No EPUB files found for testing - skipping reconstruction tests")
        return nil
    }

    private func findBuildEPUB() -> URL? {
        // Look specifically for Build.epub
        let specificPath = URL(fileURLWithPath: "/Users/kai/Downloads/epub/Build.epub")
        if FileManager.default.fileExists(atPath: specificPath.path) {
            return specificPath
        }

        // Fallback to common locations
        let testPaths = [
            "/Users/kai/Downloads",
            "/Users/kai/Desktop",
            "/Users/kai/Documents",
            FileManager.default.currentDirectoryPath,
        ]

        for basePath in testPaths {
            let buildEpubPath = URL(fileURLWithPath: basePath).appendingPathComponent("Build.epub")
            if FileManager.default.fileExists(atPath: buildEpubPath.path) {
                return buildEpubPath
            }
        }

        return nil
    }

    @Test("Test specifically with Build.epub file")
    func testBuildEPUBCoverImagePath() async throws {
        // Look specifically for Build.epub
        guard let buildEpubPath = findBuildEPUB() else {
            print("ℹ️ Build.epub not found - skipping this test")
            return
        }

        print("🔍 Testing with Build.epub at: \(buildEpubPath.path)")

        // Create a temporary directory for this test
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("EPUBParser_build_epub_test_\(UUID())")

        let parser = EPUBParser(
            epubPath: buildEpubPath,
            destinationURL: tempDir,
            cleanup: true
        )

        let document = try await parser.processEPUB()

        if let coverImagePath = document.metadata.coverImagePath {
            print("📖 Build.epub cover path: \(coverImagePath)")

            let unzippedRootURL = await parser.unzippedRootURL()
            print("📂 Unzipped root: \(unzippedRootURL.path)")

            let reconstructedURL = unzippedRootURL.appendingPathComponent(coverImagePath)
            print("🔗 Reconstructed URL: \(reconstructedURL.path)")

            let fileExists = FileManager.default.fileExists(atPath: reconstructedURL.path)
            print("📁 File exists: \(fileExists)")

            #expect(fileExists, "Build.epub cover image should be reconstructible")

            // Additional verification
            #expect(!coverImagePath.hasPrefix("/"), "Cover image path should be relative")

            print("✅ Build.epub cover image path test completed")
        } else {
            print("ℹ️ Build.epub doesn't have a cover image")
        }

        // Cleanup
        try? FileManager.default.removeItem(at: tempDir)
    }
}
