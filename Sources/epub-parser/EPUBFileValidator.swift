import Foundation

/// Handles file validation and path operations for EPUB processing
internal struct EPUBFileValidator {
    private let fileManager: FileManager

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    /// Validates that an OPF file exists at the given URL
    /// - Parameter url: The URL to check
    /// - Returns: True if the file exists and is readable
    func validateOPFFile(at url: URL) -> Bool {
        return fileManager.fileExists(atPath: url.path) && fileManager.isReadableFile(atPath: url.path)
    }

    /// Validates that a container.xml file exists and is readable
    /// - Parameter url: The URL to check
    /// - Returns: True if the file exists and is readable
    func validateContainerXML(at url: URL) -> Bool {
        return fileManager.fileExists(atPath: url.path) && fileManager.isReadableFile(atPath: url.path)
    }

    /// Checks if the given URL points to a directory
    /// - Parameter url: The URL to check
    /// - Returns: True if the URL points to a directory
    func isDirectory(_ url: URL) -> Bool {
        var isDirectory: ObjCBool = false
        return fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory) && isDirectory.boolValue
    }

    /// Normalizes paths for comparison by removing common variations
    /// - Parameter path: The path to normalize
    /// - Returns: A normalized path string
    static func normalizePathForComparison(_ path: String) -> String {
        return
            path
            .lowercased()
            .replacingOccurrences(of: "\\", with: "/")
            .trimmingCharacters(in: CharacterSet(charactersIn: "./"))
    }

    /// Validates basic EPUB files exist
    /// - Parameter baseURL: The base directory to validate
    /// - Returns: Validation result with any issues found
    func validateBasicEPUBFiles(at baseURL: URL) -> EPUBStructureValidation {
        var issues: [String] = []

        // Check for container.xml
        let containerXML = baseURL.appendingPathComponent("META-INF/container.xml")
        if !validateContainerXML(at: containerXML) {
            issues.append("Missing or unreadable META-INF/container.xml")
        }

        // Check for mimetype file (optional in some EPUBs)
        let mimetypeFile = baseURL.appendingPathComponent("mimetype")
        if !fileManager.fileExists(atPath: mimetypeFile.path) {
            // This is a warning, not an error - some EPUBs work without mimetype
        }

        return EPUBStructureValidation(
            isValid: issues.isEmpty,
            issues: issues
        )
    }
}

// MARK: - Supporting Types

/// Result of EPUB structure validation
internal struct EPUBStructureValidation {
    let isValid: Bool
    let issues: [String]

    var description: String {
        if isValid {
            return "EPUB structure is valid"
        } else {
            return "EPUB structure issues: \(issues.joined(separator: ", "))"
        }
    }
}
