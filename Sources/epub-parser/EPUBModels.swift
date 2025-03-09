import Foundation

/// A simple model to represent an EPUB chapter
public struct EPUBChapterInfo: Identifiable, Hashable {
    public let id: String
    public let title: String
    public let contentPath: String
    public let playOrder: Int

    public func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    public static func == (lhs: EPUBChapterInfo, rhs: EPUBChapterInfo) -> Bool {
        lhs.id == rhs.id
    }
}

extension Array: @retroactive Identifiable where Element == EPUBChapterInfo {
    public var id: String {
        self.map { $0.id }.joined(separator: ",")
    }
}

/// A struct to represent the content of a chapter, including HTML and title
public struct EPUBChapterContent {
    public let html: String
    public let info: EPUBChapterInfo
}
