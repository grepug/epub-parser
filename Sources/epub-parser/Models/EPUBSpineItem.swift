import Foundation

/// Represents an item in the EPUB spine (reading order)
public struct EPUBSpineItem: Identifiable, Hashable, Sendable, Codable {
    /// EPUB manifest item identifier (from OPF file)
    public let id: String

    /// Sequential index in the spine (0-based)
    public let index: Int

    /// Whether this item is part of the linear reading order
    public let linear: Bool

    /// The associated manifest item containing the actual content reference
    public let manifestItem: EPUBManifestItem

    /// Initialize a spine item
    public init(id: String, index: Int, linear: Bool, manifestItem: EPUBManifestItem) {
        self.id = id
        self.index = index
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
