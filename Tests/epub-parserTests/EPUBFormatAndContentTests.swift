import Foundation
import Testing

@testable import EPUBParser

/// EPUB format variations and content merging tests
struct EPUBFormatAndContentTests {

    @Test func testEPUBFormatVariations() async throws {
        let allEPUBFiles = TestConfiguration.findAllTestEPUBFiles()
        let validEPUBFiles = allEPUBFiles.filter { TestConfiguration.isValidEPUBFile($0) }

        guard validEPUBFiles.count >= 1 else {
            Issue.record("Need at least 1 valid EPUB file to test format variations")
            return
        }

        let testDir = try TestConfiguration.createTestDirectory()
        defer {
            try? FileManager.default.removeItem(at: testDir)
        }

        var epub2Count = 0
        var epub3Count = 0
        var formatResults: [(String, String)] = []

        for (index, epubFile) in validEPUBFiles.prefix(5).enumerated() {
            let fileName = epubFile.lastPathComponent

            let parser = EPUBParser(
                epubPath: epubFile,
                identifier: "format_test_\(index)",
                cacheDirectory: testDir
            )

            defer {
                parser.cleanup()
            }

            do {
                try await parser.processEPUB()

                // Try to determine EPUB version by checking the structure
                let tempEPUBDir = testDir.appendingPathComponent("epub_format_test_\(index)")

                let hasNCX = FileManager.default.fileExists(atPath: tempEPUBDir.appendingPathComponent("toc.ncx").path)
                let hasNavXHTML = FileManager.default.fileExists(atPath: tempEPUBDir.appendingPathComponent("nav.xhtml").path)

                var detectedFormat = "Unknown"

                if hasNavXHTML {
                    detectedFormat = "EPUB3 (nav.xhtml)"
                    epub3Count += 1
                } else if hasNCX {
                    detectedFormat = "EPUB2 (toc.ncx)"
                    epub2Count += 1
                } else {
                    // Check OPF for version information
                    do {
                        let opfFiles = try FileManager.default.contentsOfDirectory(at: tempEPUBDir, includingPropertiesForKeys: nil)
                            .filter { $0.pathExtension == "opf" }

                        if let opfFile = opfFiles.first {
                            let opfContent = try String(contentsOf: opfFile)
                            if opfContent.contains("version=\"3.0\"") {
                                detectedFormat = "EPUB3 (detected)"
                                epub3Count += 1
                            } else if opfContent.contains("version=\"2.0\"") {
                                detectedFormat = "EPUB2 (detected)"
                                epub2Count += 1
                            }
                        }
                    } catch {
                        print("    ⚠️ Could not analyze OPF for \(fileName)")
                    }
                }

                formatResults.append((fileName, detectedFormat))
                print("📚 \(fileName): \(detectedFormat)")

            } catch {
                formatResults.append((fileName, "Failed: \(String(describing: error))"))
                print("❌ \(fileName): Processing failed")
            }
        }

        print("\n📊 Format Analysis:")
        print("  • EPUB2 files: \(epub2Count)")
        print("  • EPUB3 files: \(epub3Count)")

        for (fileName, format) in formatResults {
            print("  • \(fileName): \(format)")
        }

        // Verify we can handle at least one format
        #expect(epub2Count + epub3Count > 0, "Should detect at least one valid EPUB format")

        print("✅ Format variation test completed")
    }

    @Test func testChapterContentMerging() async throws {
        // Test the HTML content merging capabilities for different chapter structures
        guard let testEPUBPath = TestConfiguration.findTestEPUBFile() else {
            Issue.record("No test EPUB file found for content merging test")
            return
        }

        let testDir = try TestConfiguration.createTestDirectory()
        defer {
            try? FileManager.default.removeItem(at: testDir)
        }

        let parser = EPUBParser(
            epubPath: testEPUBPath,
            identifier: "content_merging_test",
            cacheDirectory: testDir
        )

        defer {
            parser.cleanup()
        }

        try await parser.processEPUB()
        let chapters = await parser.chapters()

        guard !chapters.isEmpty else {
            Issue.record("No chapters found for content merging test")
            return
        }

        print("🧪 Testing Chapter Content Merging:")
        print("  📚 Total chapters: \(chapters.count)")

        // Test different merging strategies on the first few chapters
        for (index, chapter) in chapters.prefix(3).enumerated() {
            print("\n  📖 Chapter \(index + 1): '\(chapter.title)'")
            print("     Manifest items: \(chapter.manifestItems.count)")

            do {
                let baseURL = await parser.baseURL()

                // Test 1: Individual HTML retrieval
                let htmls = try chapter.htmls(baseURL: baseURL)
                #expect(!htmls.isEmpty, "Chapter should have at least one HTML content")
                print("     ✅ Individual HTMLs: \(htmls.count) files")

                // Test 2: Combined HTML (simple concatenation)
                let combinedHTML = try chapter.combinedHTML(baseURL: baseURL)
                #expect(!combinedHTML.isEmpty, "Combined HTML should not be empty")
                print("     ✅ Combined HTML: \(combinedHTML.count) characters")

                // Test 3: Merged HTML (body content merged into first document)
                let mergedHTML = try chapter.mergedHTML(baseURL: baseURL)
                #expect(!mergedHTML.isEmpty, "Merged HTML should not be empty")
                print("     ✅ Merged HTML: \(mergedHTML.count) characters")

                // Validate content structure
                if htmls.count > 1 {
                    print("     📝 Multi-file chapter detected!")
                    print("         - Individual files: \(htmls.count)")
                    print("         - Combined length: \(combinedHTML.count)")
                    print("         - Merged length: \(mergedHTML.count)")

                    // For multi-file chapters, merged HTML should be a proper HTML document
                    #expect(mergedHTML.contains("<html"), "Merged HTML should contain HTML tag")
                    #expect(mergedHTML.contains("<body"), "Merged HTML should contain body tag")
                    #expect(mergedHTML.contains("</body>"), "Merged HTML should have closing body tag")
                    #expect(mergedHTML.contains("</html>"), "Merged HTML should have closing HTML tag")

                    print("     ✅ HTML structure validation passed")
                } else {
                    print("     📄 Single-file chapter")
                    // For single-file chapters, combined and merged should be identical
                    #expect(combinedHTML == mergedHTML, "Single-file chapter: combined and merged HTML should be identical")
                }

                // Basic content validation
                let hasTextContent =
                    combinedHTML.range(of: #"<p[^>]*>.*?</p>"#, options: .regularExpression) != nil || combinedHTML.range(of: #"<div[^>]*>.*?</div>"#, options: .regularExpression) != nil

                if hasTextContent {
                    print("     ✅ Text content detected")
                } else {
                    print("     ⚠️  No obvious text content detected")
                }

                // Validate word count for content quality
                do {
                    let wordCount = try chapter.wordCount(baseURL: baseURL)
                    print("     📝 Word count: \(wordCount)")

                    if wordCount >= 100 {
                        print("     ✅ Sufficient content (≥100 words)")
                    } else {
                        print("     ⚠️  Limited content (<100 words)")
                        Issue.record("Chapter '\(chapter.title)' has only \(wordCount) words, expected at least 100")
                    }
                } catch {
                    print("     ❌ Word count failed: \(String(describing: error))")
                }

            } catch {
                Issue.record("Content merging failed for chapter '\(chapter.title)': \(error)")
                print("     ❌ Content merging failed: \(String(describing: error))")
            }
        }

        // Test edge cases with multi-file chapters
        let multiFileChapters = chapters.filter { $0.manifestItems.count > 1 }
        if !multiFileChapters.isEmpty {
            print("\n  🔗 Multi-file chapters found: \(multiFileChapters.count)")
            for chapter in multiFileChapters.prefix(2) {
                print("     • '\(chapter.title)': \(chapter.manifestItems.count) files")
                for (i, item) in chapter.manifestItems.enumerated() {
                    print("       [\(i+1)] \(item.path) (\(item.mediaType))")
                }
            }
        } else {
            print("\n  📄 All chapters are single-file chapters")
        }

        // Test chapters with fragment identifiers
        let fragmentChapters = chapters.filter { $0.path.contains("#") }
        if !fragmentChapters.isEmpty {
            print("\n  🔗 Fragment-based chapters found: \(fragmentChapters.count)")
            for chapter in fragmentChapters.prefix(3) {
                print("     • '\(chapter.title)': \(chapter.path)")
            }
        } else {
            print("\n  📄 No fragment-based chapters detected")
        }

        print("\n✅ Chapter content merging test completed successfully")
    }
}
