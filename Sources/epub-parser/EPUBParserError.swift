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
        }
    }
}
