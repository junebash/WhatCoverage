import ArgumentParser
import CoverageModel
import Foundation
import Testing
import WhatCoverage

@Suite struct WhatCoverageTests {
    @Test func infersRecognizedFormatsAndRequiresAnOverrideForUnknownInputs() throws {
        #expect(try WhatCoverageCommand.inferFormat(for: "coverage.JSON") == .llvm)
        #expect(try WhatCoverageCommand.inferFormat(for: "Tests.xcresult") == .xcode)
        #expect(throws: ValidationError.self) {
            try WhatCoverageCommand.inferFormat(for: "coverage.artifact")
        }
    }

    @Test func validationRejectsInvalidInvocationBeforeWorkflowExecution() {
        #expect(throws: Never.self) {
            _ = try WhatCoverageCommand.parseAsRoot([
                "--input", "coverage.artifact", "--format", "llvm", "--base", "HEAD", "--comparison", "direct", "--json-output", "report.json",
            ])
        }
        #expect(throws: Error.self) {
            _ = try WhatCoverageCommand.parseAsRoot([
                "--input", "coverage.json", "--base", "HEAD",
            ])
        }
        #expect(throws: Error.self) {
            _ = try WhatCoverageCommand.parseAsRoot([
                "--input", "coverage.artifact", "--base", "HEAD", "--json-output", "report.json",
            ])
        }
        #expect(throws: Error.self) {
            _ = try WhatCoverageCommand.parseAsRoot([
                "--input", "coverage.json", "--base", "HEAD", "--minimum", "101", "--json-output", "report.json",
            ])
        }
        #expect(throws: Error.self) {
            _ = try WhatCoverageCommand.parseAsRoot([
                "--input", "coverage.json", "--base", "HEAD", "--captured-source-root", "relative", "--json-output", "report.json",
            ])
        }
    }

    @Test func llvmWorkflowWritesBothReportsBeforeReturningThresholdFailure() throws {
        let repository = try makeRepository()
        defer { try? FileManager.default.removeItem(at: repository) }
        let source = repository.appending(path: "Sources/App.swift")
        try FileManager.default.createDirectory(at: source.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("unchanged\n".utf8).write(to: source)
        try git(["add", "."], at: repository)
        try git(["commit", "-m", "base"], at: repository)
        let base = try git(["rev-parse", "HEAD"], at: repository)
        try Data("unchanged\nchanged\n".utf8).write(to: source)
        try git(["commit", "-am", "head"], at: repository)

        let artifact = repository.appending(path: "coverage.artifact")
        try Data("""
        {"type":"llvm.coverage.json.export","version":"2.0.0","data":[{"files":[{"filename":"/captured/Sources/App.swift","segments":[[2,1,0,true,true,false],[3,1,0,false,true,false]]}]}]}
        """.utf8).write(to: artifact)
        let configuration = WhatCoverageConfiguration(
            input: artifact.path,
            format: .llvm,
            base: base,
            comparison: .direct,
            capturedSourceRoot: "/captured",
            markdownOutput: "report.md",
            jsonOutput: "report.json",
            minimum: try Percentage(100)
        )

        let status = try WhatCoverageWorkflow().run(configuration, repository: repository)

        #expect(status == .thresholdFailed)
        let markdown = try String(contentsOf: repository.appending(path: "report.md"), encoding: .utf8)
        let json = try String(contentsOf: repository.appending(path: "report.json"), encoding: .utf8)
        #expect(markdown.contains("**Policy:** Failed (minimum 100.00%)"))
        #expect(json.contains(#""status" : "failed""#))
        #expect(json.contains(#""capturedSourceRoot" : "/captured""#))
    }

    @Test func noChangedExecutableLinesSucceedsWithAThreshold() throws {
        let repository = try makeRepository()
        defer { try? FileManager.default.removeItem(at: repository) }
        try Data("base\n".utf8).write(to: repository.appending(path: "App.swift"))
        try git(["add", "."], at: repository)
        try git(["commit", "-m", "base"], at: repository)
        let base = try git(["rev-parse", "HEAD"], at: repository)
        try Data("base\nchanged\n".utf8).write(to: repository.appending(path: "App.swift"))
        try git(["commit", "-am", "head"], at: repository)
        let artifact = repository.appending(path: "coverage.json")
        try Data(("{" + #""type":"llvm.coverage.json.export","version":"2.0.0","data":[]"# + "}").utf8).write(to: artifact)

        let status = try WhatCoverageWorkflow().run(
            WhatCoverageConfiguration(
                input: artifact.path,
                format: .llvm,
                base: base,
                comparison: .direct,
                jsonOutput: "report.json",
                minimum: try Percentage(100)
            ),
            repository: repository
        )

        #expect(status == .success)
        let json = try String(contentsOf: repository.appending(path: "report.json"), encoding: .utf8)
        #expect(json.contains(#""status" : "notApplicable""#))
    }

    private func makeRepository() throws -> URL {
        let repository = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: repository, withIntermediateDirectories: true)
        try git(["init", "-q"], at: repository)
        try git(["config", "user.email", "tests@example.com"], at: repository)
        try git(["config", "user.name", "Tests"], at: repository)
        return repository
    }

    @discardableResult
    private func git(_ arguments: [String], at repository: URL) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = arguments
        process.currentDirectoryURL = repository
        let output = Pipe()
        process.standardOutput = output
        process.standardError = output
        try process.run()
        process.waitUntilExit()
        let result = String(decoding: output.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        guard process.terminationStatus == 0 else { throw GitTestError.failed(result) }
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

private enum GitTestError: Error {
    case failed(String)
}
