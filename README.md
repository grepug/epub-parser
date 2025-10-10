# EPUBParser

[![Swift Version](https://img.shields.io/badge/Swift-6.0-orange.svg)](https://swift.org)
[![Platforms](https://img.shields.io/badge/Platforms-macOS%2013+%20|%20iOS%2016+-blue.svg)](https://swift.org)
[![License](https://img.shields.io/badge/License-MIT-green.svg)](LICENSE)

## Features

- ✅ **Document-Centric Design**: Direct access to EPUB components (metadata, spine, TOC, manifest)
- 📚 **EPUB 2 & 3 Support**: Handles both NCX (EPUB 2) and Navigation Document (EPUB 3) formats
- � **Flexible Initialization**: Parse from `.epub` files or pre-unzipped directories
- �🔄 **Actor-Based Concurrency**: Thread-safe parsing with Swift's modern concurrency model
- 🌲 **Hierarchical TOC**: Preserves nested table of contents structure
- 📖 **Reading Order**: Access spine items with linear/non-linear distinction
- 🎯 **Fragment Support**: Proper handling of URL fragments in TOC items
- 🚀 **High Performance**: Concurrent processing of multiple EPUB files
- ✨ **100% Swift**: No dependencies on legacy Objective-C libraries
- 🧪 **Thoroughly Tested**: Validated against 29+ real-world EPUB files

## Installation

### Swift Package Manager

Add this to your `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/grepug/epub-parser.git", from: "1.0.0")
]
```

Or add it directly in Xcode:

1. File → Add Package Dependencies
2. Enter the repository URL: `https://github.com/grepug/epub-parser.git`

## Quick Start

### From EPUB File

```swift
import EPUBParser

// Initialize the parser
let epubURL = URL(fileURLWithPath: "/path/to/book.epub")
let parser = EPUBParser(
    epubPath: epubURL,
    identifier: "my-reader",
    cacheDirectory: FileManager.default.temporaryDirectory,
    cleanup: false  // Set to true to auto-cleanup in deinit
)

// Process the EPUB
let document = try await parser.processEPUB()

// Access metadata
print("Title: \(document.metadata.title)")
print("Author: \(document.metadata.primaryCreator ?? "Unknown")")
print("Language: \(document.metadata.language ?? "Unknown")")

// Manual cleanup (optional if cleanup: true was set)
parser.cleanup()
```

### From Pre-Unzipped Directory

If you already have an unzipped EPUB directory, you can initialize the parser directly:

```swift
import EPUBParser

// Initialize with pre-unzipped directory
let unzippedEPUBPath = URL(fileURLWithPath: "/path/to/unzipped/epub")

// This will validate that the directory contains required EPUB files
let parser = try EPUBParser(
    unzippedPath: unzippedEPUBPath,
    cleanup: false  // Set to true if you want to delete the directory on deinit
)

// Process the EPUB (no unzipping needed!)
let document = try await parser.processEPUB()

// By default, pre-unzipped directories are not deleted on cleanup
// unless you set cleanup: true in the initializer
parser.cleanup()
```

### Working with EPUB Content

```swift
print("Title: \(document.metadata.title)")
print("Author: \(document.metadata.primaryCreator ?? "Unknown")")
print("Language: \(document.metadata.language ?? "Unknown")")

// Access cover image (absolute URL ready to use)
if let coverURL = document.metadata.coverImageURL {
    let coverImage = UIImage(contentsOfFile: coverURL.path) // iOS
    // or NSImage(contentsOf: coverURL) for macOS
}

// Access table of contents for navigation
for tocItem in document.tableOfContents {
    print("📖 \(tocItem.title) -> \(tocItem.href)")

    // Get absolute URL for TOC item
    let absoluteURL = document.url(for: tocItem)

    // Access nested chapters
    for child in tocItem.children {
        print("  📄 \(child.title) -> \(child.href)")
    }
}

// Access spine for reading order
for (index, spineItem) in document.spine.enumerated() {
    if spineItem.linear {
        print("\(index + 1). \(spineItem.manifestItem.path)")

        // Get absolute URL for manifest item
        let htmlURL = document.url(for: spineItem.manifestItem)
    }
}

// Load HTML content
if let firstSpineItem = document.spine.first {
    let htmlURL = document.url(for: firstSpineItem.manifestItem)
    let htmlContent = try String(contentsOf: htmlURL, encoding: .utf8)
    // Display htmlContent in your reader...
}

// Clean up when done
parser.cleanup()
```

## Core Components

### EPUBDocument

The main container representing a parsed EPUB file:

```swift
public struct EPUBDocument {
    public let metadata: EPUBMetadata        // Book information
    public let manifest: [EPUBManifestItem]  // All resources
    public let spine: [EPUBSpineItem]        // Reading order
    public let tableOfContents: [EPUBTOCItem] // Navigation structure
    public let baseURL: URL                  // Base path for resources
}
```

### EPUBMetadata

Complete Dublin Core metadata:

```swift
public struct EPUBMetadata {
    public let title: String
    public let creators: [String]            // Authors
    public let language: String?
    public let identifier: String?
    public let publisher: String?
    public let date: String?
    public let bookDescription: String?
    public let subjects: [String]
    public let rights: String?
    // ... and more

    public var primaryCreator: String?       // First author
    public var creatorsString: String        // Comma-separated authors
}
```

### EPUBSpineItem

Represents reading order:

```swift
public struct EPUBSpineItem {
    public let id: String
    public let idref: String
    public let linear: Bool                  // Include in sequential reading?
    public let manifestItem: EPUBManifestItem
}
```

### EPUBTOCItem

Hierarchical table of contents:

```swift
public struct EPUBTOCItem {
    public let id: String
    public let title: String
    public let href: String                  // e.g., "chapter1.html#section2"
    public let children: [EPUBTOCItem]       // Nested items

    public var fragment: String?             // "#section2"
    public var filePath: String              // "chapter1.html"
}
```

### EPUBManifestItem

Resource metadata:

```swift
public struct EPUBManifestItem {
    public let id: String
    public let path: String                  // Relative path
    public let mediaType: String             // MIME type
}
```

## Advanced Usage

### Building a Reader UI

```swift
class EPUBReaderViewController {
    var document: EPUBDocument?

    func loadEPUB(url: URL) async throws {
        let parser = EPUBParser(
            epubPath: url,
            identifier: UUID().uuidString,
            cacheDirectory: cacheDirectory
        )

        self.document = try await parser.processEPUB()

        // Populate table of contents view
        updateTOCView()

        // Load first chapter
        if let firstSpine = document?.spine.first {
            loadChapter(spineItem: firstSpine)
        }
    }

    func updateTOCView() {
        guard let toc = document?.tableOfContents else { return }

        // Use hierarchical TOC
        for item in toc {
            addTOCSection(item, level: 0)
        }

        // Or use flattened list
        let flatTOC = document?.flattenedTableOfContents
        for item in flatTOC {
            addTOCItem(item)
        }
    }

    func loadChapter(spineItem: EPUBSpineItem) {
        guard let document = document else { return }

        let htmlURL = document.url(for: spineItem.manifestItem)

        // Load in WKWebView or your custom renderer
        webView.loadFileURL(htmlURL, allowingReadAccessTo: document.baseURL)
    }

    func navigateToTOCItem(_ tocItem: EPUBTOCItem) {
        guard let document = document else { return }

        let htmlURL = document.url(for: tocItem)

        // Load with fragment if present
        if let fragment = tocItem.fragment {
            // Scroll to anchor after page load
            webView.load(URLRequest(url: htmlURL))
            // Then: webView.evaluateJavaScript("window.location.hash = '\(fragment)'")
        } else {
            webView.loadFileURL(htmlURL, allowingReadAccessTo: document.baseURL)
        }
    }
}
```

### SwiftUI EPUB Reader Example

```swift
import SwiftUI
import WebKit

struct EPUBReaderView: View {
    @State private var document: EPUBDocument?
    @State private var currentSpineIndex = 0
    @State private var showTOC = false

    var body: some View {
        NavigationView {
            if let doc = document {
                VStack {
                    // Cover image (if available)
                    if let coverURL = doc.metadata.coverImageURL {
                        AsyncImage(url: coverURL) { image in
                            image.resizable().aspectRatio(contentMode: .fit)
                        } placeholder: {
                            ProgressView()
                        }
                        .frame(height: 200)
                    }

                    // Chapter content
                    HTMLView(url: doc.url(for: doc.spine[currentSpineIndex].manifestItem))

                    // Navigation buttons
                    HStack {
                        Button("Previous") { currentSpineIndex = max(0, currentSpineIndex - 1) }
                            .disabled(currentSpineIndex == 0)
                        Spacer()
                        Button("Next") { currentSpineIndex = min(doc.spine.count - 1, currentSpineIndex + 1) }
                            .disabled(currentSpineIndex == doc.spine.count - 1)
                    }
                    .padding()
                }
                .navigationTitle(doc.metadata.title)
                .toolbar {
                    Button("TOC") { showTOC.toggle() }
                }
                .sheet(isPresented: $showTOC) {
                    TOCView(items: doc.tableOfContents) { tocItem in
                        // Navigate to selected TOC item
                        if let spineIndex = doc.spine.firstIndex(where: { $0.manifestItem.path == tocItem.filePath }) {
                            currentSpineIndex = spineIndex
                            showTOC = false
                        }
                    }
                }
            }
        }
        .task {
            await loadEPUB()
        }
    }

    func loadEPUB() async {
        let parser = EPUBParser(/* ... */)
        document = try? await parser.processEPUB()
    }
}

struct HTMLView: UIViewRepresentable {
    let url: URL

    func makeUIView(context: Context) -> WKWebView {
        WKWebView()
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        webView.loadFileURL(url, allowingReadAccessTo: url.deletingLastPathComponent())
    }
}

struct TOCView: View {
    let items: [EPUBTOCItem]
    let onSelect: (EPUBTOCItem) -> Void

    var body: some View {
        List(items, id: \.id) { item in
            Button(action: { onSelect(item) }) {
                VStack(alignment: .leading) {
                    Text(item.title)
                    if !item.children.isEmpty {
                        TOCView(items: item.children, onSelect: onSelect)
                    }
                }
            }
        }
    }
}
```

### Concurrent Processing

```swift
// Process multiple EPUB files concurrently
let epubFiles: [URL] = // ... your EPUB file URLs

try await withThrowingTaskGroup(of: EPUBDocument.self) { group in
    for epubURL in epubFiles {
        group.addTask {
            let parser = EPUBParser(
                epubPath: epubURL,
                identifier: UUID().uuidString,
                cacheDirectory: cacheDirectory
            )
            defer { parser.cleanup() }
            return try await parser.processEPUB()
        }
    }

    var documents: [EPUBDocument] = []
    for try await document in group {
        documents.append(document)
        print("Loaded: \(document.metadata.title)")
    }
}
```

### Working with Manifest

```swift
// Get all HTML files
let htmlFiles = document.htmlManifestItems

// Access cover image (easiest way - already an absolute URL)
if let coverURL = document.metadata.coverImageURL {
    let image = UIImage(contentsOfFile: coverURL.path)
}

// Or find specific resource by ID
if let coverImage = document.manifestItem(withId: "cover-image") {
    let imageURL = document.url(for: coverImage)
    let image = UIImage(contentsOfFile: imageURL.path)
}

// Get all images
let images = document.manifest.filter { item in
    item.mediaType.hasPrefix("image/")
}
```

### Filter Linear Spine Items

```swift
// Only get items meant for sequential reading
let readingOrder = document.linearSpineItems

for spineItem in readingOrder {
    print(spineItem.manifestItem.path)
}
```

## Architecture

### Why Document-Centric?

Traditional EPUB parsers often pre-process content into custom chapter formats, which:

- ❌ Loses original EPUB structure
- ❌ Requires complex mapping logic
- ❌ Makes debugging harder
- ❌ Limits flexibility

This library takes a **document-centric approach**:

- ✅ Preserves EPUB structure as-is
- ✅ Direct access to spine, TOC, and manifest
- ✅ Simple, transparent API
- ✅ Perfect for building readers

### Thread Safety

`EPUBParser` uses Swift's `actor` model for thread-safe concurrent access:

```swift
public actor EPUBParser {
    // All methods are automatically serialized
    public func processEPUB() async throws -> EPUBDocument
    public func document() async -> EPUBDocument?
}
```

## Testing

The library includes comprehensive tests validated against 29 real-world EPUB files:

```bash
swift test
```

Test coverage includes:

- ✅ Document parsing and structure
- ✅ Metadata extraction (all Dublin Core fields)
- ✅ Spine structure and reading order
- ✅ Hierarchical TOC parsing (EPUB 2 NCX & EPUB 3 nav)
- ✅ Manifest item lookup and URL generation
- ✅ HTML content loading
- ✅ Concurrent processing
- ✅ Multiple file validation
- ✅ Both EPUB 2 and EPUB 3 formats

## Requirements

- Swift 6.0+
- macOS 13+ / iOS 16+

## Dependencies

- [ZIPFoundation](https://github.com/weichsel/ZIPFoundation) - ZIP archive extraction
- [SwiftSoup](https://github.com/scinfu/SwiftSoup) - HTML/XML parsing

## Roadmap

- [ ] Support for EPUB fixed-layout
- [ ] CSS stylesheet extraction and management
- [ ] Font extraction and embedding
- [ ] DRM detection and reporting
- [ ] EPUB validation utilities
- [ ] Improved error messages with recovery suggestions
- [ ] Progressive loading for large EPUBs

## Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

1. Fork the repository
2. Create your feature branch (`git checkout -b feature/amazing-feature`)
3. Commit your changes (`git commit -m 'Add some amazing feature'`)
4. Push to the branch (`git push origin feature/amazing-feature`)
5. Open a Pull Request

## License

This project is licensed under the MIT License - see the LICENSE file for details.

## Acknowledgments

- Inspired by the need for a modern, Swift-native EPUB parser
- Built with Swift's modern concurrency features
- Tested with books from various publishers and formats

## Author

Created by [grepug](https://github.com/grepug)

---

**Note**: This is a complete rewrite focusing on document-centric architecture rather than chapter-based extraction. If you're looking for the old chapter-based API, please see the `main` branch.
