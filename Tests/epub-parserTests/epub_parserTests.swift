import Foundation
import Testing

@testable import EPUBParser

struct EPUBParserTests {

    // MARK: - Test Configuration

    /// Attempts to find a suitable EPUB file for testing
    private static func findTestEPUBFile() -> URL? {
        let allFiles = findAllTestEPUBFiles()
        return allFiles.first
    }

    /// Finds all available EPUB files for comprehensive testing
    private static func findAllTestEPUBFiles() -> [URL] {
        let fileManager = FileManager.default
        var foundFiles: [URL] = []

        // Primary test file locations in order of preference (only .epub files)
        let testLocations = [
            "/Users/kai/Downloads/Atomic Habits (James Clear) (Z-Library).epub",
            "/Users/kai/Downloads/Elon Musk (Walter Isaacson) (Z-Library).epub",
        ]

        // Look for any .epub files in common directories
        let searchDirectories = [
            "/Users/kai/Downloads",
            "/Users/kai/Documents",
            "~/Downloads",
            "~/Documents",
        ]

        // First, try the specific test files
        for location in testLocations {
            let url = URL(fileURLWithPath: location)
            if fileManager.fileExists(atPath: url.path) {
                foundFiles.append(url)
            }
        }

        // Then search for any EPUB files in directories
        for directory in searchDirectories {
            let expandedPath = NSString(string: directory).expandingTildeInPath
            let dirURL = URL(fileURLWithPath: expandedPath)

            guard let enumerator = fileManager.enumerator(at: dirURL, includingPropertiesForKeys: nil) else {
                continue
            }

            for case let fileURL as URL in enumerator {
                let ext = fileURL.pathExtension.lowercased()
                let fileName = fileURL.lastPathComponent.lowercased()

                // Only include actual EPUB files, exclude ZIP files and other archives
                if ext == "epub" && !fileName.contains("module") && !fileName.contains("skeleton") && !fileName.contains("eureka") && !fileName.hasPrefix("dongurami")
                    && !fileName.contains("visionarytech") && !foundFiles.contains(fileURL)
                {
                    foundFiles.append(fileURL)
                }
            }
        }

        // Limit to first 8 files to avoid excessive test times
        return Array(foundFiles.prefix(8))
    }

    /// Creates a temporary directory for test operations
    private static func createTestDirectory() throws -> URL {
        let tempDir = FileManager.default.temporaryDirectory
        let testDir = tempDir.appendingPathComponent("EPUBParserTests_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: testDir, withIntermediateDirectories: true)
        return testDir
    }

    /// Quick validation to check if a file is likely a valid EPUB
    private static func isValidEPUBFile(_ url: URL) -> Bool {
        guard url.pathExtension.lowercased() == "epub" else { return false }

        // Check if we can at least open it as a ZIP archive
        do {
            let data = try Data(contentsOf: url)
            // Basic ZIP file signature check
            if data.count < 4 { return false }
            let signature = data.prefix(4)
            let zipSignature = Data([0x50, 0x4B, 0x03, 0x04])  // "PK\x03\x04"
            return signature == zipSignature
        } catch {
            return false
        }
    }

    // MARK: - Tests

    @Test func testEPUBParserInitialization() async {
        guard let testEPUBPath = Self.findTestEPUBFile() else {
            Issue.record("No test EPUB file found. Please ensure there's an EPUB file in Downloads directory.")
            return
        }

        let parser = EPUBParser(epubPath: testEPUBPath, identifier: UUID().uuidString)

        // Verify parser was created successfully
        let chapters = await parser.chapters()
        #expect(chapters.isEmpty, "Parser should start with empty chapters before processing")
    }

    @Test func testEPUBProcessing() async throws {
        guard let originalEPUBPath = Self.findTestEPUBFile() else {
            Issue.record("No test EPUB file found. Please ensure there's an EPUB file in Downloads directory.")
            return
        }

        let testDir = try Self.createTestDirectory()
        defer {
            try? FileManager.default.removeItem(at: testDir)
        }

        let testEPUBPath = testDir.appendingPathComponent("test.epub")

        // Copy the test file to a temporary location
        try FileManager.default.copyItem(at: originalEPUBPath, to: testEPUBPath)

        let parser = EPUBParser(epubPath: testEPUBPath, identifier: "testProcessing")
        defer {
            parser.cleanup()
        }

        // Process the EPUB
        do {
            try await parser.processEPUB()
        } catch {
            Issue.record("Failed to process EPUB: \(error.localizedDescription)")
            return
        }

        // Verify chapters were extracted
        let chapters = await parser.chapters()
        #expect(!chapters.isEmpty, "EPUB should contain at least one chapter")

        print("📚 Successfully processed EPUB with \(chapters.count) chapters")

        // Test each chapter
        for (index, chapter) in chapters.enumerated() {
            #expect(!chapter.id.isEmpty, "Chapter \(index + 1) should have a valid ID")
            #expect(!chapter.title.isEmpty, "Chapter \(index + 1) should have a valid title")
            #expect(!chapter.path.isEmpty, "Chapter \(index + 1) should have a valid path")

            // Verify chapter has content
            do {
                let chapterContent = try await parser.chapter(id: chapter.id)
                #expect(!chapterContent.manifestItems.isEmpty, "Chapter '\(chapter.title)' should have manifest items")

                let baseURL = await parser.baseURL()
                let html = try chapterContent.combinedHTML(baseURL: baseURL)
                #expect(!html.isEmpty, "Chapter '\(chapter.title)' should generate non-empty HTML")

                print("  ✓ Chapter \(index + 1): '\(chapter.title)' (\(chapterContent.manifestItems.count) items)")

            } catch {
                Issue.record("Failed to process chapter '\(chapter.title)': \(error.localizedDescription)")
            }
        }

        print("🎉 Successfully validated all chapters")
    }

    @Test func testEPUBParserCleanup() async throws {
        guard let testEPUBPath = Self.findTestEPUBFile() else {
            Issue.record("No test EPUB file found for cleanup test")
            return
        }

        let testDir = try Self.createTestDirectory()
        defer {
            try? FileManager.default.removeItem(at: testDir)
        }

        let parser = EPUBParser(
            epubPath: testEPUBPath,
            identifier: "cleanupTest",
            cacheDirectory: testDir
        )

        // Process EPUB to create cache files
        try await parser.processEPUB()

        // Verify cache directory was created
        let cacheDir = testDir.appendingPathComponent("epub_cleanupTest")
        #expect(FileManager.default.fileExists(atPath: cacheDir.path), "Cache directory should exist after processing")

        // Test cleanup
        parser.cleanup()

        // Verify cache directory was removed
        #expect(!FileManager.default.fileExists(atPath: cacheDir.path), "Cache directory should be removed after cleanup")
    }

    @Test func testInvalidEPUBHandling() async {
        let tempDir = FileManager.default.temporaryDirectory
        let invalidPath = tempDir.appendingPathComponent("nonexistent.epub")

        let parser = EPUBParser(epubPath: invalidPath, identifier: "invalidTest")
        defer {
            parser.cleanup()
        }

        // Should throw an error when trying to process non-existent file
        await #expect(throws: Error.self) {
            try await parser.processEPUB()
        }
    }

    @Test func testConcurrentProcessing() async throws {
        guard let testEPUBPath = Self.findTestEPUBFile() else {
            Issue.record("No test EPUB file found for concurrent test")
            return
        }

        let testDir = try Self.createTestDirectory()
        defer {
            try? FileManager.default.removeItem(at: testDir)
        }

        // Create multiple parsers with different identifiers
        let parsers = (1...3).map { index in
            EPUBParser(
                epubPath: testEPUBPath,
                identifier: "concurrent_\(index)",
                cacheDirectory: testDir
            )
        }

        defer {
            parsers.forEach { $0.cleanup() }
        }

        // Process EPUBs concurrently
        try await withThrowingTaskGroup(of: Int.self) { group in
            for parser in parsers {
                group.addTask {
                    try await parser.processEPUB()
                    return await parser.chapters().count
                }
            }

            var results: [Int] = []
            for try await result in group {
                results.append(result)
            }

            // All parsers should return the same number of chapters
            #expect(Set(results).count == 1, "All parsers should extract the same number of chapters")
            #expect(results.first! > 0, "Should extract at least one chapter")
        }

        print("✅ Concurrent processing test completed successfully")
    }

    @Test func testMultipleEPUBFiles() async throws {
        let allEPUBFiles = Self.findAllTestEPUBFiles()

        guard !allEPUBFiles.isEmpty else {
            Issue.record("No EPUB files found for comprehensive testing")
            return
        }

        // Filter to only valid EPUB files
        let validEPUBFiles = allEPUBFiles.filter { Self.isValidEPUBFile($0) }

        guard !validEPUBFiles.isEmpty else {
            Issue.record("No valid EPUB files found for testing")
            return
        }

        print("🔍 Found \(validEPUBFiles.count) valid EPUB files for testing")

        let testDir = try Self.createTestDirectory()
        defer {
            try? FileManager.default.removeItem(at: testDir)
        }

        var testResults: [(String, Int, Bool)] = []

        for (index, epubFile) in validEPUBFiles.enumerated() {
            let fileName = epubFile.lastPathComponent
            print("\n📖 Testing EPUB \(index + 1)/\(validEPUBFiles.count): \(fileName)")

            let parser = EPUBParser(
                epubPath: epubFile,
                identifier: "multi_test_\(index)",
                cacheDirectory: testDir
            )

            defer {
                parser.cleanup()
            }

            do {
                // Test processing
                try await parser.processEPUB()
                let chapters = await parser.chapters()
                let chapterCount = chapters.count

                print("  ✅ Successfully processed: \(chapterCount) chapters")

                // Test a few chapters for content
                let chaptersToTest = min(3, chapterCount)
                var validChapters = 0

                for i in 0..<chaptersToTest {
                    let chapter = chapters[i]
                    do {
                        let chapterContent = try await parser.chapter(id: chapter.id)
                        let baseURL = await parser.baseURL()
                        let html = try chapterContent.combinedHTML(baseURL: baseURL)

                        if !html.isEmpty {
                            validChapters += 1
                        }
                    } catch {
                        print("    ⚠️ Chapter '\(chapter.title)' content error: \(error.localizedDescription)")
                    }
                }

                let success = validChapters > 0
                testResults.append((fileName, chapterCount, success))

                if success {
                    print("  ✅ Content validation: \(validChapters)/\(chaptersToTest) chapters valid")
                } else {
                    print("  ❌ Content validation failed")
                }

            } catch {
                print("  ❌ Processing failed: \(error.localizedDescription)")
                testResults.append((fileName, 0, false))
            }
        }

        // Summary
        let successfulTests = testResults.filter { $0.2 }.count
        let totalChapters = testResults.reduce(0) { $0 + $1.1 }

        print("\n📊 Test Summary:")
        print("  • Valid EPUB files tested: \(validEPUBFiles.count)")
        print("  • Successful: \(successfulTests)")
        print("  • Failed: \(validEPUBFiles.count - successfulTests)")
        print("  • Total chapters extracted: \(totalChapters)")

        // Detailed results
        for (fileName, chapterCount, success) in testResults {
            let status = success ? "✅" : "❌"
            print("  \(status) \(fileName): \(chapterCount) chapters")
        }

        // At least 70% of valid EPUB files should process successfully
        let successRate = Double(successfulTests) / Double(validEPUBFiles.count)
        #expect(successRate >= 0.7, "At least 70% of valid EPUB files should process successfully (actual: \(Int(successRate * 100))%)")

        // At least one file should have chapters
        #expect(totalChapters > 0, "At least one EPUB should contain chapters")

        print("🎉 Multi-EPUB test completed with \(Int(successRate * 100))% success rate")
    }

    @Test func testEPUBFormatVariations() async throws {
        let allEPUBFiles = Self.findAllTestEPUBFiles()
        let validEPUBFiles = allEPUBFiles.filter { Self.isValidEPUBFile($0) }

        guard validEPUBFiles.count >= 1 else {
            Issue.record("Need at least 1 valid EPUB file to test format variations")
            return
        }

        let testDir = try Self.createTestDirectory()
        defer {
            try? FileManager.default.removeItem(at: testDir)
        }

        var epub2Count = 0
        var epub3Count = 0
        var formatResults: [(String, String)] = []

        for (index, epubFile) in validEPUBFiles.prefix(5).enumerated() {
            let fileName = epubFile.lastPathComponent

            let parser = EPUBParser(
                epubPath: epubFile,
                identifier: "format_test_\(index)",
                cacheDirectory: testDir
            )

            defer {
                parser.cleanup()
            }

            do {
                try await parser.processEPUB()

                // Try to determine EPUB version by checking the structure
                let tempEPUBDir = testDir.appendingPathComponent("epub_format_test_\(index)")

                let hasNCX = FileManager.default.fileExists(atPath: tempEPUBDir.appendingPathComponent("toc.ncx").path)
                let hasNavXHTML = FileManager.default.fileExists(atPath: tempEPUBDir.appendingPathComponent("nav.xhtml").path)

                var detectedFormat = "Unknown"

                if hasNavXHTML {
                    detectedFormat = "EPUB3 (nav.xhtml)"
                    epub3Count += 1
                } else if hasNCX {
                    detectedFormat = "EPUB2 (toc.ncx)"
                    epub2Count += 1
                } else {
                    // Check OPF for version information
                    do {
                        let opfFiles = try FileManager.default.contentsOfDirectory(at: tempEPUBDir, includingPropertiesForKeys: nil)
                            .filter { $0.pathExtension == "opf" }

                        if let opfFile = opfFiles.first {
                            let opfContent = try String(contentsOf: opfFile)
                            if opfContent.contains("version=\"3.0\"") {
                                detectedFormat = "EPUB3 (detected)"
                                epub3Count += 1
                            } else if opfContent.contains("version=\"2.0\"") {
                                detectedFormat = "EPUB2 (detected)"
                                epub2Count += 1
                            }
                        }
                    } catch {
                        print("    ⚠️ Could not analyze OPF for \(fileName)")
                    }
                }

                formatResults.append((fileName, detectedFormat))
                print("📚 \(fileName): \(detectedFormat)")

            } catch {
                formatResults.append((fileName, "Failed: \(error.localizedDescription)"))
                print("❌ \(fileName): Processing failed")
            }
        }

        print("\n📊 Format Analysis:")
        print("  • EPUB2 files: \(epub2Count)")
        print("  • EPUB3 files: \(epub3Count)")

        for (fileName, format) in formatResults {
            print("  • \(fileName): \(format)")
        }

        // Verify we can handle at least one format
        #expect(epub2Count + epub3Count > 0, "Should detect at least one valid EPUB format")

        print("✅ Format variation test completed")
    }
}
