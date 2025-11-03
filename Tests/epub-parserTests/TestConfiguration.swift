import Foundation

/// Configuration for EPUB parser tests
struct TestConfiguration {

    /// Configured test EPUB file paths
    /// Add specific EPUB file paths here for testing
    static let configuredTestEPUBs: [String] = [
        // Example: "/Users/username/Downloads/sample.epub"
        "/Users/kai/Downloads/epub/Build.epub",
        "/Users/kai/Downloads/epub/TheEconomist.2025.11.01.epub",
        "/Users/kai/Downloads/epub/考研英语黄皮书 2015.12~2016.5.epub",
    ]

    /// Test directories to scan for EPUB files
    static let testDirectories: [String] = [
        "/Users/kai/Downloads/epub"
    ]

    /// Whether to enable automatic discovery of EPUB files in Downloads
    static let enableAutoDiscovery = true

    /// Maximum file size for auto-discovered EPUBs (in bytes)
    static let maxAutoDiscoveryFileSize: Int64 = 50 * 1024 * 1024  // 50 MB

    // MARK: - Helper Methods

    /// Find a test EPUB file (first available)
    static func findTestEPUBFile() -> URL? {
        // First try configured paths
        for path in configuredTestEPUBs {
            let url = URL(fileURLWithPath: path)
            if FileManager.default.fileExists(atPath: url.path) {
                return url
            }
        }

        // Then try auto-discovery if enabled
        if enableAutoDiscovery {
            return findAllTestEPUBFiles().first
        }

        return nil
    }

    /// Find all available test EPUB files
    static func findAllTestEPUBFiles() -> [URL] {
        var epubFiles: [URL] = []

        // Add configured EPUBs that exist
        for path in configuredTestEPUBs {
            let url = URL(fileURLWithPath: path)
            if FileManager.default.fileExists(atPath: url.path) {
                epubFiles.append(url)
            }
        }

        // Add EPUBs from configured test directories
        for dirPath in testDirectories {
            let dirURL = URL(fileURLWithPath: dirPath)
            if FileManager.default.fileExists(atPath: dirURL.path) {
                epubFiles.append(contentsOf: findEPUBFiles(in: dirURL))
            }
        }

        // Add auto-discovered EPUBs if enabled
        if enableAutoDiscovery {
            if let downloadsDir = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first {
                epubFiles.append(contentsOf: findEPUBFiles(in: downloadsDir))
            }
        }

        // Remove duplicates based on path
        let uniqueFiles = Array(Set(epubFiles.map { $0.standardizedFileURL }))

        return uniqueFiles
    }

    /// Find EPUB files in a directory
    private static func findEPUBFiles(in directory: URL) -> [URL] {
        guard
            let enumerator = FileManager.default.enumerator(
                at: directory,
                includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey],
                options: [.skipsHiddenFiles]
            )
        else {
            return []
        }

        var epubFiles: [URL] = []

        for case let fileURL as URL in enumerator {
            guard fileURL.pathExtension.lowercased() == "epub" else { continue }

            // Check file size
            if let resourceValues = try? fileURL.resourceValues(forKeys: [.fileSizeKey]),
                let fileSize = resourceValues.fileSize
            {
                if Int64(fileSize) <= maxAutoDiscoveryFileSize {
                    epubFiles.append(fileURL)
                }
            }
        }

        return epubFiles
    }

    /// Validate that a file is a valid EPUB
    static func isValidEPUBFile(_ url: URL) -> Bool {
        guard FileManager.default.fileExists(atPath: url.path) else {
            return false
        }

        guard url.pathExtension.lowercased() == "epub" else {
            return false
        }

        // Check file size
        if let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
            let fileSize = attributes[.size] as? Int64
        {
            return fileSize > 0 && fileSize <= maxAutoDiscoveryFileSize
        }

        return false
    }

    /// Create a temporary test directory
    static func createTestDirectory() throws -> URL {
        let tempDir = FileManager.default.temporaryDirectory
        let testDir = tempDir.appendingPathComponent("EPUBParserTests_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: testDir, withIntermediateDirectories: true)
        return testDir
    }

    /// Create a test destination URL for a specific test
    static func testDestinationURL(for testName: String) -> URL {
        let tempDir = FileManager.default.temporaryDirectory
        return tempDir.appendingPathComponent("EPUBParser_\(testName)_\(UUID().uuidString)")
    }
}
