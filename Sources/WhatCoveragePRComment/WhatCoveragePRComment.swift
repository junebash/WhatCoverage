import Foundation
import ReportRendering

#if os(Linux)
import Glibc
#else
import Darwin
#endif

@main
struct WhatCoveragePRComment {
    static func main() {
        do {
            try run()
        } catch {
            FileHandle.standardError.write(Data("Error: \(error)\n".utf8))
            exit(64)
        }
    }

    private static func run() throws {
        var arguments = Array(CommandLine.arguments.dropFirst())
        if arguments == ["--help"] || arguments == ["-h"] {
            print(UsageError().description)
            return
        }
        guard let command = arguments.first else { throw UsageError() }
        arguments.removeFirst()
        let options = try Options(arguments)

        switch command {
        case "source-request":
            let report = try validatedReport(options, strictArtifactLayout: true)
            let limits = PRCoverageCommentLimits.standard
            let value: [String: Any] = [
                "paths": report.sourceRequestPaths,
                "sourceFiles": limits.sourceFiles,
                "sourceBytesPerFile": limits.sourceBytesPerFile,
                "sourceBytesTotal": limits.sourceBytesTotal,
            ]
            let data = try JSONSerialization.data(withJSONObject: value, options: [.sortedKeys])
            FileHandle.standardOutput.write(data)
            FileHandle.standardOutput.write(Data([0x0A]))
        case "render":
            let usesLocalCheckout = options.has("repo-root")
            guard usesLocalCheckout != options.has("sources"),
                  usesLocalCheckout == options.has("output")
            else {
                throw UsageError()
            }
            let body: String
            do {
                let report = try validatedReport(options, strictArtifactLayout: !usesLocalCheckout)
                let sources: [String: String]
                if usesLocalCheckout {
                    sources = LocalPRCoverageSourceLoader().load(
                        for: report,
                        repositoryRoot: URL(fileURLWithPath: try options.value("repo-root"))
                    )
                } else {
                    let sourceData = try Data(contentsOf: URL(fileURLWithPath: try options.value("sources")))
                    sources = try JSONDecoder().decode([String: String].self, from: sourceData)
                }
                var rendered = try PRCoverageCommentRenderer().render(report, sources: sources)
                if let placeholder = rendered.range(of: "RUN_URL") {
                    rendered.replaceSubrange(placeholder, with: try options.value("run-url"))
                }
                body = rendered
            } catch {
                let runURL = try options.value("run-url")
                FileHandle.standardError.write(Data("Rendering a fallback coverage comment: \(error)\n".utf8))
                body = "<!-- whatcoverage:pr-report:v1 -->\n## WhatCoverage\n\n⚠️ Coverage did not produce a valid report. [View the workflow run](\(runURL))."
            }
            if usesLocalCheckout {
                try Data((body + "\n").utf8).write(to: URL(fileURLWithPath: try options.value("output")))
            } else {
                FileHandle.standardOutput.write(Data(body.data(using: .utf8)!.base64EncodedString().utf8))
                FileHandle.standardOutput.write(Data([0x0A]))
            }
        default:
            throw UsageError()
        }
    }

    private static func validatedReport(_ options: Options, strictArtifactLayout: Bool) throws -> ValidatedPRCoverageReport {
        let reportURL = URL(fileURLWithPath: try options.value("report"))
        if strictArtifactLayout {
            let directory = reportURL.deletingLastPathComponent()
            guard reportURL.lastPathComponent == "what-coverage-report.json",
                  try FileManager.default.contentsOfDirectory(atPath: directory.path).count == 1
            else {
                throw PRCoverageCommentError.invalidReport("expected one report file")
            }
        }
        let attributes = try FileManager.default.attributesOfItem(atPath: reportURL.path)
        guard (attributes[.size] as? NSNumber)?.intValue ?? Int.max <= 1_024 * 1_024 else {
            throw PRCoverageCommentError.invalidReport("report is too large")
        }
        return try PRCoverageReportValidator().validate(
            Data(contentsOf: reportURL),
            expectedHead: try options.value("head"),
            requiredInputKind: strictArtifactLayout ? .llvm : nil
        )
    }
}

private struct Options {
    private let values: [String: String]

    init(_ arguments: [String]) throws {
        guard arguments.count.isMultiple(of: 2) else { throw UsageError() }
        var values: [String: String] = [:]
        for index in stride(from: 0, to: arguments.count, by: 2) {
            let name = arguments[index]
            guard name.hasPrefix("--"), values.updateValue(arguments[index + 1], forKey: String(name.dropFirst(2))) == nil else {
                throw UsageError()
            }
        }
        self.values = values
    }

    func value(_ name: String) throws -> String {
        guard let value = values[name] else { throw UsageError() }
        return value
    }

    func has(_ name: String) -> Bool { values[name] != nil }
}

private struct UsageError: Error, CustomStringConvertible {
    let description = """
    usage:
      what-coverage-pr-comment source-request --report PATH --head SHA
      what-coverage-pr-comment render --report PATH --head SHA --sources PATH --run-url URL
      what-coverage-pr-comment render --report PATH --head SHA --repo-root PATH --run-url URL --output PATH
    """
}
