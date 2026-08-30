import CoverageModel
import Foundation
import GitDiff
import ProcessSupport
import Testing

@Suite struct GitDiffProviderIntegrationTests {
    @Test func processRunnerCapturesOutputLargerThanAPipeBuffer() throws {
        let result = try FoundationProcessRunner().run(
            command: "sh",
            arguments: ["-c", "head -c 200000 /dev/zero | tr '\\0' x"],
            currentDirectory: FileManager.default.temporaryDirectory
        )

        #expect(result.exitCode == 0)
        #expect(result.standardOutput.count == 200_000)
    }

    @Test func discoversModificationsRenamesAndFiltersDeletedAndBinaryFiles() throws {
        let repository = try makeRepository()
        defer { try? FileManager.default.removeItem(at: repository) }
        try write("one\ntwo\nthree\n", to: repository.appending(path: "Source.swift"))
        try write("one\ntwo\nthree\nfour\nfive\n", to: repository.appending(path: "Old.swift"))
        try write("delete\n", to: repository.appending(path: "Deleted.swift"))
        try git(["add", "."], at: repository)
        try git(["commit", "-m", "base"], at: repository)
        let base = try git(["rev-parse", "HEAD"], at: repository)

        try write("ONE\ntwo\nthree\nfour\n", to: repository.appending(path: "Source.swift"))
        try git(["mv", "Old.swift", "Renamed.swift"], at: repository)
        try write("one\ntwo\nthree\nfour\nfive\nsix\n", to: repository.appending(path: "Renamed.swift"))
        try FileManager.default.removeItem(at: repository.appending(path: "Deleted.swift"))
        try Data([0, 1, 2, 0]).write(to: repository.appending(path: "image.bin"))
        try git(["add", "-A"], at: repository)
        try git(["update-index", "--add", "--cacheinfo", "160000,\(base),Dependency"], at: repository)
        try git(["commit", "-m", "head"], at: repository)

        let result = try GitDiffProvider().changedLines(repository: repository, base: base, mode: .direct)

        #expect(result.changes.files[try path("Source.swift")]?.addedLines == [1, 4])
        #expect(result.changes.files[try path("Renamed.swift")]?.addedLines == [6])
        #expect(result.changes.files[try path("Deleted.swift")] == nil)
        #expect(result.changes.files[try path("image.bin")] == nil)
        #expect(result.changes.files[try path("Dependency")] == nil)
        #expect(result.comparison.mode == .direct)
        #expect(result.comparison.resolvedBase == base)
        #expect(result.comparison.requestedHead == "HEAD")
    }

    @Test func defaultComparisonRecordsMergeBaseSemantics() throws {
        let repository = try makeRepository()
        defer { try? FileManager.default.removeItem(at: repository) }
        try write("base\n", to: repository.appending(path: "A.swift"))
        try git(["add", "."], at: repository)
        try git(["commit", "-m", "base"], at: repository)
        let base = try git(["rev-parse", "HEAD"], at: repository)
        try write("base\nfeature\n", to: repository.appending(path: "A.swift"))
        try git(["commit", "-am", "feature"], at: repository)

        let result = try GitDiffProvider().changedLines(repository: repository, base: base)

        #expect(result.comparison.mode == .mergeBase)
        #expect(result.comparison.resolvedBase == base)
        #expect(result.changes.files[try path("A.swift")]?.addedLines == [2])
    }

    @Test func invalidRevisionProducesActionableGitError() throws {
        let repository = try makeRepository()
        defer { try? FileManager.default.removeItem(at: repository) }

        do {
            _ = try GitDiffProvider().changedLines(repository: repository, base: "missing")
            Issue.record("Expected invalid revision to fail")
        } catch {
            let message = String(describing: error)
            #expect(message.contains("rev-parse"))
            #expect(message.contains("fetch the required history"))
        }
    }

    @Test func emptyDiffProducesEmptyChangedLines() throws {
        let repository = try makeRepository()
        defer { try? FileManager.default.removeItem(at: repository) }
        try write("unchanged\n", to: repository.appending(path: "A.swift"))
        try git(["add", "."], at: repository)
        try git(["commit", "-m", "only"], at: repository)

        let result = try GitDiffProvider().changedLines(repository: repository, base: "HEAD", mode: .direct)

        #expect(result.changes.files.isEmpty)
        #expect(result.comparison.resolvedBase == result.comparison.resolvedHead)
    }

    private func makeRepository() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        try git(["init", "-q"], at: url)
        try git(["config", "user.email", "tests@example.com"], at: url)
        try git(["config", "user.name", "Tests"], at: url)
        try git(["config", "commit.gpgsign", "false"], at: url)
        return url
    }

    @discardableResult
    private func git(_ arguments: [String], at repository: URL) throws -> String {
        let result = try FoundationProcessRunner().run(command: "git", arguments: arguments, currentDirectory: repository)
        guard result.exitCode == 0 else {
            throw GitDiffError.commandFailed(arguments: arguments, detail: result.standardError)
        }
        return String(decoding: result.standardOutput, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func write(_ text: String, to url: URL) throws { try Data(text.utf8).write(to: url) }
    private func path(_ value: String) throws -> RepositoryPath { try RepositoryPath(value) }
}
