import Foundation
import ReportRendering

@main
struct WhatCoveragePRComment {
    static func main() throws {
        var arguments = Array(CommandLine.arguments.dropFirst())
        guard let command = arguments.first else { throw UsageError() }
        arguments.removeFirst()
        let options = try Options(arguments)

        switch command {
        case "source-request":
            let report = try validatedReport(options)
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
            let body: String
            do {
                let report = try validatedReport(options)
                let sourceData = try Data(contentsOf: URL(fileURLWithPath: try options.value("sources")))
                let sources = try JSONDecoder().decode([String: String].self, from: sourceData)
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
            FileHandle.standardOutput.write(Data(body.data(using: .utf8)!.base64EncodedString().utf8))
            FileHandle.standardOutput.write(Data([0x0A]))
        default:
            throw UsageError()
        }
    }

    private static func validatedReport(_ options: Options) throws -> ValidatedPRCoverageReport {
        let reportURL = URL(fileURLWithPath: try options.value("report"))
        let directory = reportURL.deletingLastPathComponent()
        guard reportURL.lastPathComponent == "what-coverage-report.json",
              try FileManager.default.contentsOfDirectory(atPath: directory.path).count == 1
        else {
            throw PRCoverageCommentError.invalidReport("expected one report file")
        }
        let attributes = try FileManager.default.attributesOfItem(atPath: reportURL.path)
        guard (attributes[.size] as? NSNumber)?.intValue ?? Int.max <= 1_024 * 1_024 else {
            throw PRCoverageCommentError.invalidReport("report is too large")
        }
        return try PRCoverageReportValidator().validate(
            Data(contentsOf: reportURL),
            expectedHead: try options.value("head")
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
}

private struct UsageError: Error, CustomStringConvertible {
    let description = "usage: what-coverage-pr-comment <source-request|render> --report PATH --head SHA [--sources PATH --run-url URL]"
}
