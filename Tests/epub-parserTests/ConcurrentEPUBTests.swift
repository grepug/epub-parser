import Foundation
import Testing

@testable import EPUBParser

/// Concurrent processing and multi-file EPUB tests
struct ConcurrentEPUBTests {

    @Test func testConcurrentProcessing() async throws {
        guard let testEPUBPath = TestConfiguration.findTestEPUBFile() else {
            Issue.record("No test EPUB file found for concurrent test")
            return
        }

        let testDir = try TestConfiguration.createTestDirectory()
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

    @Test func testConfiguredEPUBsConcurrently() async throws {
        let allEPUBFiles = TestConfiguration.findAllTestEPUBFiles()

        guard !allEPUBFiles.isEmpty else {
            Issue.record("No EPUB files found. Please add EPUB file paths to configuredTestEPUBs or enable auto-discovery")
            return
        }

        print("🚀 Starting concurrent test of \(allEPUBFiles.count) EPUB files")
        print("📋 Files to test:")
        for (index, file) in allEPUBFiles.enumerated() {
            print("   \(index + 1). \(file.lastPathComponent)")
        }

        let testDir = try TestConfiguration.createTestDirectory()
        defer {
            try? FileManager.default.removeItem(at: testDir)
        }

        // Test all EPUBs concurrently
        let startTime = Date()

        let results = try await withThrowingTaskGroup(of: (String, EPUBTestResult).self, returning: [EPUBTestResult].self) { group in
            for (index, epubFile) in allEPUBFiles.enumerated() {
                group.addTask {
                    let fileName = epubFile.lastPathComponent
                    let result = await testSingleEPUB(
                        file: epubFile,
                        identifier: "concurrent_\(index)",
                        testDir: testDir
                    )
                    return (fileName, result)
                }
            }

            var allResults: [EPUBTestResult] = []
            for try await (fileName, result) in group {
                print("✅ Completed: \(fileName) - \(result.chapterCount) chapters")
                allResults.append(result)
            }
            return allResults
        }

        let endTime = Date()
        let duration = endTime.timeIntervalSince(startTime)

        // Analyze results
        let successful = results.filter { $0.success }
        let failed = results.filter { !$0.success }
        let totalChapters = results.reduce(0) { $0 + $1.chapterCount }

        print("\n📊 Concurrent Test Results:")
        print("   ⏱️  Total time: \(String(format: "%.2f", duration)) seconds")
        print("   📚 Files tested: \(results.count)")
        print("   ✅ Successful: \(successful.count)")
        print("   ❌ Failed: \(failed.count)")
        print("   📖 Total chapters: \(totalChapters)")

        if !failed.isEmpty {
            print("\n❌ Failed files:")
            for result in failed {
                print("   • \(result.fileName): \(result.error ?? "Unknown error")")
            }
        }

        print("\n✅ Successful files:")
        for result in successful {
            let formatInfo = result.epubFormat.isEmpty ? "" : " (\(result.epubFormat))"
            let fragmentInfo = result.fragmentChapters > 0 ? " - \(result.fragmentChapters) fragment chapters" : ""
            print("   • \(result.fileName): \(result.chapterCount) chapters\(formatInfo)\(fragmentInfo)")
        }

        // Test assertions
        let successRate = Double(successful.count) / Double(results.count)
        #expect(successRate >= 0.8, "At least 80% of EPUB files should process successfully (actual: \(Int(successRate * 100))%)")
        #expect(totalChapters > 0, "At least one EPUB should contain chapters")

        print("\n🎉 Concurrent test completed with \(Int(successRate * 100))% success rate in \(String(format: "%.2f", duration))s")
    }

    @Test func testMultipleEPUBFiles() async throws {
        let allEPUBFiles = TestConfiguration.findAllTestEPUBFiles()

        guard !allEPUBFiles.isEmpty else {
            Issue.record("No EPUB files found for comprehensive testing")
            return
        }

        // Filter to only valid EPUB files
        let validEPUBFiles = allEPUBFiles.filter { TestConfiguration.isValidEPUBFile($0) }

        guard !validEPUBFiles.isEmpty else {
            Issue.record("No valid EPUB files found for testing")
            return
        }

        print("🔍 Found \(validEPUBFiles.count) valid EPUB files for testing")

        let testDir = try TestConfiguration.createTestDirectory()
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

                // Test a few chapters for content and word count
                let chaptersToTest = min(3, chapterCount)
                var validChapters = 0
                var totalWords = 0

                for i in 0..<chaptersToTest {
                    let chapter = chapters[i]
                    do {
                        let chapterContent = try await parser.chapter(id: chapter.id)
                        let baseURL = await parser.baseURL()
                        let html = try chapterContent.combinedHTML(baseURL: baseURL)

                        if !html.isEmpty {
                            let wordCount = try chapterContent.wordCount(baseURL: baseURL)
                            totalWords += wordCount

                            if wordCount >= 100 {
                                validChapters += 1
                            } else {
                                print("    ⚠️ Chapter '\(chapter.title)' has only \(wordCount) words (<100)")
                            }
                        }
                    } catch {
                        print("    ⚠️ Chapter '\(chapter.title)' content error: \(String(describing: error))")
                    }
                }

                let success = validChapters > 0
                testResults.append((fileName, chapterCount, success))

                if success {
                    print("  ✅ Content validation: \(validChapters)/\(chaptersToTest) chapters valid (≥100 words each)")
                    print("  📝 Total words in tested chapters: \(totalWords)")
                } else {
                    print("  ❌ Content validation failed - no chapters meet minimum word count")
                }

            } catch {
                print("  ❌ Processing failed: \(String(describing: error))")
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
}
