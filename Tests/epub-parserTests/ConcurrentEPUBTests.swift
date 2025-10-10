import Foundation
import Testing

@testable import EPUBParser

/// Concurrent processing and multi-file EPUB tests
@Suite("Concurrent EPUB Processing")
struct ConcurrentEPUBTests {

    @Test("Process multiple EPUBs concurrently")
    func testConcurrentProcessing() async throws {
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
                    let document = try await parser.processEPUB()
                    return document.tableOfContents.count
                }
            }

            var results: [Int] = []
            for try await result in group {
                results.append(result)
            }

            // All parsers should return the same number of TOC items
            #expect(Set(results).count == 1, "All parsers should extract the same structure")
            #expect(results.first! > 0, "Should extract at least one TOC item")
        }

        print("✅ Concurrent processing test completed successfully")
    }

    @Test("Process same EPUB multiple times concurrently")
    func testSameEPUBConcurrent() async throws {
        guard let testEPUBPath = TestConfiguration.findTestEPUBFile() else {
            Issue.record("No test EPUB file found")
            return
        }

        let testDir = try TestConfiguration.createTestDirectory()
        defer {
            try? FileManager.default.removeItem(at: testDir)
        }

        print("🔄 Processing same EPUB 5 times concurrently")

        // Create 5 parsers with different identifiers
        let parsers = (1...5).map { index in
            EPUBParser(
                epubPath: testEPUBPath,
                identifier: "same_epub_\(index)",
                cacheDirectory: testDir
            )
        }

        defer {
            parsers.forEach { $0.cleanup() }
        }

        // Process concurrently
        try await withThrowingTaskGroup(of: (Int, Int, Int).self) { group in
            for (index, parser) in parsers.enumerated() {
                group.addTask {
                    let document = try await parser.processEPUB()
                    return (index, document.tableOfContents.count, document.spine.count)
                }
            }

            var results: [(Int, Int, Int)] = []
            for try await result in group {
                results.append(result)
                print("  ✓ Parser \(result.0 + 1): \(result.1) TOC, \(result.2) spine")
            }

            // All parsers should return the same counts
            let tocCounts = Set(results.map { $0.1 })
            let spineCounts = Set(results.map { $0.2 })

            #expect(tocCounts.count == 1, "All parsers should extract same TOC count")
            #expect(spineCounts.count == 1, "All parsers should extract same spine count")
        }

        print("✅ Concurrent processing of same EPUB validated")
    }
}
