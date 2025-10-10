import Foundation
import Testing

@testable import EPUBParser

/// Tests for EPUB metadata parsing
@Suite("EPUB Metadata")
struct EPUBMetadataTests {

    @Test("Metadata extraction")
    func testMetadataExtraction() async throws {
        guard let testEPUBPath = TestConfiguration.findTestEPUBFile() else {
            Issue.record("No test EPUB file found")
            return
        }

        let parser = EPUBParser(epubPath: testEPUBPath, identifier: "metadata_test")
        defer { parser.cleanup() }

        let document = try await parser.processEPUB()
        let metadata = document.metadata

        print("📖 EPUB Metadata:")

        // Test title
        if let title = metadata.title {
            print("  Title: \(title)")
            #expect(!title.isEmpty, "Title should not be empty")
        } else {
            print("  Title: (not specified)")
        }

        // Test creators/authors
        print("  Creators: \(metadata.creators.count)")
        for (index, creator) in metadata.creators.enumerated() {
            print("    \(index + 1). \(creator)")
            #expect(!creator.isEmpty, "Creator name should not be empty")
        }

        if !metadata.creators.isEmpty {
            #expect(!metadata.creatorsString.isEmpty, "Creators string should not be empty")
            #expect(metadata.primaryCreator != nil, "Primary creator should be available")
        }

        // Test language
        if let language = metadata.language {
            print("  Language: \(language)")
            #expect(!language.isEmpty, "Language should not be empty")
        }

        // Test identifier
        if let identifier = metadata.identifier {
            print("  Identifier: \(identifier)")
            #expect(!identifier.isEmpty, "Identifier should not be empty")
        }

        // Test publisher
        if let publisher = metadata.publisher {
            print("  Publisher: \(publisher)")
        }

        // Test date
        if let date = metadata.date {
            print("  Date: \(date)")
        }

        // Test description
        if let description = metadata.description {
            print("  Description: \(description.prefix(100))...")
        }

        // Test subjects
        if !metadata.subjects.isEmpty {
            print("  Subjects: \(metadata.subjectsString)")
        }

        // Test contributors
        if !metadata.contributors.isEmpty {
            print("  Contributors: \(metadata.contributorsString)")
        }

        print("✅ Metadata extraction complete")
    }

    @Test("Metadata helper methods")
    func testMetadataHelpers() async throws {
        guard let testEPUBPath = TestConfiguration.findTestEPUBFile() else {
            Issue.record("No test EPUB file found")
            return
        }

        let parser = EPUBParser(epubPath: testEPUBPath, identifier: "metadata_helpers_test")
        defer { parser.cleanup() }

        let document = try await parser.processEPUB()
        let metadata = document.metadata

        // Test creators string formatting
        if !metadata.creators.isEmpty {
            let creatorsString = metadata.creatorsString
            #expect(creatorsString.contains(metadata.creators[0]), "Creators string should contain first creator")

            if metadata.creators.count > 1 {
                #expect(creatorsString.contains(","), "Multiple creators should be comma-separated")
            }
        }

        // Test primary creator
        if let primaryCreator = metadata.primaryCreator {
            #expect(metadata.creators.first == primaryCreator, "Primary creator should be first creator")
        }

        // Test subjects string
        if !metadata.subjects.isEmpty {
            let subjectsString = metadata.subjectsString
            #expect(subjectsString.contains(metadata.subjects[0]), "Subjects string should contain first subject")
        }

        // Test contributors string
        if !metadata.contributors.isEmpty {
            let contributorsString = metadata.contributorsString
            #expect(contributorsString.contains(metadata.contributors[0]), "Contributors string should contain first contributor")
        }

        print("✅ Metadata helper methods validated")
    }
}
