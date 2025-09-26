import Foundation

/// Resolves EPUB directory structures, handling both standard and nested layouts
internal struct EPUBDirectoryResolver {
    private let fileManager: FileManager

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    /// Resolves the actual base directory and container.xml path for an EPUB
    /// - Parameter unzipDestination: The initial unzip destination
    /// - Returns: A tuple containing the resolved base URL and container.xml URL
    func resolveEPUBStructure(from unzipDestination: URL) -> EPUBStructureResult {
        let standardContainerXML = unzipDestination.appendingPathComponent("META-INF/container.xml")

        // First, try the standard EPUB structure
        if fileManager.fileExists(atPath: standardContainerXML.path) {
            return EPUBStructureResult(
                baseURL: unzipDestination,
                containerXMLURL: standardContainerXML,
                structureType: .standard
            )
        }

        // Handle nested directory structures
        if let nestedResult = findNestedEPUBStructure(in: unzipDestination) {
            return nestedResult
        }

        // Fallback to standard structure even if files don't exist (let caller handle the error)
        return EPUBStructureResult(
            baseURL: unzipDestination,
            containerXMLURL: standardContainerXML,
            structureType: .standard
        )
    }

    /// Finds OPF files in subdirectories when direct path lookup fails
    /// - Parameters:
    ///   - opfPath: The relative path to the OPF file from container.xml
    ///   - baseURL: The base URL to search from
    /// - Returns: The URL of the found OPF file, or nil if not found
    func findOPFInSubdirectories(opfPath: String, baseURL: URL) -> URL? {
        guard
            let enumerator = fileManager.enumerator(
                at: baseURL,
                includingPropertiesForKeys: [.isDirectoryKey]
            )
        else {
            return nil
        }

        for case let dirURL as URL in enumerator {
            guard let resourceValues = try? dirURL.resourceValues(forKeys: [.isDirectoryKey]),
                resourceValues.isDirectory == true
            else {
                continue
            }

            let candidateURL = dirURL.appendingPathComponent(opfPath)
            if fileManager.fileExists(atPath: candidateURL.path) {
                return candidateURL
            }
        }

        return nil
    }

    // MARK: - Private Methods

    private func findNestedEPUBStructure(in unzipDestination: URL) -> EPUBStructureResult? {
        do {
            let contents = try fileManager.contentsOfDirectory(atPath: unzipDestination.path)

            // Look for subdirectories that contain EPUB structure
            for item in contents {
                let itemURL = unzipDestination.appendingPathComponent(item)

                if isDirectory(itemURL),
                    let nestedContainerXML = findContainerXMLInDirectory(itemURL)
                {
                    return EPUBStructureResult(
                        baseURL: itemURL,
                        containerXMLURL: nestedContainerXML,
                        structureType: .nested(subdirectory: item)
                    )
                }
            }
        } catch {
            // Continue with fallback if directory listing fails
        }

        return nil
    }

    private func isDirectory(_ url: URL) -> Bool {
        var isDirectory: ObjCBool = false
        return fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory) && isDirectory.boolValue
    }

    private func findContainerXMLInDirectory(_ directoryURL: URL) -> URL? {
        let containerXML = directoryURL.appendingPathComponent("META-INF/container.xml")
        return fileManager.fileExists(atPath: containerXML.path) ? containerXML : nil
    }
}

// MARK: - Supporting Types

/// Result of EPUB structure resolution
internal struct EPUBStructureResult {
    let baseURL: URL
    let containerXMLURL: URL
    let structureType: EPUBStructureType
}

/// Types of EPUB directory structures
internal enum EPUBStructureType {
    case standard
    case nested(subdirectory: String)

    var description: String {
        switch self {
        case .standard:
            return "Standard EPUB structure"
        case .nested(let subdirectory):
            return "Nested EPUB structure (subdirectory: \(subdirectory))"
        }
    }
}
