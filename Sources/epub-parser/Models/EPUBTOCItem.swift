import Foundation

/// Represents an item in the EPUB table of contents (hierarchical navigation)
public struct EPUBTOCItem: Identifiable, Hashable, Sendable, Codable {
    /// Unique identifier for this TOC item
    public let id: String

    /// The display title for this TOC entry
    public let title: String

    /// Play order (for sequential reading)
    public let playOrder: Int

    /// The full href including any fragment identifier (e.g., "chapter1.html#section2")
    public let href: String

    /// The base file path without fragment (e.g., "chapter1.html")
    public var filePath: String {
        href.components(separatedBy: "#").first ?? href
    }

    /// The fragment identifier if present (e.g., "section2" from "chapter1.html#section2")
    public var fragment: String? {
        let components = href.components(separatedBy: "#")
        return components.count > 1 ? components[1] : nil
    }

    /// Child TOC items for hierarchical structure (e.g., subsections)
    public var children: [EPUBTOCItem]?

    /// Initialize a TOC item
    public init(id: String, title: String, playOrder: Int, href: String, children: [EPUBTOCItem] = []) {
        self.id = id
        self.title = title
        self.playOrder = playOrder
        self.href = href
        self.children = children
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    public static func == (lhs: EPUBTOCItem, rhs: EPUBTOCItem) -> Bool {
        lhs.id == rhs.id
    }
}

extension EPUBTOCItem {
    /// Flatten the hierarchical TOC structure into a linear array
    public func flattened() -> [EPUBTOCItem] {
        var result = [self]
        for child in children ?? [] {
            result.append(contentsOf: child.flattened())
        }
        return result
    }

    /// Get all flattened TOC items from an array
    public static func flattenAll(_ items: [EPUBTOCItem]) -> [EPUBTOCItem] {
        items.flatMap { $0.flattened() }
    }
}
