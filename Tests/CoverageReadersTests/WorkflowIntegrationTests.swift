import CoverageDelta
import CoverageModel
import CoverageReaders
import DiffCoverage
import Foundation
import GitDiff
import ProcessSupport
import Testing

@Suite struct WorkflowIntegrationTests {
    @Test func llvmArtifactAndGitDiffProduceInMemoryReport() throws {
        let repository = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: repository, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: repository) }
        try git(["init", "-q"], at: repository)
        try git(["config", "user.email", "tests@example.com"], at: repository)
        try git(["config", "user.name", "Tests"], at: repository)
        try git(["config", "commit.gpgsign", "false"], at: repository)
        let source = repository.appending(path: "Sources/App.swift")
        try FileManager.default.createDirectory(at: source.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("unchanged\nold covered\nold uncovered\n".utf8).write(to: source)
        try git(["add", "."], at: repository)
        try git(["commit", "-m", "base"], at: repository)
        let base = try git(["rev-parse", "HEAD"], at: repository)
        try Data("unchanged\nnew covered\nnew uncovered\n".utf8).write(to: source)
        try git(["commit", "-am", "head"], at: repository)

        let fixture = try #require(Bundle.module.url(forResource: "llvm-export", withExtension: "json", subdirectory: "Fixtures"))
        let mapper = try SourcePathMapper(repositoryRoot: repository.path, capturedSourceRoot: "/captured/project")
        let coverage = try LLVMCoverageReader().read(data: Data(contentsOf: fixture), pathMapper: mapper)
        let changes = try GitDiffProvider().changedLines(repository: repository, base: base, mode: .direct).changes

        let report = DiffCoverageCalculator.calculate(coverage: coverage, changes: changes, minimum: try Percentage(75))

        #expect(report.totals == CoverageCounts(executable: 2, covered: 1))
        #expect(report.policy == .failed(threshold: try Percentage(75), actual: try Percentage(50)))
    }

    @Test func twoLLVMFixturesProduceWholeProjectDeltaWithoutGitInput() throws {
        let baseFixture = try #require(Bundle.module.url(forResource: "llvm-export-base", withExtension: "json", subdirectory: "Fixtures"))
        let headFixture = try #require(Bundle.module.url(forResource: "llvm-export", withExtension: "json", subdirectory: "Fixtures"))
        let mapper = try SourcePathMapper(repositoryRoot: "/current/project", capturedSourceRoot: "/captured/project")

        let base = try LLVMCoverageReader().read(data: Data(contentsOf: baseFixture), pathMapper: mapper)
        let head = try LLVMCoverageReader().read(data: Data(contentsOf: headFixture), pathMapper: mapper)
        let delta = CoverageDeltaCalculator.calculate(base: base, head: head)

        #expect(delta.project.base == CoverageCounts(executable: 1, covered: 1))
        #expect(delta.project.head == CoverageCounts(executable: 3, covered: 2))
        #expect(abs((delta.project.percentagePointChange?.value ?? 0) - (-100.0 / 3.0)) < 0.000_001)
    }

    @discardableResult
    private func git(_ arguments: [String], at repository: URL) throws -> String {
        let result = try FoundationProcessRunner().run(command: "git", arguments: arguments, currentDirectory: repository)
        guard result.exitCode == 0 else {
            throw GitDiffError.commandFailed(arguments: arguments, detail: result.standardError)
        }
        return String(decoding: result.standardOutput, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
