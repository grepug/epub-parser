import Foundation

/// Represents metadata for an EPUB document
public struct EPUBMetadata: Hashable, Sendable, Codable {
    // MARK: - Core Metadata

    /// Title of the publication
    public let title: String?

    /// Creator/Author(s) of the publication
    public let creators: [String]

    /// Contributor(s) to the publication
    public let contributors: [String]

    /// Language of the publication (e.g., "en", "en-US")
    public let language: String?

    /// Unique identifier for the publication (usually ISBN or UUID)
    public let identifier: String?

    /// Publisher of the publication
    public let publisher: String?

    /// Publication date
    public let date: String?

    /// Description or summary of the publication
    public let description: String?

    /// Subject matter or keywords
    public let subjects: [String]

    /// Rights information (copyright, etc.)
    public let rights: String?

    /// Type of publication
    public let type: String?

    /// Source from which this publication is derived
    public let source: String?

    /// Coverage (spatial or temporal)
    public let coverage: String?

    /// Cover image absolute URL
    public let coverImageURL: URL?

    /// Any additional metadata not captured above
    public let additionalMetadata: [String: String]

    /// Initialize metadata
    public init(
        title: String? = nil,
        creators: [String] = [],
        contributors: [String] = [],
        language: String? = nil,
        identifier: String? = nil,
        publisher: String? = nil,
        date: String? = nil,
        description: String? = nil,
        subjects: [String] = [],
        rights: String? = nil,
        type: String? = nil,
        source: String? = nil,
        coverage: String? = nil,
        coverImageURL: URL? = nil,
        additionalMetadata: [String: String] = [:]
    ) {
        self.title = title
        self.creators = creators
        self.contributors = contributors
        self.language = language
        self.identifier = identifier
        self.publisher = publisher
        self.date = date
        self.description = description
        self.subjects = subjects
        self.rights = rights
        self.type = type
        self.source = source
        self.coverage = coverage
        self.coverImageURL = coverImageURL
        self.additionalMetadata = additionalMetadata
    }
}

extension EPUBMetadata {
    /// Get the primary creator/author
    public var primaryCreator: String? {
        creators.first
    }

    /// Get all creators as a single formatted string
    public var creatorsString: String {
        creators.joined(separator: ", ")
    }

    /// Get all contributors as a single formatted string
    public var contributorsString: String {
        contributors.joined(separator: ", ")
    }

    /// Get all subjects as a single formatted string
    public var subjectsString: String {
        subjects.joined(separator: ", ")
    }
}
