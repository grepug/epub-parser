import Foundation

/// A model to represent an EPUB chapter with its content
public struct EPUBChapter: Identifiable, Hashable, Sendable {
    public let id: String
    public let title: String
    public let playOrder: Int
    /// The source path of the chapter in the EPUB
    public let path: String
    /// All manifest items associated with this chapter
    public var manifestItems: [EPUBManifestItem]

    /// Initialize a complete chapter with manifest items
    public init(id: String, title: String, playOrder: Int, path: String, manifestItems: [EPUBManifestItem] = []) {
        self.id = id
        self.title = title
        self.playOrder = playOrder
        self.path = path
        self.manifestItems = manifestItems
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    public static func == (lhs: EPUBChapter, rhs: EPUBChapter) -> Bool {
        lhs.id == rhs.id
    }
}

extension Array: @retroactive Identifiable where Element == EPUBChapter {
    public var id: String {
        self.map { $0.id }.joined(separator: ",")
    }
}
