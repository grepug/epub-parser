import Foundation
import Testing

@testable import EPUBParser

/// Shared test configuration and utilities for EPUB parser tests
struct TestConfiguration {

    // MARK: - Test Configuration

    /// Configurable list of EPUB files for testing
    /// Add your EPUB file paths here to include them in concurrent testing
    static let configuredTestEPUBs: [String] = [
        // Working EPUB files only
        // "/Users/kai/Downloads/epub_test/Build An Unorthodox Guide to Making Things Worth Making (Tony Fadell) (Z-Library).epub",
        // "/Users/kai/Downloads/epub_test/Data science from scratch the 1 data science guide for everything a data scientist needs to know Python, linear algebra,... (Cooper, Steven) (Z-Library).epub",

        // Corrupted files - commented out until re-downloaded
        // "/Users/kai/Downloads/epub_test/The 7 Habits of Highly Effective People- Powerful Lessons in -- Stephen R. Covey -- 2017 -- Infographics -- 9781633533103 -- cf7f01f2c4c337eec89aafe62c32ee62 -- Anna's Archive.epub",
        // "/Users/kai/Downloads/Atomic Habits (James Clear) (Z-Library).epub",
        // "/Users/kai/Downloads/Elon Musk (Walter Isaacson) (Z-Library).epub",

        // EPUBs from /Users/kai/Downloads/epub folder
        "/Users/kai/Downloads/epub/14238.epub",
        "/Users/kai/Downloads/epub/14598.epub",
        "/Users/kai/Downloads/epub/19547.epub",
        "/Users/kai/Downloads/epub/25230.epub",
        "/Users/kai/Downloads/epub/4954.epub",
        "/Users/kai/Downloads/epub/88874.epub",
        "/Users/kai/Downloads/epub/Call+Me+by+Your+Name.epub",
        "/Users/kai/Downloads/epub/EBook_1753371031.epub",
        "/Users/kai/Downloads/epub/habits.epub",
    ]

    /// Additional directories to search for EPUB files (if auto-discovery is enabled)
    static let autoDiscoveryDirectories: [String] = [
        "/Users/kai/Downloads/epub",  // Primary test folder
        "/Users/kai/Downloads/epub_test",
        "/Users/kai/Downloads",
        "/Users/kai/Documents",
        "~/Downloads",
        "~/Documents",
    ]

    /// Whether to enable auto-discovery of EPUB files in addition to configured list
    /// Can be overridden with environment variable: EPUB_AUTO_DISCOVERY=true/false
    static let enableAutoDiscovery: Bool = {
        if let envValue = ProcessInfo.processInfo.environment["EPUB_AUTO_DISCOVERY"] {
            return envValue.lowercased() == "true"
        }
        return false  // Default value
    }()

    /// Maximum number of EPUB files to test concurrently (to avoid resource exhaustion)
    static let maxConcurrentTests: Int = 12

    // MARK: - Utility Methods

    /// Attempts to find a suitable EPUB file for testing
    static func findTestEPUBFile() -> URL? {
        let allFiles = findAllTestEPUBFiles()
        return allFiles.first
    }

    /// Finds all available EPUB files for comprehensive testing
    static func findAllTestEPUBFiles() -> [URL] {
        let fileManager = FileManager.default
        var foundFiles: [URL] = []

        // First, add all configured EPUB files that exist
        for epubPath in configuredTestEPUBs {
            let expandedPath = NSString(string: epubPath).expandingTildeInPath
            let url = URL(fileURLWithPath: expandedPath)
            if fileManager.fileExists(atPath: url.path) && isValidEPUBFile(url) {
                foundFiles.append(url)
            }
        }

        // Then, if auto-discovery is enabled, search for additional EPUB files
        if enableAutoDiscovery {
            for directory in autoDiscoveryDirectories {
                let expandedPath = NSString(string: directory).expandingTildeInPath
                let dirURL = URL(fileURLWithPath: expandedPath)

                guard let enumerator = fileManager.enumerator(at: dirURL, includingPropertiesForKeys: nil) else {
                    continue
                }

                for case let fileURL as URL in enumerator {
                    let ext = fileURL.pathExtension.lowercased()
                    let fileName = fileURL.lastPathComponent.lowercased()

                    // Only include actual EPUB files, exclude problematic files, and avoid duplicates
                    if ext == "epub"
                        && !fileName.contains("module")
                        && !fileName.contains("skeleton")
                        && !fileName.contains("eureka")
                        && !fileName.hasPrefix("dongurami")
                        && !fileName.contains("visionarytech")
                        && !foundFiles.contains(fileURL)
                    {
                        foundFiles.append(fileURL)
                    }
                }
            }
        }

        // Limit to avoid excessive test times and resource usage
        return Array(foundFiles.prefix(maxConcurrentTests))
    }

    /// Creates a temporary directory for test operations
    static func createTestDirectory() throws -> URL {
        let tempDir = FileManager.default.temporaryDirectory
        let testDir = tempDir.appendingPathComponent("EPUBParserTests_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: testDir, withIntermediateDirectories: true)
        return testDir
    }

    /// Quick validation to check if a file is likely a valid EPUB
    static func isValidEPUBFile(_ url: URL) -> Bool {
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
}

/// Test result structure for concurrent testing
struct EPUBTestResult {
    let fileName: String
    let success: Bool
    let chapterCount: Int
    let epubFormat: String
    let fragmentChapters: Int
    let error: String?
}

/// Test a single EPUB file and return results
func testSingleEPUB(file: URL, identifier: String, testDir: URL) async -> EPUBTestResult {
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
        try await parser.processEPUB()
        let chapters = await parser.chapters()

        // Analyze chapter structure
        let fragmentChapters = chapters.filter { $0.path.contains("#") }.count

        // Determine EPUB format
        let tempEPUBDir = testDir.appendingPathComponent("epub_\(identifier)")
        var epubFormat = ""

        if FileManager.default.fileExists(atPath: tempEPUBDir.appendingPathComponent("nav.xhtml").path) {
            epubFormat = "EPUB3"
        } else if FileManager.default.fileExists(atPath: tempEPUBDir.appendingPathComponent("toc.ncx").path) {
            epubFormat = "EPUB2"
        }

        // Test content extraction for first chapter
        if let firstChapter = chapters.first {
            let baseURL = await parser.baseURL()
            let _ = try firstChapter.combinedHTML(baseURL: baseURL)
        }

        return EPUBTestResult(
            fileName: fileName,
            success: true,
            chapterCount: chapters.count,
            epubFormat: epubFormat,
            fragmentChapters: fragmentChapters,
            error: nil
        )

    } catch {
        return EPUBTestResult(
            fileName: fileName,
            success: false,
            chapterCount: 0,
            epubFormat: "",
            fragmentChapters: 0,
            error: String(describing: error)
        )
    }
}
