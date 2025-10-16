import Testing
import Foundation
@testable import EPUBParser

/// Test cache system functionality
struct CacheSystemTests {
    
    @Test("Verify JSON caching saves and loads correctly")
    func testCacheSystemRoundtrip() async throws {
        // Find a test EPUB file
        guard let epubPath = findFirstEPUB() else {
            Issue.record("No test EPUB files found in bundle")
            return
        }
        
        // First extraction - should save to cache
        let destinationURL = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("EPUBParser_cache_test_\(UUID())")
        
        let parser = EPUBParser(epubPath: epubPath, destinationURL: destinationURL)
        let originalDocument = try await parser.processEPUB()
        
        // Verify cache file exists
        let cacheURL = destinationURL.appendingPathComponent(".epub_cache.json")
        #expect(FileManager.default.fileExists(atPath: cacheURL.path), "Cache file should exist after first parse")
        
        // Test loading from cache using the unzipped directory initializer
        let cachedParser = try EPUBParser(unzippedPath: destinationURL)
        let cachedDocument = try await cachedParser.processEPUB()
        
        // Verify documents match
        #expect(originalDocument.metadata.title == cachedDocument.metadata.title)
        #expect(originalDocument.spineItems.count == cachedDocument.spineItems.count)
        #expect(originalDocument.manifest.count == cachedDocument.manifest.count)
        
        // Verify spine items have correct structure
        for (original, cached) in zip(originalDocument.spineItems, cachedDocument.spineItems) {
            #expect(original.id == cached.id, "Spine item IDs should match")
            #expect(original.index == cached.index, "Spine item indices should match")
            #expect(original.manifestItem.path == cached.manifestItem.path, "Spine item paths should match")
        }
        
        print("✅ Cache system test passed - documents match after round-trip")
        
        // Clean up
        try? FileManager.default.removeItem(at: destinationURL)
    }
    
    @Test("Test second init requires cache file")
    func testSecondInitRequiresCache() async throws {
        let destinationURL = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("EPUBParser_no_cache_test_\(UUID())")
        
        // Create directory with required EPUB structure but no cache file
        try FileManager.default.createDirectory(at: destinationURL, withIntermediateDirectories: true)
        let metaInfDir = destinationURL.appendingPathComponent("META-INF")
        try FileManager.default.createDirectory(at: metaInfDir, withIntermediateDirectories: true)
        
        // Create minimal container.xml
        let containerContent = """
        <?xml version="1.0" encoding="UTF-8"?>
        <container version="1.0" xmlns="urn:oasis:names:tc:opendocument:xmlns:container">
            <rootfiles>
                <rootfile full-path="OEBPS/content.opf" media-type="application/oebps-package+xml"/>
            </rootfiles>
        </container>
        """
        try containerContent.write(to: metaInfDir.appendingPathComponent("container.xml"), 
                                  atomically: true, encoding: .utf8)
        
        // Should throw cacheNotFound error when initializing (cache file is missing)
        do {
            _ = try EPUBParser(unzippedPath: destinationURL)
            Issue.record("Expected EPUBParserError.cacheNotFound but initialization succeeded")
        } catch EPUBParserError.cacheNotFound {
            print("✅ Correctly threw cacheNotFound error when cache file missing")
        } catch {
            Issue.record("Expected EPUBParserError.cacheNotFound but got: \(error)")
        }
        
        // Clean up
        try? FileManager.default.removeItem(at: destinationURL)
    }
    
    @Test("Test relative path conversion in cache")
    func testRelativePathConversion() async throws {
        guard let epubPath = findFirstEPUB() else {
            Issue.record("No test EPUB files found in bundle")
            return
        }
        
        let destinationURL = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("EPUBParser_relative_path_test_\(UUID())")
        
        let parser = EPUBParser(epubPath: epubPath, destinationURL: destinationURL)
        _ = try await parser.processEPUB()
        
        // Read the cached JSON file
        let cacheURL = destinationURL.appendingPathComponent(".epub_cache.json")
        let jsonData = try Data(contentsOf: cacheURL)
        let jsonObject = try JSONSerialization.jsonObject(with: jsonData) as? [String: Any]
        
        // Check that baseURL is stored as a relative path in the JSON
        if let baseURL = jsonObject?["baseURL"] as? String {
            #expect(!baseURL.contains("/var/folders/") && !baseURL.contains("/tmp/"), 
                    "Cache should store relative paths, not absolute. Found: \(baseURL)")
            print("✅ Cache correctly stores relative baseURL: \(baseURL)")
        }
        
        // Clean up
        try? FileManager.default.removeItem(at: destinationURL)
    }
    
    // Helper function to find the first EPUB file in the test bundle
    private func findFirstEPUB() -> URL? {
        // Try to find EPUB files in common test directories
        let testPaths = [
            "/Users/kai/Downloads",
            "/Users/kai/Desktop", 
            "/Users/kai/Documents",
            FileManager.default.currentDirectoryPath
        ]
        
        for basePath in testPaths {
            let enumerator = FileManager.default.enumerator(atPath: basePath)
            while let file = enumerator?.nextObject() as? String {
                if file.lowercased().hasSuffix(".epub") {
                    return URL(fileURLWithPath: basePath).appendingPathComponent(file)
                }
            }
        }
        
        // Fallback: create a dummy test case
        Issue.record("No EPUB files found for testing - skipping cache tests")
        return nil
    }
}