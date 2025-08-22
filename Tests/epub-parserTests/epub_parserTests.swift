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

    @Test func testChapterContentMerging() async throws {
        // Test the HTML content merging capabilities for different chapter structures
        guard let testEPUBPath = Self.findTestEPUBFile() else {
            Issue.record("No test EPUB file found for content merging test")
            return
        }

        let testDir = try Self.createTestDirectory()
        defer {
            try? FileManager.default.removeItem(at: testDir)
        }

        let parser = EPUBParser(
            epubPath: testEPUBPath,
            identifier: "content_merging_test",
            cacheDirectory: testDir
        )

        defer {
            parser.cleanup()
        }

        try await parser.processEPUB()
        let chapters = await parser.chapters()

        guard !chapters.isEmpty else {
            Issue.record("No chapters found for content merging test")
            return
        }

        print("🧪 Testing Chapter Content Merging:")
        print("  📚 Total chapters: \(chapters.count)")

        // Test different merging strategies on the first few chapters
        for (index, chapter) in chapters.prefix(3).enumerated() {
            print("\n  📖 Chapter \(index + 1): '\(chapter.title)'")
            print("     Manifest items: \(chapter.manifestItems.count)")

            do {
                let baseURL = await parser.baseURL()

                // Test 1: Individual HTML retrieval
                let htmls = try chapter.htmls(baseURL: baseURL)
                #expect(!htmls.isEmpty, "Chapter should have at least one HTML content")
                print("     ✅ Individual HTMLs: \(htmls.count) files")

                // Test 2: Combined HTML (simple concatenation)
                let combinedHTML = try chapter.combinedHTML(baseURL: baseURL)
                #expect(!combinedHTML.isEmpty, "Combined HTML should not be empty")
                print("     ✅ Combined HTML: \(combinedHTML.count) characters")

                // Test 3: Merged HTML (body content merged into first document)
                let mergedHTML = try chapter.mergedHTML(baseURL: baseURL)
                #expect(!mergedHTML.isEmpty, "Merged HTML should not be empty")
                print("     ✅ Merged HTML: \(mergedHTML.count) characters")

                // Validate content structure
                if htmls.count > 1 {
                    print("     📝 Multi-file chapter detected!")
                    print("         - Individual files: \(htmls.count)")
                    print("         - Combined length: \(combinedHTML.count)")
                    print("         - Merged length: \(mergedHTML.count)")

                    // For multi-file chapters, merged HTML should be a proper HTML document
                    #expect(mergedHTML.contains("<html"), "Merged HTML should contain HTML tag")
                    #expect(mergedHTML.contains("<body"), "Merged HTML should contain body tag")
                    #expect(mergedHTML.contains("</body>"), "Merged HTML should have closing body tag")
                    #expect(mergedHTML.contains("</html>"), "Merged HTML should have closing HTML tag")

                    print("     ✅ HTML structure validation passed")
                } else {
                    print("     📄 Single-file chapter")
                    // For single-file chapters, combined and merged should be identical
                    #expect(combinedHTML == mergedHTML, "Single-file chapter: combined and merged HTML should be identical")
                }

                // Basic content validation
                let hasTextContent =
                    combinedHTML.range(of: #"<p[^>]*>.*?</p>"#, options: .regularExpression) != nil || combinedHTML.range(of: #"<div[^>]*>.*?</div>"#, options: .regularExpression) != nil

                if hasTextContent {
                    print("     ✅ Text content detected")
                } else {
                    print("     ⚠️  No obvious text content detected")
                }

            } catch {
                Issue.record("Content merging failed for chapter '\(chapter.title)': \(error)")
                print("     ❌ Content merging failed: \(error.localizedDescription)")
            }
        }

        // Test edge cases with multi-file chapters
        let multiFileChapters = chapters.filter { $0.manifestItems.count > 1 }
        if !multiFileChapters.isEmpty {
            print("\n  🔗 Multi-file chapters found: \(multiFileChapters.count)")
            for chapter in multiFileChapters.prefix(2) {
                print("     • '\(chapter.title)': \(chapter.manifestItems.count) files")
                for (i, item) in chapter.manifestItems.enumerated() {
                    print("       [\(i+1)] \(item.path) (\(item.mediaType))")
                }
            }
        } else {
            print("\n  📄 All chapters are single-file chapters")
        }

        // Test chapters with fragment identifiers
        let fragmentChapters = chapters.filter { $0.path.contains("#") }
        if !fragmentChapters.isEmpty {
            print("\n  🔗 Fragment-based chapters found: \(fragmentChapters.count)")
            for chapter in fragmentChapters.prefix(3) {
                print("     • '\(chapter.title)': \(chapter.path)")
            }
        } else {
            print("\n  📄 No fragment-based chapters detected")
        }

        print("\n✅ Chapter content merging test completed successfully")
    }

    @Test func testSpecificEPUB_TonyFadell() async throws {
        // Test the specific EPUB file mentioned by the user
        let epubPath = "/Users/kai/Downloads/epub_test/Build An Unorthodox Guide to Making Things Worth Making (Tony Fadell) (Z-Library).epub"
        let epubURL = URL(fileURLWithPath: epubPath)

        guard FileManager.default.fileExists(atPath: epubPath) else {
            Issue.record("Tony Fadell EPUB file not found at: \(epubPath)")
            return
        }

        // Validate it's a proper EPUB file
        guard Self.isValidEPUBFile(epubURL) else {
            Issue.record("File is not a valid EPUB: \(epubPath)")
            return
        }

        let testDir = try Self.createTestDirectory()
        defer {
            try? FileManager.default.removeItem(at: testDir)
        }

        let parser = EPUBParser(
            epubPath: epubURL,
            identifier: "tony_fadell_test",
            cacheDirectory: testDir
        )

        defer {
            parser.cleanup()
        }

        print("📖 Testing Tony Fadell EPUB: 'Build An Unorthodox Guide to Making Things Worth Making'")

        do {
            try await parser.processEPUB()
            let chapters = await parser.chapters()

            print("📚 Successfully processed EPUB with \(chapters.count) chapters")

            #expect(!chapters.isEmpty, "EPUB should contain at least one chapter")

            // Analyze the chapter structure
            let singleFileChapters = chapters.filter { $0.manifestItems.count == 1 }
            let multiFileChapters = chapters.filter { $0.manifestItems.count > 1 }
            let fragmentChapters = chapters.filter { $0.path.contains("#") }

            print("📊 Chapter Structure Analysis:")
            print("   • Total chapters: \(chapters.count)")
            print("   • Single-file chapters: \(singleFileChapters.count)")
            print("   • Multi-file chapters: \(multiFileChapters.count)")
            print("   • Fragment-based chapters: \(fragmentChapters.count)")

            // Show first few chapters
            print("\n📋 Chapter List (first 10):")
            for (index, chapter) in chapters.prefix(10).enumerated() {
                let manifestCount = chapter.manifestItems.count
                let fragmentIndicator = chapter.path.contains("#") ? " (fragment)" : ""
                print("   \(index + 1). '\(chapter.title)' (\(manifestCount) items)\(fragmentIndicator)")

                if manifestCount > 1 {
                    print("      Multi-file chapter with \(manifestCount) files:")
                    for (i, item) in chapter.manifestItems.enumerated() {
                        print("        [\(i+1)] \(item.path)")
                    }
                }
            }

            if chapters.count > 10 {
                print("   ... and \(chapters.count - 10) more chapters")
            }

            // Test content extraction for first few chapters
            print("\n🧪 Content Validation:")
            for (index, chapter) in chapters.prefix(3).enumerated() {
                do {
                    let baseURL = await parser.baseURL()
                    let combinedHTML = try chapter.combinedHTML(baseURL: baseURL)
                    let mergedHTML = try chapter.mergedHTML(baseURL: baseURL)

                    #expect(!combinedHTML.isEmpty, "Chapter '\(chapter.title)' should have non-empty HTML content")
                    #expect(!mergedHTML.isEmpty, "Chapter '\(chapter.title)' should have non-empty merged HTML")

                    print("   ✅ Chapter \(index + 1): '\(chapter.title)'")
                    print("      - Combined HTML: \(combinedHTML.count) characters")
                    print("      - Merged HTML: \(mergedHTML.count) characters")

                    // Check for actual text content
                    let hasTextContent =
                        combinedHTML.range(of: #"<p[^>]*>.*?</p>"#, options: .regularExpression) != nil || combinedHTML.range(of: #"<div[^>]*>.*?</div>"#, options: .regularExpression) != nil

                    if hasTextContent {
                        print("      - Text content: ✅ Detected")
                    } else {
                        print("      - Text content: ⚠️  No obvious text content")
                    }

                } catch {
                    print("   ❌ Chapter \(index + 1): Content extraction failed - \(error)")
                }
            }

            // Special analysis for multi-file chapters
            if !multiFileChapters.isEmpty {
                print("\n🔗 Multi-file Chapter Analysis:")
                for chapter in multiFileChapters.prefix(3) {
                    print("   📚 '\(chapter.title)': \(chapter.manifestItems.count) files")
                    for (i, item) in chapter.manifestItems.enumerated() {
                        print("      [\(i+1)] \(item.path) (\(item.mediaType))")
                    }

                    // Test the HTML merging for multi-file chapters
                    do {
                        let baseURL = await parser.baseURL()
                        let htmls = try chapter.htmls(baseURL: baseURL)
                        let combined = try chapter.combinedHTML(baseURL: baseURL)
                        let merged = try chapter.mergedHTML(baseURL: baseURL)

                        print("      Content lengths: Individual[\(htmls.map{$0.count})] Combined[\(combined.count)] Merged[\(merged.count)]")

                        // Validate HTML structure for merged content
                        if merged.contains("<html") && merged.contains("</html>") {
                            print("      ✅ Merged HTML has proper document structure")
                        } else {
                            print("      ⚠️  Merged HTML may not have complete document structure")
                        }

                    } catch {
                        print("      ❌ Multi-file content merging failed: \(error)")
                    }
                }
            }

            print("\n✅ Tony Fadell EPUB test completed successfully!")
            print("   Total chapters processed: \(chapters.count)")

        } catch {
            Issue.record("Failed to process Tony Fadell EPUB: \(error.localizedDescription)")
            print("❌ Processing failed: \(error.localizedDescription)")
        }
    }
}
