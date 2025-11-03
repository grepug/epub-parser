import Foundation
import Testing

@testable import EPUBParser

struct NavigateScenarioTest {

    @Test("Simulate navigate function assertion failure scenario")
    func testNavigateAssertionFailureScenario() async throws {
        // Find a test EPUB file
        guard let epubURL = TestConfiguration.findTestEPUBFile() else {
            Issue.record("No test EPUB file found. Please add an EPUB file to the configured test directories.")
            return
        }

        // Create a destination URL for this test
        let destinationURL = TestConfiguration.testDestinationURL(for: "navigate_assertion_test")

        // Initialize and process
        let parser = EPUBParser(
            epubPath: epubURL,
            destinationURL: destinationURL,
            skipUnzipIfDirectoryExists: true,
            cleanup: false
        )

        let document = try await parser.processEPUB()
        
        print("\n=== NAVIGATE ASSERTION FAILURE SCENARIO TEST ===")
        
        // Simulate what a navigate function might do that could cause assertion failures
        // This replicates the logic that might be on lines 144 and 149 mentioned in the screenshot
        
        func simulateNavigateFunction(toPath path: String) -> Bool {
            print("Navigating to path: '\(path)'")
            
            // Line 144 equivalent - Get spine ID for the path
            let spineId = document.spineItemId(for: path)
            
            // This would cause an assertion failure if spineId is nil
            guard let spineId = spineId else {
                print("❌ ASSERTION FAILURE at line 144 equivalent: No spine ID found for path '\(path)'")
                return false
            }
            
            print("✅ Found spine ID: '\(spineId)'")
            
            // Line 149 equivalent - Validate that the spine ID exists in the spine
            let spineItem = document.spineItems.first { $0.id == spineId }
            
            // This would cause an assertion failure if spineItem is nil
            guard let spineItem = spineItem else {
                print("❌ ASSERTION FAILURE at line 149 equivalent: Spine ID '\(spineId)' not found in spine items")
                return false
            }
            
            print("✅ Found spine item: id='\(spineItem.id)', index='\(spineItem.index)', path='\(spineItem.manifestItem.path)'")
            
            return true
        }
        
        // Test 1: Navigate to all spine items (should work)
        print("\n--- Test 1: Navigate to all spine item paths ---")
        var successCount = 0
        var failureCount = 0
        
        for (index, spineItem) in document.spineItems.enumerated() {
            let path = spineItem.manifestItem.path
            let success = simulateNavigateFunction(toPath: path)
            
            if success {
                successCount += 1
            } else {
                failureCount += 1
                print("Failed navigation [\(index)]: '\(path)'")
            }
        }
        
        print("Navigation results: \(successCount) success, \(failureCount) failures")
        
        // Test 2: Navigate with problematic paths that might cause issues
        print("\n--- Test 2: Navigate with problematic paths ---")
        
        let problematicPaths = [
            "", // Empty string
            "nonexistent.html", // Non-existent file
            "text/chapter01.html", // Generic path not in this EPUB
            "/absolute/path/chapter.html", // Absolute path
            "file:///absolute/file/path.html", // File URL string
            "text/../text/chapter01.html", // Path with navigation
            "text/./chapter01.html", // Path with current directory reference
        ]
        
        for path in problematicPaths {
            print("Testing problematic path: '\(path)'")
            let success = simulateNavigateFunction(toPath: path)
            if !success {
                print("  Expected failure for: '\(path)'")
            } else {
                print("  Unexpected success for: '\(path)'")
            }
        }
        
        // Test 3: Navigate with URLs that might cause the absoluteString issue
        print("\n--- Test 3: Navigate with URL objects ---")
        
        if let firstSpineItem = document.spineItems.first {
            let manifestPath = firstSpineItem.manifestItem.path
            
            // Test with different URL types
            let relativeURL = URL(string: manifestPath)!
            let fileURL = URL(fileURLWithPath: manifestPath)
            let httpURL = URL(string: "http://example.com/\(manifestPath)")!
            
            print("Testing relative URL: '\(relativeURL)'")
            let relativeSuccess = simulateNavigateFunction(toPath: relativeURL.absoluteString)
            
            print("Testing file URL: '\(fileURL)'")
            let fileSuccess = simulateNavigateFunction(toPath: fileURL.absoluteString)
            
            print("Testing http URL: '\(httpURL)'")
            let httpSuccess = simulateNavigateFunction(toPath: httpURL.absoluteString)
            
            // This is where the bug might manifest - when passing URL.absoluteString
            // that creates paths that don't match the spine item paths
            if !fileSuccess {
                print("🎯 POTENTIAL BUG FOUND: File URL absoluteString navigation failed")
                print("   Original path: '\(manifestPath)'")
                print("   File URL absoluteString: '\(fileURL.absoluteString)'")
                print("   This could be the source of the assertion failures!")
            }
            
            if !httpSuccess {
                print("🎯 POTENTIAL BUG FOUND: HTTP URL absoluteString navigation failed")
                print("   Original path: '\(manifestPath)'")
                print("   HTTP URL absoluteString: '\(httpURL.absoluteString)'")
                print("   This could be the source of the assertion failures!")
            }
        }
        
        // Test 4: Navigate with modified paths (after HTML extension normalization)
        print("\n--- Test 4: Navigate with HTML extension modified paths ---")
        
        for spineItem in document.spineItems.prefix(3) {
            let originalPath = spineItem.manifestItem.path
            
            // Simulate what might happen if someone tries to navigate to an old path
            // after HTML extension normalization has changed the file paths
            if originalPath.hasSuffix(".xhtml") {
                let modifiedPath = String(originalPath.dropLast(6)) + ".html"  // Change .xhtml to .html
                
                print("Testing modified path scenario:")
                print("  Original: '\(originalPath)'")
                print("  Modified: '\(modifiedPath)'")
                
                let originalSuccess = simulateNavigateFunction(toPath: originalPath)
                let modifiedSuccess = simulateNavigateFunction(toPath: modifiedPath)
                
                if originalSuccess != modifiedSuccess {
                    print("🎯 POTENTIAL ISSUE: Original and modified path navigation results differ")
                    print("   This could cause navigation issues if paths are inconsistent")
                }
            }
        }
        
        print("\n=== END NAVIGATE ASSERTION FAILURE SCENARIO TEST ===\n")
        
        // The test passes if we successfully identified potential issues
        // In a real scenario, assertion failures would prevent the test from completing
        #expect(failureCount == 0, "All spine item navigations should succeed")
        
        // Cleanup
        try? FileManager.default.removeItem(at: destinationURL)
    }
    
    @Test("Test edge case spine ID lookups that might cause assertions")
    func testEdgeCaseSpineIDLookups() async throws {
        // Find a test EPUB file
        guard let epubURL = TestConfiguration.findTestEPUBFile() else {
            Issue.record("No test EPUB file found. Please add an EPUB file to the configured test directories.")
            return
        }

        // Create a destination URL for this test
        let destinationURL = TestConfiguration.testDestinationURL(for: "edge_case_spine_id")

        // Initialize and process
        let parser = EPUBParser(
            epubPath: epubURL,
            destinationURL: destinationURL,
            skipUnzipIfDirectoryExists: true,
            cleanup: false
        )

        let document = try await parser.processEPUB()
        
        print("\n=== EDGE CASE SPINE ID LOOKUP TEST ===")
        
        // These are edge cases that might cause assertion failures in navigation code
        let edgeCases = [
            ("Empty string", ""),
            ("Just filename", "chapter01.xhtml"),
            ("Absolute file path", "/Users/test/chapter01.xhtml"),
            ("URL with scheme", "file:///test/chapter01.xhtml"),
            ("HTTP URL", "http://example.com/chapter01.xhtml"),
            ("Path with query", "chapter01.xhtml?param=value"),
            ("Path with fragment", "chapter01.xhtml#section1"),
            ("Path with both", "chapter01.xhtml?param=value#section1"),
            ("Windows path", "text\\chapter01.xhtml"),
            ("Path with spaces", "text/chapter 01.xhtml"),
            ("Path with unicode", "text/chaptér_01.xhtml"),
            ("Very long path", String(repeating: "text/", count: 100) + "chapter01.xhtml"),
        ]
        
        for (description, testPath) in edgeCases {
            print("Testing \(description): '\(testPath)'")
            let result = document.spineItemId(for: testPath)
            print("  Result: '\(result ?? "nil")'")
            
            // Check if this would cause an assertion in a navigate function
            if result == nil && !testPath.isEmpty {
                print("  ⚠️ Would cause assertion failure if not handled properly")
            }
        }
        
        // Test URL-based lookups that might behave differently
        print("\n--- URL-based lookups ---")
        
        if let firstSpineItem = document.spineItems.first {
            let manifestPath = firstSpineItem.manifestItem.path
            
            // Test various URL configurations
            let urls: [(String, URL?)] = [
                ("Relative URL", URL(string: manifestPath)),
                ("File URL", URL(fileURLWithPath: manifestPath)),
                ("Base + relative", URL(string: manifestPath, relativeTo: URL(fileURLWithPath: "/base/"))),
                ("Fragment URL", URL(string: manifestPath + "#fragment")),
            ]
            
            for (description, url) in urls {
                guard let url = url else {
                    print("\(description): Failed to create URL")
                    continue
                }
                
                print("\(description): '\(url)'")
                
                // Test both string and URL methods
                let stringResult = document.spineItemId(for: url.absoluteString)
                let urlResult = document.spineItemId(for: url)
                
                print("  absoluteString result: '\(stringResult ?? "nil")'")
                print("  URL result: '\(urlResult ?? "nil")'")
                
                if stringResult != urlResult {
                    print("  ❌ MISMATCH: String and URL methods return different results!")
                    print("     This discrepancy could cause navigation issues")
                }
            }
        }
        
        print("\n=== END EDGE CASE SPINE ID LOOKUP TEST ===\n")
        
        // Cleanup
        try? FileManager.default.removeItem(at: destinationURL)
    }
}