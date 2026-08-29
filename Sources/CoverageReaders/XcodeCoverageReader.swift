import CoverageModel
import Foundation
import ProcessSupport

public enum XcodeCoverageReaderError: Error, Equatable, Sendable, CustomStringConvertible {
    case toolUnavailable(String)
    case invalidResultBundle(path: String, detail: String)
    case missingCoverage(path: String)
    case multipleCoverageArchives(path: String, count: Int)
    case malformedResultBundleMetadata(String)
    case processFailed(String)
    case xccovFailed(path: String, exitCode: Int32, detail: String)
    case malformedJSON(String)
    case malformedLine(source: String, index: Int)
    case invalidPath(source: String, reason: String)
    case ambiguousPath(path: RepositoryPath, sources: [String])
    case invalidCoverageModel(String)

    public var description: String {
        switch self {
        case .toolUnavailable(let detail):
            return "Xcode coverage tools are unavailable: \(detail). Select an Xcode toolchain with xcode-select."
        case .invalidResultBundle(let path, let detail):
            return "Could not read Xcode result bundle at \(path): \(detail). Regenerate a complete .xcresult bundle."
        case .missingCoverage(let path):
            return "The Xcode result bundle at \(path) has no coverage archive. Run tests with code coverage enabled."
        case .multipleCoverageArchives(let path, let count):
            return "The Xcode result bundle at \(path) contains \(count) coverage archives. Provide a bundle with exactly one test action; implicit xccov selection is not deterministic."
        case .malformedResultBundleMetadata(let detail):
            return "xcresulttool returned metadata WhatCoverage could not parse: \(detail)."
        case .processFailed(let detail):
            return "Could not run the Xcode coverage tools: \(detail)."
        case .xccovFailed(let path, let exitCode, let detail):
            return "xccov could not read coverage from \(path) (exit \(exitCode)): \(detail). Regenerate the result bundle with coverage enabled."
        case .malformedJSON(let detail):
            return "xccov returned malformed archive JSON: \(detail)."
        case .malformedLine(let source, let index):
            return "xccov returned an invalid line record at index \(index) for \(source)."
        case .invalidPath(let source, let reason):
            return "Could not map Xcode coverage path \(source): \(reason)."
        case .ambiguousPath(let path, let sources):
            return "Multiple Xcode source paths map to \(path.value): \(sources.joined(separator: ", "))."
        case .invalidCoverageModel(let detail):
            return "Xcode coverage could not be normalized: \(detail)."
        }
    }
}

public struct XcodeCoverageReader<Runner: ProcessRunning>: Sendable {
    private let runner: Runner

    public init(runner: Runner) {
        self.runner = runner
    }

    public func read(resultBundle: URL, pathMapper: SourcePathMapper) throws -> NormalizedCoverage {
        let workingDirectory = URL(fileURLWithPath: pathMapper.repositoryRoot, isDirectory: true)
        let metadata = try run(
            arguments: ["xcresulttool", "get", "object", "--legacy", "--path", resultBundle.path, "--format", "json"],
            currentDirectory: workingDirectory,
            resultBundle: resultBundle,
            operation: .metadata
        )
        let archiveCount: Int
        do {
            let record = try JSONDecoder().decode(ActionsInvocationRecord.self, from: metadata.standardOutput)
            archiveCount = Set(record.actions.values.compactMap(\.actionResult?.coverage?.archiveRef?.id?.value)).count
        } catch {
            throw XcodeCoverageReaderError.malformedResultBundleMetadata(error.localizedDescription)
        }
        guard archiveCount > 0 else {
            throw XcodeCoverageReaderError.missingCoverage(path: resultBundle.path)
        }
        guard archiveCount == 1 else {
            throw XcodeCoverageReaderError.multipleCoverageArchives(path: resultBundle.path, count: archiveCount)
        }

        let archive = try run(
            arguments: ["xccov", "view", "--archive", "--json", resultBundle.path],
            currentDirectory: workingDirectory,
            resultBundle: resultBundle,
            operation: .archive
        )
        return try normalize(archive.standardOutput, pathMapper: pathMapper)
    }

    private func normalize(_ data: Data, pathMapper: SourcePathMapper) throws -> NormalizedCoverage {
        let archive: [String: [ArchiveLine]]
        do {
            archive = try JSONDecoder().decode([String: [ArchiveLine]].self, from: data)
        } catch {
            throw XcodeCoverageReaderError.malformedJSON(error.localizedDescription)
        }

        var mapped: [RepositoryPath: (source: String, lines: [LineCoverage])] = [:]
        for source in archive.keys.sorted() {
            let path: RepositoryPath?
            do { path = try pathMapper.map(source) }
            catch {
                throw XcodeCoverageReaderError.invalidPath(source: source, reason: String(describing: error))
            }
            guard let path else { continue }
            if let existing = mapped[path] {
                throw XcodeCoverageReaderError.ambiguousPath(
                    path: path,
                    sources: [existing.source, source].sorted()
                )
            }
            let records = archive[source] ?? []
            var lines: [LineCoverage] = []
            for (index, record) in records.enumerated() {
                guard record.line > 0, record.executionCount.map({ $0 >= 0 }) ?? true else {
                    throw XcodeCoverageReaderError.malformedLine(source: source, index: index)
                }
                guard record.isExecutable else { continue }
                guard let count = record.executionCount else {
                    throw XcodeCoverageReaderError.malformedLine(source: source, index: index)
                }
                do { lines.append(try LineCoverage(line: record.line, executionCount: count)) }
                catch { throw XcodeCoverageReaderError.malformedLine(source: source, index: index) }
            }
            mapped[path] = (source, lines)
        }

        do {
            return try NormalizedCoverage(files: mapped.keys.sorted().map { path in
                try FileCoverage(path: path, lines: mapped[path]?.lines ?? [])
            })
        } catch {
            throw XcodeCoverageReaderError.invalidCoverageModel(String(describing: error))
        }
    }

    private enum Operation { case metadata; case archive }

    private func run(
        arguments: [String],
        currentDirectory: URL,
        resultBundle: URL,
        operation: Operation
    ) throws -> ProcessResult {
        let result: ProcessResult
        do { result = try runner.run(command: "xcrun", arguments: arguments, currentDirectory: currentDirectory) }
        catch { throw XcodeCoverageReaderError.processFailed(String(describing: error)) }
        guard result.exitCode == 0 else {
            let detail = result.standardError.isEmpty ? "exit status \(result.exitCode)" : result.standardError
            let unavailable = detail.localizedCaseInsensitiveContains("unable to find utility")
                || detail.localizedCaseInsensitiveContains("command not found")
                || (result.exitCode == 127 && detail.localizedCaseInsensitiveContains("no such file or directory"))
            if unavailable { throw XcodeCoverageReaderError.toolUnavailable(detail) }
            switch operation {
            case .metadata:
                throw XcodeCoverageReaderError.invalidResultBundle(path: resultBundle.path, detail: detail)
            case .archive:
                throw XcodeCoverageReaderError.xccovFailed(
                    path: resultBundle.path,
                    exitCode: result.exitCode,
                    detail: detail
                )
            }
        }
        return result
    }
}

public extension XcodeCoverageReader where Runner == FoundationProcessRunner {
    init() { self.init(runner: FoundationProcessRunner()) }
}

private struct ActionsInvocationRecord: Decodable {
    let actions: Values<Action>
}

private struct Values<Value: Decodable>: Decodable {
    let values: [Value]

    enum CodingKeys: String, CodingKey { case values = "_values" }
}

private struct Action: Decodable {
    let actionResult: ActionResult?
}

private struct ActionResult: Decodable {
    let coverage: CoverageReference?
}

private struct CoverageReference: Decodable {
    let archiveRef: Reference?
}

private struct Reference: Decodable {
    let id: WrappedString?
}

private struct WrappedString: Decodable {
    let value: String

    enum CodingKeys: String, CodingKey { case value = "_value" }
}

private struct ArchiveLine: Decodable {
    let line: Int
    let isExecutable: Bool
    let executionCount: Int?
}
