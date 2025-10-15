import Foundation
import Testing

@testable import EPUBParser

struct SpineIDDebugTest {

    @Test("Comprehensive spine ID debugging test")
    func testSpineIDIssues() async throws {
        // Find a test EPUB file
        guard let epubURL = TestConfiguration.findTestEPUBFile() else {
            Issue.record("No test EPUB file found. Please add an EPUB file to the configured test directories.")
            return
        }

        // Create a destination URL for this test
        let destinationURL = TestConfiguration.testDestinationURL(for: "spine_id_debug")

        // Initialize and process
        let parser = EPUBParser(
            epubPath: epubURL,
            destinationURL: destinationURL,
            skipUnzipIfDirectoryExists: true,
            cleanup: false
        )

        let document = try await parser.processEPUB()
        
        print("\n=== SPINE ID DEBUG TEST ===")
        print("EPUB: \(epubURL.lastPathComponent)")
        print("Spine items count: \(document.spine.count)")
        print("Manifest items count: \(document.manifest.count)")
        
        // Debug all spine items
        print("\n--- SPINE ITEMS ---")
        for (index, spineItem) in document.spine.enumerated() {
            print("[\(index)] Spine Item:")
            print("  id: '\(spineItem.id)'")
            print("  id: '\(spineItem.id)'")
            print("  manifestItem.id: '\(spineItem.manifestItem.id)'")
            print("  manifestItem.path: '\(spineItem.manifestItem.path)'")
            print("  manifestItem.mediaType: '\(spineItem.manifestItem.mediaType)'")
            
            // Test spineItemId lookup for this item
            let lookupById = document.spineItemId(for: spineItem.manifestItem.path)
            let lookupByURL = document.spineItemId(for: URL(string: spineItem.manifestItem.path)!)
            
            print("  spineItemId(for: path) → '\(lookupById ?? "nil")'")
            print("  spineItemId(for: URL) → '\(lookupByURL ?? "nil")'")
            
            // Check if lookups match expected values
            let expectedId = spineItem.id
            if lookupById != expectedId {
                print("  ❌ MISMATCH: Expected '\(expectedId)', got '\(lookupById ?? "nil")'")
            } else {
                print("  ✅ Path lookup matches")
            }
            
            if lookupByURL != expectedId {
                print("  ❌ MISMATCH: Expected '\(expectedId)', got '\(lookupByURL ?? "nil")'")
            } else {
                print("  ✅ URL lookup matches")
            }
            print("")
        }
        
        // Test various edge cases that might cause issues
        print("\n--- EDGE CASE TESTS ---")
        
        // Test 1: Empty string
        let emptyResult = document.spineItemId(for: "")
        print("spineItemId(for: '') → '\(emptyResult ?? "nil")'")
        #expect(emptyResult == nil, "Empty string should return nil")
        
        // Test 2: Non-existent path
        let nonExistentResult = document.spineItemId(for: "non-existent-file.html")
        print("spineItemId(for: 'non-existent-file.html') → '\(nonExistentResult ?? "nil")'")
        #expect(nonExistentResult == nil, "Non-existent path should return nil")
        
        // Test 3: Path with fragment
        if let firstSpineItem = document.spine.first {
            let pathWithFragment = firstSpineItem.manifestItem.path + "#section1"
            let fragmentResult = document.spineItemId(for: pathWithFragment)
            print("spineItemId(for: '\(pathWithFragment)') → '\(fragmentResult ?? "nil")'")
            #expect(fragmentResult == firstSpineItem.id, "Path with fragment should match spine item id")
        }
        
        // Test 4: URL with various schemes
        if let firstSpineItem = document.spine.first {
            let fileURL = URL(fileURLWithPath: firstSpineItem.manifestItem.path)
            let fileURLResult = document.spineItemId(for: fileURL)
            print("spineItemId(for: fileURL) → '\(fileURLResult ?? "nil")'")
            
            // Test with relative URL
            if let relativeURL = URL(string: firstSpineItem.manifestItem.path) {
                let relativeResult = document.spineItemId(for: relativeURL)
                print("spineItemId(for: relativeURL) → '\(relativeResult ?? "nil")'")
                #expect(relativeResult == firstSpineItem.id, "Relative URL should match spine item id")
            }
        }
        
        // Test 5: Check for duplicate spine items or manifest items that might cause confusion
        let spineIds = document.spine.map { $0.id }
        let uniqueIds = Set(spineIds)
        if spineIds.count != uniqueIds.count {
            print("⚠️ WARNING: Duplicate spine item ids detected!")
            let duplicates = Dictionary(grouping: document.spine, by: { $0.id }).filter { $0.value.count > 1 }
            for (spineId, occurrences) in duplicates {
                print("  Duplicate id '\(spineId)' appears \(occurrences.count) times")
        }
        
        // Test 6: Check for manifest items without corresponding spine items
        let manifestIds = document.manifest.map { $0.id }
        let spineIdsSet = Set(spineIds)
        let orphanedManifestItems = manifestIds.filter { !spineIdsSet.contains($0) }
        if !orphanedManifestItems.isEmpty {
            print("ℹ️ Manifest items not in spine: \(orphanedManifestItems)")
        }
        
        // Test 7: Simulate the navigate function scenario
        print("\n--- NAVIGATE FUNCTION SIMULATION ---")
        
        // Test what might happen in a navigate function
        for (index, spineItem) in document.spine.enumerated() {
            let manifestItem = spineItem.manifestItem
            
            // This is what a navigate function might do:
            // 1. Get the spine item ID for a given path/URL
            let foundSpineId = document.spineItemId(for: manifestItem.path)
            
            // 2. Assert that we found a valid spine ID
            if foundSpineId == nil {
                print("❌ CRITICAL: No spine ID found for manifest path '\(manifestItem.path)'")
                print("   This would cause an assertion failure in a navigate function!")
            } else if foundSpineId != spineItem.id {
                print("❌ CRITICAL: Spine ID mismatch for manifest path '\(manifestItem.path)'")
                print("   Expected: '\(spineItem.id)', Found: '\(foundSpineId!)'")
                print("   This would cause incorrect navigation behavior!")
            } else {
                print("✅ Navigate test [\(index)]: Path '\(manifestItem.path)' → SpineID '\(foundSpineId!)'")
            }
        }
        
        // Test 8: Check for specific patterns that might break navigation
        print("\n--- NAVIGATION EDGE CASES ---")
        
        // Test paths that might be problematic
        let testPaths = [
            "text/chapter01.xhtml",
            "OEBPS/text/chapter01.xhtml", 
            "chapter01.html",
            "Text/Chapter01.xhtml",
            "../text/chapter01.xhtml",
            "./chapter01.xhtml"
        ]
        
        for testPath in testPaths {
            let result = document.spineItemId(for: testPath)
            print("Test path '\(testPath)' → '\(result ?? "nil")'")
        }
        
        print("\n=== END SPINE ID DEBUG TEST ===\n")
        
        // Cleanup
        try? FileManager.default.removeItem(at: destinationURL)
    }
    
    @Test("Test specific spine ID assertion failure scenarios")
    func testSpineIDAssertionFailures() async throws {
        // Find a test EPUB file
        guard let epubURL = TestConfiguration.findTestEPUBFile() else {
            Issue.record("No test EPUB file found. Please add an EPUB file to the configured test directories.")
            return
        }

        // Create a destination URL for this test
        let destinationURL = TestConfiguration.testDestinationURL(for: "spine_id_assertions")

        // Initialize and process
        let parser = EPUBParser(
            epubPath: epubURL,
            destinationURL: destinationURL,
            skipUnzipIfDirectoryExists: true,
            cleanup: false
        )

        let document = try await parser.processEPUB()
        
        print("\n=== ASSERTION FAILURE SIMULATION ===")
        
        // Simulate scenarios that would cause assertion failures in navigate functions
        
        // Scenario 1: Navigate to each spine item and verify lookup works
        for (index, spineItem) in document.spine.enumerated() {
            let manifestPath = spineItem.manifestItem.path
            
            // This simulates what line 144 might be doing
            let spineId = document.spineItemId(for: manifestPath)
            
            if spineId == nil {
                print("❌ ASSERTION WOULD FAIL at line 144 equivalent:")
                print("   Spine item [\(index)] with path '\(manifestPath)' returned nil spineId")
                print("   Expected id: '\(spineItem.id)'")
                
                // Try to debug why this failed
                print("   Debug info:")
                print("     Manifest item ID: '\(spineItem.manifestItem.id)'")
                print("     Spine item idref: '\(spineItem.id)'")
                print("     Do they match? \(spineItem.manifestItem.id == spineItem.id)")
                
                // Check if there's a mismatch causing the lookup failure
                #expect(spineId != nil, "Spine ID lookup should not return nil for valid spine item path")
            }
            
            // This simulates what line 149 might be doing
            if let foundSpineId = spineId, foundSpineId != spineItem.id {
                print("❌ ASSERTION WOULD FAIL at line 149 equivalent:")
                print("   Expected spine idref '\(spineItem.id)' but got '\(foundSpineId)'")
                print("   For path: '\(manifestPath)'")
                
                #expect(foundSpineId == spineItem.id, "Found spine ID should match expected idref")
            }
        }
        
        // Scenario 2: Test with modified paths (simulating HTML extension changes)
        for (index, spineItem) in document.spine.enumerated() {
            let originalPath = spineItem.manifestItem.path
            
            // Test if the path was modified during HTML extension normalization
            let pathWithoutExtension = URL(fileURLWithPath: originalPath).deletingPathExtension().path
            let modifiedPath = pathWithoutExtension + ".html"
            
            if originalPath != modifiedPath {
                print("\nTesting modified path scenario for spine item [\(index)]:")
                print("  Original path: '\(originalPath)'")
                print("  Modified path: '\(modifiedPath)'")
                
                let originalLookup = document.spineItemId(for: originalPath)
                let modifiedLookup = document.spineItemId(for: modifiedPath)
                
                print("  Original lookup result: '\(originalLookup ?? "nil")'")
                print("  Modified lookup result: '\(modifiedLookup ?? "nil")'")
                
                // This might be where the assertion failure occurs if the path was changed
                // but the spine item still references the old path
                if originalLookup == nil && modifiedLookup != nil {
                    print("  ⚠️ Original path lookup failed but modified path works - this could cause navigation issues")
                } else if originalLookup != nil && modifiedLookup == nil {
                    print("  ⚠️ Modified path lookup failed but original path works - this could cause navigation issues")
                }
            }
        }
        
        print("\n=== END ASSERTION FAILURE SIMULATION ===\n")
        
        // Cleanup
        try? FileManager.default.removeItem(at: destinationURL)
    }
    
    @Test("Test spine ID consistency after HTML processing")
    func testSpineIDConsistencyAfterHTMLProcessing() async throws {
        // Find a test EPUB file
        guard let epubURL = TestConfiguration.findTestEPUBFile() else {
            Issue.record("No test EPUB file found. Please add an EPUB file to the configured test directories.")
            return
        }

        // Create a destination URL for this test
        let destinationURL = TestConfiguration.testDestinationURL(for: "spine_id_consistency")

        // Initialize and process
        let parser = EPUBParser(
            epubPath: epubURL,
            destinationURL: destinationURL,
            skipUnzipIfDirectoryExists: true,
            cleanup: false
        )

        let document = try await parser.processEPUB()
        
        print("\n=== SPINE ID CONSISTENCY TEST ===")
        
        // Check that every spine item can be looked up by its manifest path
        var failureCount = 0
        var successCount = 0
        
        for (index, spineItem) in document.spine.enumerated() {
            let manifestPath = spineItem.manifestItem.path
            let expectedId = spineItem.id
            
            // Test the lookup
            let foundSpineId = document.spineItemId(for: manifestPath)
            
            if foundSpineId == expectedId {
                successCount += 1
                print("✅ [\(index)] '\(manifestPath)' → '\(foundSpineId!)' ✓")
            } else {
                failureCount += 1
                print("❌ [\(index)] '\(manifestPath)' → '\(foundSpineId ?? "nil")' (expected '\(expectedId)')")
                
                // Additional debugging for failures
                print("     Spine item details:")
                print("       spine.id: '\(spineItem.id)'")
                print("       spine.id: '\(spineItem.id)'")
                print("       manifest.id: '\(spineItem.manifestItem.id)'")
                print("       manifest.path: '\(spineItem.manifestItem.path)'")
                print("       manifest.mediaType: '\(spineItem.manifestItem.mediaType)'")
            }
        }
        
        print("\nConsistency Results:")
        print("  ✅ Successful lookups: \(successCount)")
        print("  ❌ Failed lookups: \(failureCount)")
        print("  📊 Success rate: \(Double(successCount) / Double(document.spine.count) * 100.0)%")
        
        // The test should pass if all lookups are consistent
        #expect(failureCount == 0, "All spine items should be consistently lookupable by their manifest paths")
        
        print("\n=== END SPINE ID CONSISTENCY TEST ===\n")
        
        // Cleanup
        try? FileManager.default.removeItem(at: destinationURL)
    }
}