import CoverageModel
import CoverageReaders
import Foundation
import Testing

@Suite struct LLVMCoverageReaderTests {
    @Test func readsSegmentsAndMapsCapturedAndRelativePaths() throws {
        let fixture = try #require(Bundle.module.url(forResource: "llvm-export", withExtension: "json", subdirectory: "Fixtures"))
        let mapper = try SourcePathMapper(repositoryRoot: "/current/project", capturedSourceRoot: "/captured/project")

        let coverage = try LLVMCoverageReader().read(data: Data(contentsOf: fixture), pathMapper: mapper)

        #expect(coverage.files.count == 2)
        #expect(coverage.files[try RepositoryPath("Sources/App.swift")]?.lines == [2: 4, 3: 0])
        #expect(coverage.files[try RepositoryPath("Sources/Relative.swift")]?.lines == [7: 1])
    }

    @Test func readsExportGeneratedBySwift621() throws {
        let fixture = try #require(Bundle.module.url(
            forResource: "llvm-export-swift-6.2.1",
            withExtension: "json",
            subdirectory: "Fixtures"
        ))
        let mapper = try SourcePathMapper(repositoryRoot: "/current/project", capturedSourceRoot: "/captured/project")

        let coverage = try LLVMCoverageReader().read(data: Data(contentsOf: fixture), pathMapper: mapper)

        let path = try RepositoryPath("Tests/FixtureTests/FixtureTests.swift")
        #expect(coverage.files[path]?.lines == [4: 1, 5: 1, 6: 1])
    }

    @Test func pathMapperUsesComponentBoundaryAndExcludesOutsidePaths() throws {
        let mapper = try SourcePathMapper(repositoryRoot: "/repo")
        #expect(try mapper.map("/repo/Sources/A.swift") == RepositoryPath("Sources/A.swift"))
        #expect(try mapper.map("/repository/Sources/A.swift") == nil)
        #expect(try mapper.map("/other/A.swift") == nil)
    }

    @Test func pathMapperRejectsOverlappingRootsWithDifferentMappings() throws {
        let mapper = try SourcePathMapper(repositoryRoot: "/repo", capturedSourceRoot: "/repo/captured")
        #expect(throws: PathMappingError.self) { try mapper.map("/repo/captured/Sources/A.swift") }
    }

    @Test func rejectsUnsupportedTypeAndVersion() throws {
        let mapper = try SourcePathMapper(repositoryRoot: "/repo")
        #expect(throws: LLVMCoverageReaderError.unsupportedType("other")) {
            try read(#"{"type":"other","version":"2.0.0","data":[]}"#, mapper)
        }
        #expect(throws: LLVMCoverageReaderError.unsupportedVersion("3.0.0")) {
            try read(#"{"type":"llvm.coverage.json.export","version":"3.0.0","data":[]}"#, mapper)
        }
    }

    @Test func rejectsMalformedJSONAndSegments() throws {
        let mapper = try SourcePathMapper(repositoryRoot: "/repo")
        #expect(throws: LLVMCoverageReaderError.self) { try read("not json", mapper) }
        let malformed = #"{"type":"llvm.coverage.json.export","version":"2.0.0","data":[{"files":[{"filename":"A.swift","segments":[[0,1,1,true,true,false]]}]}]}"#
        #expect(throws: LLVMCoverageReaderError.malformedSegment(file: "A.swift", index: 0)) {
            try read(malformed, mapper)
        }
        let invalidPath = #"{"type":"llvm.coverage.json.export","version":"2.0.0","data":[{"files":[{"filename":"../A.swift","segments":[]}]}]}"#
        #expect(throws: LLVMCoverageReaderError.self) { try read(invalidPath, mapper) }
    }

    @Test func rejectsTwoArtifactPathsMappingToOneRepositoryPath() throws {
        let mapper = try SourcePathMapper(repositoryRoot: "/current", capturedSourceRoot: "/captured")
        let json = #"{"type":"llvm.coverage.json.export","version":"2.0.0","data":[{"files":[{"filename":"/current/A.swift","segments":[]},{"filename":"/captured/A.swift","segments":[]}]}]}"#
        let expected = LLVMCoverageReaderError.ambiguousPath(
            path: try RepositoryPath("A.swift"),
            sources: ["/captured/A.swift", "/current/A.swift"]
        )
        #expect(throws: expected) { try read(json, mapper) }
    }

    private func read(_ json: String, _ mapper: SourcePathMapper) throws -> NormalizedCoverage {
        try LLVMCoverageReader().read(data: Data(json.utf8), pathMapper: mapper)
    }
}
