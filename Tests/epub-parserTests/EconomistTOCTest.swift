import Foundation
import Testing

@testable import EPUBParser

struct EconomistTOCTest {
    
    @Test("Examine The Economist TOC structure")
    func testEconomistTOC() async throws {
        let epubPath = "/Users/kai/Downloads/epub/TheEconomist.2025.11.01.epub"
        let epubURL = URL(fileURLWithPath: epubPath)
        
        guard FileManager.default.fileExists(atPath: epubURL.path) else {
            Issue.record("The Economist EPUB file not found at: \(epubPath)")
            return
        }
        
        let destinationURL = TestConfiguration.testDestinationURL(for: "economist_toc_test")
        
        print("\n" + String(repeating: "=", count: 80))
        print("🔍 EXAMINING THE ECONOMIST TOC STRUCTURE")
        print(String(repeating: "=", count: 80))
        
        // Parse the EPUB
        let document = try await EPUBParser.parse(
            destinationURL: destinationURL,
            epubSourceURL: epubURL,
            cleanup: false
        )
        
        // Print metadata
        print("\n📚 METADATA:")
        print("  Title: \(document.metadata.title ?? "N/A")")
        print("  Publisher: \(document.metadata.publisher ?? "N/A")")
        print("  Language: \(document.metadata.language ?? "N/A")")
        
        // Print manifest summary
        print("\n📦 MANIFEST:")
        print("  Total items: \(document.manifest.count)")
        let htmlItems = document.manifest.filter { $0.mediaType.contains("html") || $0.path.hasSuffix(".html") || $0.path.hasSuffix(".xhtml") }
        print("  HTML items: \(htmlItems.count)")
        
        // Print spine summary
        print("\n📖 SPINE (Reading Order):")
        print("  Total spine items: \(document.spineItems.count)")
        print("  First 5 spine items:")
        for (index, spineItem) in document.spineItems.prefix(5).enumerated() {
            print("    [\(index)] \(spineItem.manifestItem.path)")
        }
        
        // Print TOC structure
        print("\n📑 TABLE OF CONTENTS:")
        print("  Total TOC items: \(document.tableOfContents.count)")
        
        if document.tableOfContents.isEmpty {
            print("  ⚠️ WARNING: No TOC items found!")
            
            // Let's examine the raw TOC file
            print("\n🔍 Examining TOC file location...")
            
            // Look for toc.ncx or navigation document
            let tocNCX = document.manifest.first { $0.id.lowercased().contains("toc") || $0.path.lowercased().contains("toc.ncx") }
            let navDoc = document.manifest.first { $0.properties["properties"]?.contains("nav") == true }
            
            if let tocItem = tocNCX ?? navDoc {
                print("  Found TOC file: \(tocItem.path)")
                let tocURL = document.baseURL.appendingPathComponent(tocItem.path)
                
                if FileManager.default.fileExists(atPath: tocURL.path) {
                    do {
                        let tocContent = try String(contentsOf: tocURL, encoding: .utf8)
                        print("\n📄 TOC File Content (first 2000 characters):")
                        print(String(tocContent.prefix(2000)))
                        
                        // Analyze the content
                        if tocContent.contains("<navPoint") {
                            print("\n  ✓ This is an NCX file (EPUB2 format)")
                            let navPointCount = tocContent.components(separatedBy: "<navPoint").count - 1
                            print("  Found \(navPointCount) navPoint elements")
                        } else if tocContent.contains("<nav") {
                            print("\n  ✓ This is a navigation document (EPUB3 format)")
                            let navCount = tocContent.components(separatedBy: "<nav").count - 1
                            print("  Found \(navCount) nav elements")
                        }
                    } catch {
                        print("  ❌ Error reading TOC file: \(error)")
                    }
                } else {
                    print("  ❌ TOC file not found at: \(tocURL.path)")
                }
            } else {
                print("  ❌ No TOC file found in manifest")
                
                // Print all manifest items to help debug
                print("\n📋 All manifest items:")
                for (index, item) in document.manifest.enumerated() {
                    print("    [\(index)] ID: \(item.id), Path: \(item.path), Type: \(item.mediaType)")
                    if !item.properties.isEmpty {
                        print("         Properties: \(item.properties)")
                    }
                }
            }
        } else {
            print("\n  TOC Structure:")
            printTOCItems(document.tableOfContents, level: 0)
            
            // Validate TOC items
            print("\n🔍 Validating TOC items:")
            var validCount = 0
            var invalidCount = 0
            
            for tocItem in document.flattenedTableOfContents {
                // Check if the href exists in spine
                let spineItemId = document.spineItemId(for: tocItem.href)
                if spineItemId != nil {
                    validCount += 1
                } else {
                    invalidCount += 1
                    print("  ⚠️ Invalid TOC item: \(tocItem.title)")
                    print("     HREF: \(tocItem.href)")
                    print("     Not found in spine")
                }
            }
            
            print("\n  Valid TOC items: \(validCount)")
            print("  Invalid TOC items: \(invalidCount)")
        }
        
        // Check for line breaks in HTML content
        print("\n📝 Checking HTML content normalization:")
        var filesWithLineBreaks = 0
        var filesChecked = 0
        
        for spineItem in document.spineItems.prefix(5) {
            let fileURL = document.baseURL.appendingPathComponent(spineItem.manifestItem.path)
            
            guard FileManager.default.fileExists(atPath: fileURL.path) else {
                continue
            }
            
            do {
                let htmlContent = try String(contentsOf: fileURL, encoding: .utf8)
                filesChecked += 1
                
                // Check for line breaks in paragraphs
                if let regex = try? NSRegularExpression(pattern: "<p[^>]*>(.*?)</p>", options: [.caseInsensitive, .dotMatchesLineSeparators]) {
                    let range = NSRange(htmlContent.startIndex..., in: htmlContent)
                    let matches = regex.matches(in: htmlContent, options: [], range: range)
                    
                    for match in matches.prefix(3) {
                        if let contentRange = Range(match.range(at: 1), in: htmlContent) {
                            let paragraphContent = String(htmlContent[contentRange])
                            
                            if paragraphContent.contains("\n") {
                                filesWithLineBreaks += 1
                                print("  ⚠️ Found line breaks in: \(spineItem.manifestItem.path)")
                                print("     Sample: \(paragraphContent.prefix(100))...")
                                break
                            }
                        }
                    }
                }
            } catch {
                continue
            }
        }
        
        print("\n  Files checked: \(filesChecked)")
        print("  Files with line breaks in paragraphs: \(filesWithLineBreaks)")
        
        print("\n" + String(repeating: "=", count: 80))
        
        // Cleanup
        try? FileManager.default.removeItem(at: destinationURL)
    }
    
    // Helper function to print TOC items recursively
    private func printTOCItems(_ items: [EPUBTOCItem], level: Int) {
        let indent = String(repeating: "  ", count: level + 1)
        for item in items {
            print("\(indent)- \(item.title)")
            print("\(indent)  HREF: \(item.href)")
            print("\(indent)  Play Order: \(item.playOrder)")
            
            if let children = item.children, !children.isEmpty {
                printTOCItems(children, level: level + 1)
            }
        }
    }
}
