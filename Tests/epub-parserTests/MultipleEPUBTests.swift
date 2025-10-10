import Foundation
import Testing

@testable import EPUBParser

/// Tests for validating multiple EPUB files from test directory
@Suite("Multiple EPUB Files Validation")
struct MultipleEPUBTests {

    @Test("Validate all EPUB files")
    func testAllEPUBFiles() async throws {
        let epubFiles = TestConfiguration.findAllTestEPUBFiles()

        guard !epubFiles.isEmpty else {
            Issue.record("No EPUB files found. Please add EPUB files to /Users/kai/Downloads/epub")
            return
        }

        print("📚 Found \(epubFiles.count) EPUB files to validate")
        print("📋 Files:")
        for (index, file) in epubFiles.enumerated() {
            print("  \(index + 1). \(file.lastPathComponent)")
        }

        let testDir = try TestConfiguration.createTestDirectory()
        defer {
            try? FileManager.default.removeItem(at: testDir)
        }

        var testResults: [EPUBTestResult] = []

        for (index, epubFile) in epubFiles.enumerated() {
            let fileName = epubFile.lastPathComponent
            print("\n📖 Testing [\(index + 1)/\(epubFiles.count)]: \(fileName)")

            let result = await testEPUBFile(
                file: epubFile,
                identifier: "multi_test_\(index)",
                testDir: testDir
            )

            testResults.append(result)

            if result.success {
                print("  ✅ Success")
                print("    - TOC: \(result.tocCount) items")
                print("    - Spine: \(result.spineCount) items")
                print("    - Manifest: \(result.manifestCount) items")
                print("    - HTML files: \(result.htmlFileCount)")

                if let title = result.metadata.title {
                    print("    - Title: \(title)")
                }
                if !result.metadata.creators.isEmpty {
                    print("    - Authors: \(result.metadata.creators.joined(separator: ", "))")
                }
            } else {
                print("  ❌ Failed: \(result.error ?? "Unknown error")")
            }
        }

        // Summary
        let successful = testResults.filter { $0.success }
        let failed = testResults.filter { !$0.success }

        print("\n" + String(repeating: "=", count: 60))
        print("📊 Test Summary")
        print(String(repeating: "=", count: 60))
        print("  Total files tested: \(testResults.count)")
        print("  ✅ Successful: \(successful.count)")
        print("  ❌ Failed: \(failed.count)")
        print("  Success rate: \(Int(Double(successful.count) / Double(testResults.count) * 100))%")

        if !failed.isEmpty {
            print("\n❌ Failed files:")
            for result in failed {
                print("  • \(result.fileName)")
                print("    Error: \(result.error ?? "Unknown")")
            }
        }

        print("\n✅ Successful files:")
        for result in successful {
            print("  • \(result.fileName)")
            print("    TOC: \(result.tocCount), Spine: \(result.spineCount), Manifest: \(result.manifestCount)")
        }

        // Statistics
        if !successful.isEmpty {
            let avgTOC = successful.reduce(0) { $0 + $1.tocCount } / successful.count
            let avgSpine = successful.reduce(0) { $0 + $1.spineCount } / successful.count
            let avgManifest = successful.reduce(0) { $0 + $1.manifestCount } / successful.count

            print("\n📈 Statistics (successful files):")
            print("  Average TOC items: \(avgTOC)")
            print("  Average spine items: \(avgSpine)")
            print("  Average manifest items: \(avgManifest)")
        }

        // Assertions
        let successRate = Double(successful.count) / Double(testResults.count)
        #expect(successRate >= 0.7, "At least 70% of EPUBs should process successfully")

        print("\n🎉 Validation complete")
    }

    @Test("Validate EPUB formats")
    func testEPUBFormats() async throws {
        let epubFiles = TestConfiguration.findAllTestEPUBFiles()

        guard !epubFiles.isEmpty else {
            Issue.record("No EPUB files found")
            return
        }

        print("📋 Analyzing EPUB Formats")

        let testDir = try TestConfiguration.createTestDirectory()
        defer {
            try? FileManager.default.removeItem(at: testDir)
        }

        var epub2Count = 0
        var epub3Count = 0
        var unknownCount = 0

        for (index, epubFile) in epubFiles.enumerated() {
            let parser = EPUBParser(
                epubPath: epubFile,
                identifier: "format_test_\(index)",
                cacheDirectory: testDir
            )

            defer { parser.cleanup() }

            do {
                let document = try await parser.processEPUB()

                // Try to determine format based on TOC file extension
                // This is a heuristic - NCX = EPUB 2, nav.xhtml = EPUB 3
                let hasNCX = document.tableOfContents.count > 0  // If we parsed it, we found some TOC

                // Check metadata for EPUB 3 specific fields
                let hasEPUB3Features = !document.metadata.additionalMetadata.isEmpty

                if hasEPUB3Features {
                    epub3Count += 1
                    print("  • \(epubFile.lastPathComponent): EPUB 3 (likely)")
                } else if hasNCX {
                    epub2Count += 1
                    print("  • \(epubFile.lastPathComponent): EPUB 2 (likely)")
                } else {
                    unknownCount += 1
                    print("  • \(epubFile.lastPathComponent): Unknown format")
                }
            } catch {
                print("  • \(epubFile.lastPathComponent): Failed to analyze")
                unknownCount += 1
            }
        }

        print("\n📊 Format Distribution:")
        print("  EPUB 2: \(epub2Count)")
        print("  EPUB 3: \(epub3Count)")
        print("  Unknown: \(unknownCount)")

        #expect(epub2Count + epub3Count > 0, "Should identify at least some EPUB formats")
    }
}

/// Detailed test result for an EPUB file
struct EPUBTestResult {
    let fileName: String
    let success: Bool
    let tocCount: Int
    let spineCount: Int
    let manifestCount: Int
    let htmlFileCount: Int
    let metadata: MetadataInfo
    let error: String?

    struct MetadataInfo {
        let title: String?
        let creators: [String]
        let language: String?
    }
}

/// Test a single EPUB file with detailed validation
private func testEPUBFile(file: URL, identifier: String, testDir: URL) async -> EPUBTestResult {
    let fileName = file.lastPathComponent

    let parser = EPUBParser(
        epubPath: file,
        identifier: identifier,
        cacheDirectory: testDir
    )

    defer {
        parser.cleanup()
    }

    do {
        let document = try await parser.processEPUB()

        let metadata = EPUBTestResult.MetadataInfo(
            title: document.metadata.title,
            creators: document.metadata.creators,
            language: document.metadata.language
        )

        return EPUBTestResult(
            fileName: fileName,
            success: true,
            tocCount: document.tableOfContents.count,
            spineCount: document.spine.count,
            manifestCount: document.manifest.count,
            htmlFileCount: document.htmlManifestItems.count,
            metadata: metadata,
            error: nil
        )
    } catch {
        return EPUBTestResult(
            fileName: fileName,
            success: false,
            tocCount: 0,
            spineCount: 0,
            manifestCount: 0,
            htmlFileCount: 0,
            metadata: EPUBTestResult.MetadataInfo(title: nil, creators: [], language: nil),
            error: String(describing: error)
        )
    }
}
