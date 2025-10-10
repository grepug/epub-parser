import Foundation

/// Represents an item in the EPUB spine (reading order)
public struct EPUBSpineItem: Identifiable, Hashable, Sendable, Codable {
    /// Unique identifier for this spine item
    public let id: String

    /// Reference to the manifest item ID
    public let idref: String

    /// Whether this item is part of the linear reading order
    public let linear: Bool

    /// The associated manifest item containing the actual content reference
    public let manifestItem: EPUBManifestItem

    /// Initialize a spine item
    public init(id: String, idref: String, linear: Bool, manifestItem: EPUBManifestItem) {
        self.id = id
        self.idref = idref
        self.linear = linear
        self.manifestItem = manifestItem
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    public static func == (lhs: EPUBSpineItem, rhs: EPUBSpineItem) -> Bool {
        lhs.id == rhs.id
    }
}
