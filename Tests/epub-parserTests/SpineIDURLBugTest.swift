import Foundation
import Testing

@testable import EPUBParser

struct SpineIDURLBugTest {

    @Test("Demonstrate the spine ID URL absoluteString bug")
    func testSpineIDURLAbsoluteStringBug() async throws {
        // Find a test EPUB file
        guard let epubURL = TestConfiguration.findTestEPUBFile() else {
            Issue.record("No test EPUB file found. Please add an EPUB file to the configured test directories.")
            return
        }

        // Create a destination URL for this test
        let destinationURL = TestConfiguration.testDestinationURL(for: "spine_id_url_bug")

        // Initialize and process
        let parser = EPUBParser(
            epubPath: epubURL,
            destinationURL: destinationURL,
            skipUnzipIfDirectoryExists: true,
            cleanup: false
        )

        let document = try await parser.processEPUB()
        
        print("\n=== SPINE ID URL ABSOLUTE STRING BUG TEST ===")
        
        // Test the bug with the first spine item
        guard let firstSpineItem = document.spine.first else {
            Issue.record("No spine items found in document")
            return
        }
        
        let manifestPath = firstSpineItem.manifestItem.path
        let expectedId = firstSpineItem.id
        
        print("Testing spine item:")
        print("  manifestPath: '\(manifestPath)'")
        print("  expectedId: '\(expectedId)'")
        
        // Test 1: String-based lookup (should work)
        let stringResult = document.spineItemId(for: manifestPath)
        print("  spineItemId(for: string) → '\(stringResult ?? "nil")'")
        
        // Test 2: URL-based lookup with relative URL (this is the bug)
        if let relativeURL = URL(string: manifestPath) {
            print("  Relative URL: '\(relativeURL)'")
            print("  Relative URL absoluteString: '\(relativeURL.absoluteString)'")
            
            let urlResult = document.spineItemId(for: relativeURL)
            print("  spineItemId(for: relativeURL) → '\(urlResult ?? "nil")'")
            
            // This will demonstrate the bug
            if stringResult != urlResult {
                print("  ❌ BUG DETECTED: String and URL results don't match!")
                print("     String result: '\(stringResult ?? "nil")'")
                print("     URL result: '\(urlResult ?? "nil")'")
                print("     The URL method is using absoluteString which creates absolute paths")
            }
        }
        
        // Test 3: URL-based lookup with file URL (also demonstrates the bug)
        let fileURL = URL(fileURLWithPath: manifestPath)
        print("  File URL: '\(fileURL)'")
        print("  File URL absoluteString: '\(fileURL.absoluteString)'")
        
        let fileURLResult = document.spineItemId(for: fileURL)
        print("  spineItemId(for: fileURL) → '\(fileURLResult ?? "nil")'")
        
        if stringResult != fileURLResult {
            print("  ❌ BUG DETECTED: String and file URL results don't match!")
            print("     String result: '\(stringResult ?? "nil")'")
            print("     File URL result: '\(fileURLResult ?? "nil")'")
            print("     The URL method is using absoluteString which creates file:// URLs")
        }
        
        // Show the correct behavior vs incorrect behavior
        print("\n=== BUG ANALYSIS ===")
        print("The spineItemId(for: URL) method calls url.absoluteString")
        print("This causes problems:")
        print("1. Relative URLs become absolute URLs")
        print("2. File URLs become file:// schemes")
        print("3. The absoluteString doesn't match the relative paths in spine items")
        
        // Demonstrate the correct fix
        print("\n=== CORRECT BEHAVIOR ===")
        if let relativeURL = URL(string: manifestPath) {
            // This is what the method should do instead of absoluteString:
            let correctPath = relativeURL.path
            print("Using url.path instead of absoluteString:")
            print("  url.path: '\(correctPath)'")
            
            // Test the string lookup with this corrected path
            let correctedResult = document.spineItemId(for: correctPath)
            print("  spineItemId(for: correctedPath) → '\(correctedResult ?? "nil")'")
        }
        
        print("\n=== END BUG TEST ===\n")
        
        // Test assertion - this shows the bug exists
        if let relativeURL = URL(string: manifestPath) {
            let urlResult = document.spineItemId(for: relativeURL)
            #expect(stringResult == urlResult, "String and URL lookups should return the same result, but they don't due to the absoluteString bug")
        }
        
        // Cleanup
        try? FileManager.default.removeItem(at: destinationURL)
    }
    
    @Test("Test the proposed fix for spine ID URL bug")
    func testSpineIDURLBugFix() async throws {
        // Find a test EPUB file
        guard let epubURL = TestConfiguration.findTestEPUBFile() else {
            Issue.record("No test EPUB file found. Please add an EPUB file to the configured test directories.")
            return
        }

        // Create a destination URL for this test
        let destinationURL = TestConfiguration.testDestinationURL(for: "spine_id_url_fix")

        // Initialize and process
        let parser = EPUBParser(
            epubPath: epubURL,
            destinationURL: destinationURL,
            skipUnzipIfDirectoryExists: true,
            cleanup: false
        )

        let document = try await parser.processEPUB()
        
        print("\n=== TESTING PROPOSED FIX ===")
        
        // Test multiple spine items
        for (index, spineItem) in document.spine.prefix(5).enumerated() {
            let manifestPath = spineItem.manifestItem.path
            let expectedId = spineItem.id
            
            print("[\(index)] Testing: '\(manifestPath)' → expected '\(expectedId)'")
            
            // Current string-based lookup (works)
            let stringResult = document.spineItemId(for: manifestPath)
            
            // Test different URL types
            if let relativeURL = URL(string: manifestPath) {
                // Current buggy implementation (using absoluteString)
                let buggyResult = document.spineItemId(for: relativeURL.absoluteString)
                
                // Proposed fix (using path or pathComponents)
                let fixedResult1 = document.spineItemId(for: relativeURL.path)
                
                // Another proposed fix (handle relative URLs properly)
                let fixedResult2: String?
                if relativeURL.scheme == nil {
                    // It's a relative URL, use the original string
                    fixedResult2 = document.spineItemId(for: manifestPath)
                } else {
                    // It's an absolute URL, extract the path
                    fixedResult2 = document.spineItemId(for: relativeURL.path)
                }
                
                print("    String lookup: '\(stringResult ?? "nil")'")
                print("    Buggy URL (absoluteString): '\(buggyResult ?? "nil")'")
                print("    Fix 1 (url.path): '\(fixedResult1 ?? "nil")'")
                print("    Fix 2 (scheme check): '\(fixedResult2 ?? "nil")'")
                
                // Verify the fixes work
                let fix1Works = stringResult == fixedResult1
                let fix2Works = stringResult == fixedResult2
                
                print("    Fix 1 works: \(fix1Works ? "✅" : "❌")")
                print("    Fix 2 works: \(fix2Works ? "✅" : "❌")")
            }
        }
        
        print("\n=== END PROPOSED FIX TEST ===\n")
        
        // Cleanup
        try? FileManager.default.removeItem(at: destinationURL)
    }
}