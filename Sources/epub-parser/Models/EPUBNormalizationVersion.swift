import Foundation

/// HTML normalization version for EPUB content processing
public enum EPUBNormalizationVersion: Int, Codable, Sendable, Hashable {
    /// Version 1: Remove excessive newlines (3+ → 2), trim trailing whitespace
    /// Does NOT remove inline line breaks within element content
    case v1 = 1
    
    /// Version 2: Remove inline line breaks within HTML elements
    /// Converts multi-line paragraph content to single lines
    case v2 = 2
    
    /// Current recommended version
    public static let current: EPUBNormalizationVersion = .v2

    public static func withNumber(_ number: Int?) -> EPUBNormalizationVersion {
        // defaults to v1 if nil, because the database didn't store version previously
        guard let number else {
            return .v1
        }

        return EPUBNormalizationVersion(rawValue: number) ?? .current
    }

    public var folderName: String {
        "v\(rawValue)"
    }
}
