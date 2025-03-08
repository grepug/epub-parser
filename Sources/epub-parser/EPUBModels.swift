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

/// A struct to represent the content of a chapter, including HTML and title
public struct ChapterContent {
    public let html: String
    public let info: EPUBChapterInfo
}
