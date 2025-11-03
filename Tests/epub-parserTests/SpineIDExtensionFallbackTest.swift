import Foundation
import Testing

@testable import EPUBParser

struct SpineIDExtensionFallbackTest {

    @Test("Debug the HTML extension fallback logic")
    func testHTMLExtensionFallback() async throws {
        // Find a test EPUB file
        guard let epubURL = TestConfiguration.findTestEPUBFile() else {
            Issue.record("No test EPUB file found. Please add an EPUB file to the configured test directories.")
            return
        }

        // Create a destination URL for this test
        let destinationURL = TestConfiguration.testDestinationURL(for: "extension_fallback")

        // Initialize and process
        let parser = EPUBParser(
            epubPath: epubURL,
            destinationURL: destinationURL,
            skipUnzipIfDirectoryExists: true,
            cleanup: false
        )

        let document = try await parser.processEPUB()
        
        print("\n=== HTML EXTENSION FALLBACK DEBUG ===")
        
        if let firstSpineItem = document.spineItems.first {
            let originalPath = firstSpineItem.manifestItem.path
            print("Original path: '\(originalPath)'")
            
            // Test the .html version
            let htmlPath = String(originalPath.dropLast(6)) + ".html"  // .xhtml -> .html
            print("Testing HTML path: '\(htmlPath)'")
            
            // Debug the path processing step by step
            print("\nDebugging spineItemId lookup for '\(htmlPath)':")
            
            // Step 1: Check for direct match
            print("Step 1: Checking direct matches...")
            for (index, spineItem) in document.spineItems.enumerated() {
                let manifestPath = spineItem.manifestItem.path
                if manifestPath == htmlPath {
                    print("  Direct match found at index \(index): '\(manifestPath)'")
                    break
                }
            }
            
            // Step 2: Check filename matches
            print("Step 2: Checking filename matches...")
            let targetFileName = URL(fileURLWithPath: htmlPath).lastPathComponent
            print("  Target filename: '\(targetFileName)'")
            
            for (index, spineItem) in document.spineItems.enumerated() {
                let manifestPath = spineItem.manifestItem.path
                let manifestFileName = URL(fileURLWithPath: manifestPath).lastPathComponent
                if manifestFileName == targetFileName {
                    print("  Filename match found at index \(index): '\(manifestFileName)' vs '\(targetFileName)'")
                    break
                }
            }
            
            // Step 3: Check HTML extension fallback
            print("Step 3: Checking HTML extension fallback...")
            let basePath = URL(fileURLWithPath: htmlPath).deletingPathExtension().path
            print("  Base path: '\(basePath)'")
            
            let htmlExtensions = ["html", "xhtml", "htm"]
            for ext in htmlExtensions {
                let testPath = basePath + "." + ext
                print("  Testing extension '\(ext)': '\(testPath)'")
                
                for (index, spineItem) in document.spineItems.enumerated() {
                    if spineItem.manifestItem.path == testPath {
                        print("    ✅ Match found at index \(index): '\(spineItem.manifestItem.path)'")
                        print("    Should return idref: '\(spineItem.id)'")
                        break
                    }
                }
            }
            
            // Test the actual method call
            let result = document.spineItemId(for: htmlPath)
            print("\nActual method result: '\(result ?? "nil")'")
            
            if result == nil {
                print("❌ Method failed - debugging why...")
                
                // Let's manually trace through the logic
                print("\nManual trace:")
                
                // Remove fragment part if present
                let pathWithoutFragment: String
                if let hashIndex = htmlPath.firstIndex(of: "#") {
                    pathWithoutFragment = String(htmlPath[..<hashIndex])
                } else {
                    pathWithoutFragment = htmlPath
                }
                print("  pathWithoutFragment: '\(pathWithoutFragment)'")
                
                // Handle absolute URLs
                let targetPath: String
                if let url = URL(string: pathWithoutFragment), url.scheme != nil {
                    print("  URL has scheme: \(url.scheme!)")
                    targetPath = url.lastPathComponent
                } else {
                    targetPath = pathWithoutFragment
                }
                print("  targetPath: '\(targetPath)'")
                
                // Normalize path
                let normalizedPath = targetPath.hasPrefix("/") ? String(targetPath.dropFirst()) : targetPath
                print("  normalizedPath: '\(normalizedPath)'")
                
                // Check if it should hit the extension fallback
                let shouldTryFallback = normalizedPath.hasSuffix(".html") || normalizedPath.hasSuffix(".xhtml") || normalizedPath.hasSuffix(".htm")
                print("  shouldTryFallback: \(shouldTryFallback)")
                
                if shouldTryFallback {
                    let fallbackBasePath = URL(fileURLWithPath: normalizedPath).deletingPathExtension().path
                    print("  fallbackBasePath: '\(fallbackBasePath)'")
                    
                    for ext in htmlExtensions {
                        let fallbackTestPath = fallbackBasePath + "." + ext
                        print("  fallbackTestPath: '\(fallbackTestPath)'")
                        
                        for (index, spineItem) in document.spineItems.prefix(3).enumerated() {
                            let spinePath = spineItem.manifestItem.path
                            print("    Comparing '\(fallbackTestPath)' with spine[\(index)]: '\(spinePath)'")
                            if spinePath == fallbackTestPath {
                                print("    🎯 MATCH FOUND! Should return: '\(spineItem.id)'")
                            }
                        }
                    }
                }
            }
        }
        
        print("\n=== END EXTENSION FALLBACK DEBUG ===\n")
        
        // Cleanup
        try? FileManager.default.removeItem(at: destinationURL)
    }
}