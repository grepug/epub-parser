import Foundation

/// Errors that can occur during EPUB parsing
public enum EPUBParserError: LocalizedError {
    case contentOPFNotFound
    case tocNCXNotFound
    case chapterNotFound(id: String)
    case htmlPathResolutionFailed
    case opfParsingFailed
    case tocNCXPathNotFound
    case ncxParsingFailed
    case ncxParseError
    case opfParseError
    case missingContainerXML
    case invalidEPUBStructure(String)
    case invalidUnzippedPath(String)
    case cacheNotFound

    public var errorDescription: String? {
        switch self {
        case .contentOPFNotFound:
            return "Failed to find content.opf path"
        case .tocNCXNotFound:
            return "TOC file not found"
        case .chapterNotFound(let id):
            return "Could not find chapter with id \(id)"
        case .htmlPathResolutionFailed:
            return "Could not resolve HTML path"
        case .opfParsingFailed:
            return "Failed to create parser for OPF"
        case .tocNCXPathNotFound:
            return "Could not find toc.ncx path"
        case .ncxParsingFailed:
            return "Failed to create parser for NCX"
        case .ncxParseError:
            return "Failed to parse NCX file"
        case .opfParseError:
            return "Failed to parse OPF file"
        case .missingContainerXML:
            return "Missing or unreadable container.xml file"
        case .invalidEPUBStructure(let description):
            return "Invalid EPUB structure: \(description)"
        case .invalidUnzippedPath(let reason):
            return "Invalid unzipped EPUB path: \(reason)"
        case .cacheNotFound:
            return "Cache file not found. Pre-unzipped EPUB directory must contain .epub_cache.json file"
        }
    }
}
