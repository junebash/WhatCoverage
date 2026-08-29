import CoverageModel
import CoverageReaders
import Foundation
import ProcessSupport
import Testing

@Suite struct XcodeCoverageReaderTests {
    @Test func invokesArchiveJSONAndNormalizesEquivalentCoverage() throws {
        let fixture = try #require(Bundle.module.url(
            forResource: "xccov-archive",
            withExtension: "json",
            subdirectory: "Fixtures"
        ))
        let runner = ScriptedRunner(results: [
            "xcresulttool": success(metadata(archiveIDs: ["archive-1"])),
            "xccov": ProcessResult(
                exitCode: 0,
                standardOutput: try Data(contentsOf: fixture),
                standardError: ""
            ),
        ])
        let mapper = try SourcePathMapper(
            repositoryRoot: "/current/project",
            capturedSourceRoot: "/captured/project"
        )

        let coverage = try XcodeCoverageReader(runner: runner).read(
            resultBundle: URL(fileURLWithPath: "/tmp/Tests.xcresult"),
            pathMapper: mapper
        )

        #expect(coverage.files.count == 2)
        #expect(coverage.files[try RepositoryPath("Sources/App.swift")]?.lines == [2: 4, 3: 0])
        #expect(coverage.files[try RepositoryPath("Sources/Relative.swift")]?.lines == [7: 1])

        let llvmFixture = try #require(Bundle.module.url(
            forResource: "llvm-export",
            withExtension: "json",
            subdirectory: "Fixtures"
        ))
        let llvmCoverage = try LLVMCoverageReader().read(
            data: Data(contentsOf: llvmFixture),
            pathMapper: mapper
        )
        #expect(coverage == llvmCoverage)
    }

    @Test func failsExplicitlyForZeroOrMultipleCoverageArchives() throws {
        let mapper = try SourcePathMapper(repositoryRoot: "/repo")
        let bundle = URL(fileURLWithPath: "/tmp/Tests.xcresult")

        #expect(throws: XcodeCoverageReaderError.missingCoverage(path: bundle.path)) {
            try XcodeCoverageReader(runner: ScriptedRunner(results: [
                "xcresulttool": success(metadata(archiveIDs: [])),
            ])).read(resultBundle: bundle, pathMapper: mapper)
        }
        #expect(throws: XcodeCoverageReaderError.multipleCoverageArchives(path: bundle.path, count: 2)) {
            try XcodeCoverageReader(runner: ScriptedRunner(results: [
                "xcresulttool": success(metadata(archiveIDs: ["archive-1", "archive-2"])),
            ])).read(resultBundle: bundle, pathMapper: mapper)
        }
    }

    @Test func distinguishesInvalidBundleToolAndXccovFailures() throws {
        let mapper = try SourcePathMapper(repositoryRoot: "/repo")
        let bundle = URL(fileURLWithPath: "/tmp/Tests.xcresult")

        #expect(throws: XcodeCoverageReaderError.invalidResultBundle(
            path: bundle.path,
            detail: "Error: Failed to load result bundle"
        )) {
            try XcodeCoverageReader(runner: ScriptedRunner(results: [
                "xcresulttool": failure(1, "Error: Failed to load result bundle"),
            ])).read(resultBundle: bundle, pathMapper: mapper)
        }
        #expect(throws: XcodeCoverageReaderError.toolUnavailable("xcrun: unable to find utility xccov")) {
            try XcodeCoverageReader(runner: ScriptedRunner(results: [
                "xcresulttool": failure(72, "xcrun: unable to find utility xccov"),
            ])).read(resultBundle: bundle, pathMapper: mapper)
        }
        #expect(throws: XcodeCoverageReaderError.xccovFailed(
            path: bundle.path,
            exitCode: 1,
            detail: "Failed to load coverage archive"
        )) {
            try XcodeCoverageReader(runner: ScriptedRunner(results: [
                "xcresulttool": success(metadata(archiveIDs: ["archive-1"])),
                "xccov": failure(1, "Failed to load coverage archive"),
            ])).read(resultBundle: bundle, pathMapper: mapper)
        }
    }

    @Test func rejectsMalformedMetadataArchiveAndExecutableLines() throws {
        let mapper = try SourcePathMapper(repositoryRoot: "/repo")
        let bundle = URL(fileURLWithPath: "/tmp/Tests.xcresult")

        #expect(throws: XcodeCoverageReaderError.self) {
            try XcodeCoverageReader(runner: ScriptedRunner(results: [
                "xcresulttool": success("{}"),
            ])).read(resultBundle: bundle, pathMapper: mapper)
        }
        #expect(throws: XcodeCoverageReaderError.self) {
            try XcodeCoverageReader(runner: ScriptedRunner(results: [
                "xcresulttool": success(metadata(archiveIDs: ["archive-1"])),
                "xccov": success("not json"),
            ])).read(resultBundle: bundle, pathMapper: mapper)
        }
        let malformedLine = #"{"A.swift":[{"line":1,"isExecutable":true}]}"#
        #expect(throws: XcodeCoverageReaderError.malformedLine(source: "A.swift", index: 0)) {
            try XcodeCoverageReader(runner: ScriptedRunner(results: [
                "xcresulttool": success(metadata(archiveIDs: ["archive-1"])),
                "xccov": success(malformedLine),
            ])).read(resultBundle: bundle, pathMapper: mapper)
        }
    }

    private func metadata(archiveIDs: [String]) -> String {
        let actions = archiveIDs.map { id in
            "{\"actionResult\":{\"coverage\":{\"archiveRef\":{\"id\":{\"_value\":\"\(id)\"}}}}}"
        }
        return "{\"actions\":{\"_values\":[\(actions.joined(separator: ","))]}}"
    }

    private func success(_ text: String) -> ProcessResult {
        ProcessResult(exitCode: 0, standardOutput: Data(text.utf8), standardError: "")
    }

    private func failure(_ exitCode: Int32, _ detail: String) -> ProcessResult {
        ProcessResult(exitCode: exitCode, standardOutput: Data(), standardError: detail)
    }
}

private struct ScriptedRunner: ProcessRunning {
    let results: [String: ProcessResult]

    func run(command: String, arguments: [String], currentDirectory: URL) throws -> ProcessResult {
        guard command == "xcrun", let tool = arguments.first, let result = results[tool] else {
            throw StubError.unexpectedCommand(command: command, arguments: arguments)
        }
        if tool == "xcresulttool" {
            guard arguments.dropFirst() == [
                "get", "object", "--legacy", "--path", "/tmp/Tests.xcresult", "--format", "json",
            ] else {
                throw StubError.unexpectedCommand(command: command, arguments: arguments)
            }
        } else if tool == "xccov" {
            guard arguments.dropFirst() == ["view", "--archive", "--json", "/tmp/Tests.xcresult"] else {
                throw StubError.unexpectedCommand(command: command, arguments: arguments)
            }
        }
        return result
    }
}

private enum StubError: Error {
    case unexpectedCommand(command: String, arguments: [String])
}
