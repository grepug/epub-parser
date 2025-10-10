import Foundation
import Testing

@testable import EPUBParser

@Suite("Unzipped Path Initialization")
struct UnzippedPathTests {

    @Test("Initialize with valid unzipped EPUB directory")
    func testValidUnzippedPath() async throws {
        // First, create an unzipped EPUB directory by processing an EPUB
        guard let epubURL = TestConfiguration.findTestEPUBFile() else {
            print("⚠️ No test EPUB file found - skipping test")
            return
        }

        // Unzip an EPUB first
        let tempDir = try TestConfiguration.createTestDirectory()

        // Use the regular initializer to unzip
        let parser1 = EPUBParser(
            epubPath: epubURL,
            identifier: "test_unzip",
            cacheDirectory: tempDir
        )

        let document1 = try await parser1.processEPUB()

        // Get the actual unzip directory (not the OPF root)
        let unzipDir = tempDir.appendingPathComponent("epub_test_unzip")

        print("📂 Unzipped EPUB directory: \(unzipDir.path)")

        // Now test the new initializer with the unzipped path
        let parser2 = try EPUBParser(unzippedPath: unzipDir)

        let document2 = try await parser2.processEPUB()

        // Verify both parsers produce the same document structure
        #expect(document1.metadata.title == document2.metadata.title)
        #expect(document1.manifest.count == document2.manifest.count)
        #expect(document1.spine.count == document2.spine.count)
        #expect(document1.tableOfContents.count == document2.tableOfContents.count)

        print("✅ Successfully initialized parser with unzipped directory")
        print("   - Title: \(document2.metadata.title)")
        print("   - Manifest: \(document2.manifest.count) items")
        print("   - Spine: \(document2.spine.count) items")
        print("   - TOC: \(document2.tableOfContents.count) items")

        // Cleanup
        try? FileManager.default.removeItem(at: tempDir)
    }

    @Test("Invalid unzipped path throws error")
    func testInvalidUnzippedPath() async throws {
        let invalidPath = URL(fileURLWithPath: "/nonexistent/path/to/epub")

        do {
            let _ = try EPUBParser(unzippedPath: invalidPath)
            Issue.record("Expected error for non-existent path")
        } catch let error as EPUBParserError {
            switch error {
            case .invalidUnzippedPath(let reason):
                print("✅ Correctly threw error: \(reason)")
                #expect(reason.contains("does not exist"))
            default:
                Issue.record("Expected invalidUnzippedPath error, got: \(error)")
            }
        }
    }

    @Test("Path is not a directory throws error")
    func testPathIsNotDirectory() async throws {
        // Create a regular file instead of a directory
        let tempFile = FileManager.default.temporaryDirectory
            .appendingPathComponent("notadirectory.txt")
        try "test content".write(to: tempFile, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: tempFile) }

        do {
            let _ = try EPUBParser(unzippedPath: tempFile)
            Issue.record("Expected error for non-directory path")
        } catch let error as EPUBParserError {
            switch error {
            case .invalidUnzippedPath(let reason):
                print("✅ Correctly threw error: \(reason)")
                #expect(reason.contains("not a directory"))
            default:
                Issue.record("Expected invalidUnzippedPath error, got: \(error)")
            }
        }
    }

    @Test("Directory without container.xml throws error")
    func testMissingContainerXML() async throws {
        // Create an empty directory
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("invalid_epub_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        do {
            let _ = try EPUBParser(unzippedPath: tempDir)
            Issue.record("Expected error for missing container.xml")
        } catch let error as EPUBParserError {
            switch error {
            case .invalidUnzippedPath(let reason):
                print("✅ Correctly threw error: \(reason)")
                #expect(reason.contains("container.xml"))
            default:
                Issue.record("Expected invalidUnzippedPath error, got: \(error)")
            }
        }
    }

    @Test("Pre-unzipped directory is not deleted on cleanup")
    func testPreUnzippedNotDeleted() async throws {
        guard let epubURL = TestConfiguration.findTestEPUBFile() else {
            print("⚠️ No test EPUB file found - skipping test")
            return
        }

        // Unzip an EPUB first
        let tempDir = try TestConfiguration.createTestDirectory()
        let parser1 = EPUBParser(
            epubPath: epubURL,
            identifier: "test_cleanup",
            cacheDirectory: tempDir
        )

        let _ = try await parser1.processEPUB()
        let unzippedPath = tempDir.appendingPathComponent("epub_test_cleanup")

        // Verify directory exists
        #expect(FileManager.default.fileExists(atPath: unzippedPath.path))

        // Create parser with pre-unzipped path
        let parser2 = try EPUBParser(unzippedPath: unzippedPath)
        let _ = try await parser2.processEPUB()

        // Call cleanup on parser2 (should NOT delete the directory)
        await parser2.cleanup()

        // Directory should still exist
        #expect(FileManager.default.fileExists(atPath: unzippedPath.path))
        print("✅ Pre-unzipped directory correctly preserved after cleanup")

        // Now cleanup parser1 (which created the directory)
        await parser1.cleanup()

        // Now directory should be gone
        #expect(!FileManager.default.fileExists(atPath: unzippedPath.path))
        print("✅ Directory correctly deleted by original parser cleanup")

        // Cleanup temp dir
        try? FileManager.default.removeItem(at: tempDir)
    }
}
