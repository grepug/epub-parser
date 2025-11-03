import Foundation
import Testing

@testable import EPUBParser

struct ChineseEPUBTest {

    @Test("Test Chinese EPUB parsing - 考研英语黄皮书")
    func testChineseEPUBParsing() async throws {
        let epubPath = "/Users/kai/Downloads/epub/考研英语黄皮书 2015.12~2016.5.epub"
        let epubURL = URL(fileURLWithPath: epubPath)

        guard FileManager.default.fileExists(atPath: epubURL.path) else {
            Issue.record("Chinese EPUB file not found at: \(epubPath)")
            return
        }

        let destinationURL = TestConfiguration.testDestinationURL(for: "chinese_epub_test")

        print("\n" + String(repeating: "=", count: 80))
        print("🔍 EXAMINING CHINESE EPUB STRUCTURE")
        print("File: 考研英语黄皮书 2015.12~2016.5.epub")
        print(String(repeating: "=", count: 80))

        do {
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
            print("  Creators: \(document.metadata.creators.joined(separator: ", "))")

            // Print manifest summary
            print("\n📦 MANIFEST:")
            print("  Total items: \(document.manifest.count)")
            let htmlItems = document.manifest.filter { $0.mediaType.contains("html") || $0.path.hasSuffix(".html") || $0.path.hasSuffix(".xhtml") }
            print("  HTML items: \(htmlItems.count)")
            let imageItems = document.manifest.filter { $0.mediaType.hasPrefix("image/") }
            print("  Image items: \(imageItems.count)")

            // Print spine summary
            print("\n📖 SPINE (Reading Order):")
            print("  Total spine items: \(document.spineItems.count)")
            print("  First 10 spine items:")
            for (index, spineItem) in document.spineItems.prefix(10).enumerated() {
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
                        } catch {
                            print("  ❌ Error reading TOC file: \(error)")
                        }
                    } else {
                        print("  ❌ TOC file not found at: \(tocURL.path)")
                    }
                } else {
                    print("  ❌ No TOC file found in manifest")
                }
            } else {
                print("\n  TOC Structure (first 20 items):")
                for (index, tocItem) in document.tableOfContents.prefix(20).enumerated() {
                    print("    [\(index)] \(tocItem.title)")
                    print("         HREF: \(tocItem.href)")
                    print("         Play Order: \(tocItem.playOrder)")
                }
            }

            // Check encoding and character issues
            print("\n🔍 Checking character encoding:")
            var chineseContentFound = false
            var encodingIssues = false

            for spineItem in document.spineItems.prefix(5) {
                let fileURL = document.baseURL.appendingPathComponent(spineItem.manifestItem.path)

                guard FileManager.default.fileExists(atPath: fileURL.path) else {
                    continue
                }

                do {
                    let htmlContent = try String(contentsOf: fileURL, encoding: .utf8)

                    // Check for Chinese characters
                    if htmlContent.range(of: "[\\u4e00-\\u9fff]", options: .regularExpression) != nil {
                        chineseContentFound = true
                        print("  ✓ Chinese characters found in: \(spineItem.manifestItem.path)")

                        // Show a sample
                        if let match = htmlContent.range(of: "[\\u4e00-\\u9fff]+", options: .regularExpression) {
                            let sample = String(htmlContent[match])
                            print("    Sample: \(sample)")
                        }
                    }

                    // Check for encoding issues (replacement characters)
                    if htmlContent.contains("�") {
                        encodingIssues = true
                        print("  ⚠️ Encoding issues found in: \(spineItem.manifestItem.path)")
                    }

                } catch {
                    print("  ❌ Error reading file \(spineItem.manifestItem.path): \(error)")
                }
            }

            print("\n  Chinese content found: \(chineseContentFound)")
            print("  Encoding issues: \(encodingIssues)")

            // Test basic functionality
            print("\n✅ SUCCESS: EPUB parsed successfully!")
            #expect(document.spineItems.count > 0, "Should have spine items")
            #expect(document.manifest.count > 0, "Should have manifest items")

        } catch {
            print("\n❌ PARSING FAILED!")
            print("Error: \(error)")

            // Let's try to understand why it failed
            print("\n🔍 Investigating failure...")

            // Check if it's a ZIP file
            do {
                let fileHandle = try FileHandle(forReadingFrom: epubURL)
                let header = fileHandle.readData(ofLength: 4)
                fileHandle.closeFile()

                let zipSignature = Data([0x50, 0x4B, 0x03, 0x04])  // "PK" ZIP signature
                let zipSignature2 = Data([0x50, 0x4B, 0x05, 0x06])  // Empty ZIP
                let zipSignature3 = Data([0x50, 0x4B, 0x07, 0x08])  // Spanned ZIP

                if header == zipSignature || header == zipSignature2 || header == zipSignature3 {
                    print("  ✓ File has valid ZIP signature")
                } else {
                    print("  ❌ File does not have valid ZIP signature")
                    print("  Header bytes: \(header.map { String(format: "%02X", $0) }.joined(separator: " "))")
                }
            } catch {
                print("  ❌ Cannot read file header: \(error)")
            }

            // Check file size
            do {
                let attributes = try FileManager.default.attributesOfItem(atPath: epubURL.path)
                let fileSize = attributes[.size] as? Int64 ?? 0
                print("  File size: \(fileSize) bytes")

                if fileSize == 0 {
                    print("  ❌ File is empty!")
                }
            } catch {
                print("  ❌ Cannot get file attributes: \(error)")
            }

            // Try to manually unzip and check structure
            print("\n🔧 Attempting manual extraction...")
            do {
                let tempUnzipDir = FileManager.default.temporaryDirectory.appendingPathComponent("manual_unzip_\(UUID().uuidString)")
                try FileManager.default.createDirectory(at: tempUnzipDir, withIntermediateDirectories: true)

                try FileManager.default.unzipItem(at: epubURL, to: tempUnzipDir)

                // Check for essential files
                let containerXML = tempUnzipDir.appendingPathComponent("META-INF/container.xml")
                let mimetypeFile = tempUnzipDir.appendingPathComponent("mimetype")

                print("  Container.xml exists: \(FileManager.default.fileExists(atPath: containerXML.path))")
                print("  Mimetype file exists: \(FileManager.default.fileExists(atPath: mimetypeFile.path))")

                if FileManager.default.fileExists(atPath: mimetypeFile.path) {
                    let mimetype = try String(contentsOf: mimetypeFile, encoding: .utf8)
                    print("  Mimetype content: '\(mimetype.trimmingCharacters(in: .whitespacesAndNewlines))'")
                }

                if FileManager.default.fileExists(atPath: containerXML.path) {
                    let containerContent = try String(contentsOf: containerXML, encoding: .utf8)
                    print("  Container.xml content (first 500 chars):")
                    print(String(containerContent.prefix(500)))
                }

                // Cleanup
                try? FileManager.default.removeItem(at: tempUnzipDir)

            } catch {
                print("  ❌ Manual extraction failed: \(error)")
            }

            // Re-throw the error for the test
            throw error
        }

        print("\n" + String(repeating: "=", count: 80))

        // Cleanup
        try? FileManager.default.removeItem(at: destinationURL)
    }
}
