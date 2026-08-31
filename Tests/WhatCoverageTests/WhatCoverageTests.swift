import ArgumentParser
import CoverageModel
import Foundation
import ReportRendering
import Testing
@testable import WhatCoverage

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
        #expect(throws: Error.self) {
            _ = try WhatCoverageCommand.parseAsRoot([
                "--input", "coverage.json", "--base", "HEAD", "--base-format", "llvm", "--json-output", "report.json",
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
        let head = try git(["rev-parse", "HEAD"], at: repository)

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
        #expect(json.contains(#""wholeProjectCoverage""#))
        #expect(json.contains(#""executable" : 1"#))
        #expect(!json.contains(#""coverageDelta""#))
        let validated = try PRCoverageReportValidator().validate(Data(json.utf8), expectedHead: head)
        let comment = try PRCoverageCommentRenderer().render(validated)
        #expect(comment.contains("**Diff coverage:** 0.00% (0/1 executable lines)"))
        #expect(comment.contains("**Whole-project coverage:** 0.00% (0/1 executable lines)"))
        #expect(!comment.localizedCaseInsensitiveContains("delta"))
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

    @Test func workflowReportsTwoArtifactDeltaIndependentlyFromPathSelectionAndPolicy() throws {
        let repository = try makeRepository()
        defer { try? FileManager.default.removeItem(at: repository) }
        try Data("base\n".utf8).write(to: repository.appending(path: "App.swift"))
        try git(["add", "."], at: repository)
        try git(["commit", "-m", "base"], at: repository)
        let baseRevision = try git(["rev-parse", "HEAD"], at: repository)
        try Data("head\n".utf8).write(to: repository.appending(path: "App.swift"))
        try git(["commit", "-am", "head"], at: repository)

        let baseArtifact = repository.appending(path: "base.json")
        let headArtifact = repository.appending(path: "head.json")
        try Data(llvmArtifact(root: "/base", count: 0).utf8).write(to: baseArtifact)
        try Data(llvmArtifact(root: "/head", count: 1).utf8).write(to: headArtifact)

        let status = try WhatCoverageWorkflow().run(
            WhatCoverageConfiguration(
                input: headArtifact.path,
                format: .llvm,
                base: baseRevision,
                comparison: .direct,
                capturedSourceRoot: "/head",
                baseInput: baseArtifact.path,
                baseFormat: .llvm,
                baseCapturedSourceRoot: "/base",
                jsonOutput: "report.json",
                minimum: try Percentage(100),
                pathSelection: try PathSelection(rules: [PathRule(pattern: "**", action: .exclude)])
            ),
            repository: repository
        )

        #expect(status == .success)
        let report = try String(contentsOf: repository.appending(path: "report.json"), encoding: .utf8)
        #expect(report.contains(#""coverageDelta""#))
        #expect(report.contains(#""percentagePointChange" : 100"#))
        #expect(report.contains(#""wholeProjectCoverage""#))
        #expect(report.contains(#""status" : "notApplicable""#))

        let scopedStatus = try WhatCoverageWorkflow().run(
            WhatCoverageConfiguration(
                input: headArtifact.path,
                format: .llvm,
                base: baseRevision,
                comparison: .direct,
                capturedSourceRoot: "/head",
                baseInput: baseArtifact.path,
                baseFormat: .llvm,
                baseCapturedSourceRoot: "/base",
                markdownOutput: "scoped.md",
                jsonOutput: "scoped.json",
                pathSelection: try PathSelection(rules: [PathRule(pattern: "**", action: .exclude)]),
                pathScope: PathScope(wholeProject: true, coverageDelta: true)
            ),
            repository: repository
        )
        #expect(scopedStatus == .success)
        let scopedData = try Data(contentsOf: repository.appending(path: "scoped.json"))
        let scoped = try #require(try JSONSerialization.jsonObject(with: scopedData) as? [String: Any])
        let wholeProject = try #require(scoped["wholeProjectCoverage"] as? [String: Any])
        let delta = try #require(scoped["coverageDelta"] as? [String: Any])
        let project = try #require(delta["project"] as? [String: Any])
        let deltaBase = try #require(project["base"] as? [String: Any])
        let deltaHead = try #require(project["head"] as? [String: Any])
        #expect(wholeProject["executable"] as? Int == 0)
        #expect(deltaBase["executable"] as? Int == 0)
        #expect(deltaHead["executable"] as? Int == 0)
        #expect(try String(contentsOf: repository.appending(path: "scoped.md"), encoding: .utf8).contains("**Project:** N/A (0/0) → N/A (0/0) (N/A)"))
    }

    @Test func orderedPathRulesUseLastMatchingRuleAndGlobComponents() throws {
        let selection = try PathSelection(rules: [
            PathRule(pattern: "Sources/**/*.swift", action: .include),
            PathRule(pattern: "**/Generated/**", action: .exclude),
            PathRule(pattern: "Sources/Generated/Important.swift", action: .include),
        ])
        #expect(selection.includes(try RepositoryPath("Sources/App.swift")))
        #expect(!selection.includes(try RepositoryPath("Sources/Generated/Code.swift")))
        #expect(selection.includes(try RepositoryPath("Sources/Generated/Important.swift")))
        #expect(selection.includes(try RepositoryPath("README.md")))
        #expect(try PathSelection(rules: [PathRule(pattern: "**/*.swift", action: .exclude)]).includes(RepositoryPath("App.swift")) == false)
        #expect(try PathSelection(rules: [PathRule(pattern: "file?.swift", action: .exclude)]).includes(RepositoryPath("file😀.swift")) == false)
        #expect(try PathSelection(rules: [PathRule(pattern: "notes [v1]#.swift", action: .exclude)]).includes(RepositoryPath("notes [v1]#.swift")) == false)
    }

    @Test func versionTwoBarePathsMatchDirectoryTreesWithoutChangingVersionOnePatterns() throws {
        let repository = try makeRepository()
        defer { try? FileManager.default.removeItem(at: repository) }
        let configuration = repository.appending(path: ".whatcoverage.toml")

        try Data("schema_version = 1\n[[paths]]\npattern = \"Tests\"\naction = \"exclude\"\n".utf8).write(to: configuration)
        let versionOne = try WhatCoverageCommand.fileConfiguration(config: nil, noConfig: false, repository: repository)
        #expect(versionOne.pathSelection.includes(try RepositoryPath("Tests/AppTests.swift")))

        try Data("schema_version = 2\n[[paths]]\npattern = \"Tests\"\naction = \"exclude\"\n".utf8).write(to: configuration)
        let bare = try WhatCoverageCommand.fileConfiguration(config: nil, noConfig: false, repository: repository)
        #expect(!bare.pathSelection.includes(try RepositoryPath("Tests/AppTests.swift")))

        for pattern in ["Tests/**", "Tests/**/*"] {
            try Data("schema_version = 2\n[[paths]]\npattern = \"\(pattern)\"\naction = \"exclude\"\n".utf8).write(to: configuration)
            let globbed = try WhatCoverageCommand.fileConfiguration(config: nil, noConfig: false, repository: repository)
            #expect(!globbed.pathSelection.includes(try RepositoryPath("Tests/AppTests.swift")))
        }
    }

    @Test func importsContinuedSonarPropertiesBeforeExplicitOverrides() throws {
        let repository = try makeRepository()
        defer { try? FileManager.default.removeItem(at: repository) }
        try Data("""
        sonar.sources=RedzoneApps,\
          SharedLibraries
        sonar.tests=Tests,SharedLibraries/Tests
        sonar.exclusions=SharedLibraries/Package.swift
        sonar.coverage.exclusions=**/Generated/**,\
          **/*ViewController.swift
        sonar.projectKey=ignored
        sonar.projectName=Redzone\\ iOS
        """.utf8).write(to: repository.appending(path: "sonar-project.properties"))
        try Data("""
        schema_version = 2
        [path_scope]
        changed_lines = true
        whole_project = true
        coverage_delta = true
        [sonar]
        properties_file = "sonar-project.properties"
        use_sources_as_allowlist = true
        use_exclusions = true
        use_coverage_exclusions = true
        use_test_paths_as_exclusions = true
        [[paths]]
        pattern = "RedzoneApps/Generated/Important.swift"
        action = "include"
        """.utf8).write(to: repository.appending(path: ".whatcoverage.toml"))

        let configuration = try WhatCoverageCommand.fileConfiguration(config: nil, noConfig: false, repository: repository)

        #expect(configuration.pathScope.changedLines)
        #expect(configuration.pathScope.wholeProject)
        #expect(configuration.pathScope.coverageDelta)
        #expect(configuration.pathSelection.includes(try RepositoryPath("RedzoneApps/App.swift")))
        #expect(configuration.pathSelection.includes(try RepositoryPath("SharedLibraries/Core/App.swift")))
        #expect(!configuration.pathSelection.includes(try RepositoryPath("Other/App.swift")))
        #expect(!configuration.pathSelection.includes(try RepositoryPath("Tests/AppTests.swift")))
        #expect(!configuration.pathSelection.includes(try RepositoryPath("SharedLibraries/Tests/CoreTests.swift")))
        #expect(!configuration.pathSelection.includes(try RepositoryPath("SharedLibraries/Package.swift")))
        #expect(!configuration.pathSelection.includes(try RepositoryPath("RedzoneApps/Feature/Generated/API.swift")))
        #expect(!configuration.pathSelection.includes(try RepositoryPath("RedzoneApps/HomeViewController.swift")))
        #expect(configuration.pathSelection.includes(try RepositoryPath("RedzoneApps/Generated/Important.swift")))
    }

    @Test func sonarImportReportsMissingFilesAndUnsupportedPatterns() throws {
        let repository = try makeRepository()
        defer { try? FileManager.default.removeItem(at: repository) }
        let configuration = repository.appending(path: ".whatcoverage.toml")
        try Data("schema_version = 2\n[sonar]\nproperties_file = \"missing.properties\"\nuse_coverage_exclusions = true\n".utf8).write(to: configuration)
        #expect(throws: WhatCoverageError.self) {
            try WhatCoverageCommand.fileConfiguration(config: nil, noConfig: false, repository: repository)
        }

        try Data("sonar.coverage.exclusions=**/*.{swift,m}\n".utf8).write(to: repository.appending(path: "sonar-project.properties"))
        try Data("schema_version = 2\n[sonar]\nproperties_file = \"sonar-project.properties\"\nuse_coverage_exclusions = true\n".utf8).write(to: configuration)
        #expect(throws: WhatCoverageError.self) {
            try WhatCoverageCommand.fileConfiguration(config: nil, noConfig: false, repository: repository)
        }
    }

    @Test func rejectsUnsafeAndMalformedPathPatterns() {
        for pattern in ["", "/absolute", "C:/drive", "a/../b", "a//b", "a/***/b", "a/foo**bar", "a\\b"] {
            #expect(throws: Error.self) { _ = try PathRule(pattern: pattern, action: .include) }
        }
    }

    @Test func loadsStrictVersionedConfigurationAndHonorsDiscoveryOverrides() throws {
        let repository = try makeRepository()
        defer { try? FileManager.default.removeItem(at: repository) }
        let automatic = repository.appending(path: ".whatcoverage.toml")
        try Data("""
        schema_version = 1
        minimum = 60
        [[paths]]
        pattern = "**"
        action = "exclude"
        [[paths]]
        pattern = "Sources/**"
        action = "include"
        """.utf8).write(to: automatic)
        let configuration = try WhatCoverageCommand.fileConfiguration(config: nil, noConfig: false, repository: repository)
        let expectedMinimum = try Percentage(60)
        #expect(configuration.minimum == expectedMinimum)
        #expect(configuration.pathSelection.includes(try RepositoryPath("Sources/App.swift")))
        #expect(!configuration.pathSelection.includes(try RepositoryPath("Tests/AppTests.swift")))
        let disabled = try WhatCoverageCommand.fileConfiguration(config: nil, noConfig: true, repository: repository)
        #expect(disabled.minimum == nil)
        #expect(disabled.pathSelection.includes(try RepositoryPath("Tests/AppTests.swift")))
        #expect(throws: WhatCoverageError.self) { try WhatCoverageCommand.fileConfiguration(config: "missing.toml", noConfig: false, repository: repository) }
        try Data("schema_version = 1\nunknown = true\n".utf8).write(to: automatic)
        #expect(throws: WhatCoverageError.self) { try WhatCoverageCommand.fileConfiguration(config: nil, noConfig: false, repository: repository) }
    }

    @Test func rejectsInvalidConfiguredMinimums() throws {
        let repository = try makeRepository()
        defer { try? FileManager.default.removeItem(at: repository) }
        let configuration = repository.appending(path: ".whatcoverage.toml")
        for minimum in ["-1", "101", "nan", "\"60\""] {
            try Data("schema_version = 1\nminimum = \(minimum)\n".utf8).write(to: configuration)
            #expect(throws: WhatCoverageError.self) {
                try WhatCoverageCommand.fileConfiguration(config: nil, noConfig: false, repository: repository)
            }
        }
        for minimum in ["0", "100"] {
            try Data("schema_version = 1\nminimum = \(minimum)\n".utf8).write(to: configuration)
            #expect(try WhatCoverageCommand.fileConfiguration(config: nil, noConfig: false, repository: repository).minimum?.value == Double(minimum))
        }
    }

    @Test func pathSelectionChangesTotalsAndCanMakeCoverageNotApplicable() throws {
        let repository = try makeRepository()
        defer { try? FileManager.default.removeItem(at: repository) }
        for path in ["Sources/Covered.swift", "Generated/Uncovered.swift"] {
            let file = repository.appending(path: path)
            try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data("base\n".utf8).write(to: file)
        }
        try git(["add", "."], at: repository)
        try git(["commit", "-m", "base"], at: repository)
        let base = try git(["rev-parse", "HEAD"], at: repository)
        try Data("base\nchanged\n".utf8).write(to: repository.appending(path: "Sources/Covered.swift"))
        try Data("base\nchanged\n".utf8).write(to: repository.appending(path: "Generated/Uncovered.swift"))
        try git(["commit", "-am", "head"], at: repository)
        let artifact = repository.appending(path: "coverage.json")
        try Data(#"{"type":"llvm.coverage.json.export","version":"2.0.0","data":[{"files":[{"filename":"/captured/Sources/Covered.swift","segments":[[2,1,1,true,true,false],[3,1,0,false,true,false]]},{"filename":"/captured/Generated/Uncovered.swift","segments":[[2,1,0,true,true,false],[3,1,0,false,true,false]]}]}]}"#.utf8).write(to: artifact)
        let selection = try PathSelection(rules: [PathRule(pattern: "Generated/**", action: .exclude)])
        let status = try WhatCoverageWorkflow().run(WhatCoverageConfiguration(input: artifact.path, format: .llvm, base: base, comparison: .direct, capturedSourceRoot: "/captured", jsonOutput: "report.json", minimum: try Percentage(100), pathSelection: selection), repository: repository)
        #expect(status == .success)
        let json = try String(contentsOf: repository.appending(path: "report.json"), encoding: .utf8)
        #expect(json.contains("Sources/Covered.swift"))
        #expect(!json.contains("Generated/Uncovered.swift"))
        let jsonObject = try #require(try JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any])
        let wholeProject = try #require(jsonObject["wholeProjectCoverage"] as? [String: Any])
        #expect(wholeProject["executable"] as? Int == 2)
        #expect(wholeProject["covered"] as? Int == 1)

        let scopedStatus = try WhatCoverageWorkflow().run(WhatCoverageConfiguration(input: artifact.path, format: .llvm, base: base, comparison: .direct, capturedSourceRoot: "/captured", markdownOutput: "scoped.md", jsonOutput: "scoped.json", minimum: try Percentage(100), pathSelection: selection, pathScope: PathScope(wholeProject: true)), repository: repository)
        #expect(scopedStatus == .success)
        let scopedData = try Data(contentsOf: repository.appending(path: "scoped.json"))
        let scopedObject = try #require(try JSONSerialization.jsonObject(with: scopedData) as? [String: Any])
        let scopedWholeProject = try #require(scopedObject["wholeProjectCoverage"] as? [String: Any])
        #expect(scopedWholeProject["executable"] as? Int == 1)
        #expect(scopedWholeProject["covered"] as? Int == 1)
        #expect(try String(contentsOf: repository.appending(path: "scoped.md"), encoding: .utf8).contains("**Whole-project coverage:** 100.00% (1/1)"))
        let validated = try PRCoverageReportValidator().validate(scopedData, expectedHead: try git(["rev-parse", "HEAD"], at: repository))
        #expect(try PRCoverageCommentRenderer().render(validated).contains("**Whole-project coverage:** 100.00% (1/1 executable lines)"))

        let emptyStatus = try WhatCoverageWorkflow().run(WhatCoverageConfiguration(input: artifact.path, format: .llvm, base: base, comparison: .direct, capturedSourceRoot: "/captured", markdownOutput: "empty.md", jsonOutput: "empty.json", minimum: try Percentage(100), pathSelection: try PathSelection(rules: [PathRule(pattern: "**", action: .exclude)]), pathScope: PathScope(wholeProject: true)), repository: repository)
        #expect(emptyStatus == .success)
        let emptyJSON = try String(contentsOf: repository.appending(path: "empty.json"), encoding: .utf8)
        #expect(emptyJSON.contains(#""status" : "notApplicable""#))
        #expect(emptyJSON.contains(#""executable" : 0"#))
        #expect(!emptyJSON.contains(#""percentage""#))
        #expect(try String(contentsOf: repository.appending(path: "empty.md"), encoding: .utf8).contains("**Whole-project coverage:** N/A (0/0)"))
    }

    private func makeRepository() throws -> URL {
        let repository = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: repository, withIntermediateDirectories: true)
        try git(["init", "-q"], at: repository)
        try git(["config", "user.email", "tests@example.com"], at: repository)
        try git(["config", "user.name", "Tests"], at: repository)
        try git(["config", "commit.gpgsign", "false"], at: repository)
        return repository
    }

    private func llvmArtifact(root: String, count: Int) -> String {
        #"{"type":"llvm.coverage.json.export","version":"2.0.0","data":[{"files":[{"filename":""#
            + root
            + #"/App.swift","segments":[[1,1,"#
            + String(count)
            + #",true,true,false],[2,1,0,false,true,false]]}]}]}"#
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
