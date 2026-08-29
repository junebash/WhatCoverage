import CoverageModel
import Foundation

public enum LLVMCoverageReaderError: Error, Equatable, Sendable {
    case malformedJSON(String)
    case unsupportedType(String?)
    case unsupportedVersion(String)
    case malformedSegment(file: String, index: Int)
    case invalidPath(source: String, reason: String)
    case ambiguousPath(path: RepositoryPath, sources: [String])
    case invalidCoverageModel(String)
}

public struct LLVMCoverageReader: Sendable {
    public static let exportType = "llvm.coverage.json.export"
    public static let supportedMajorVersions = Set([2])

    public init() {}

    public func read(data: Data, pathMapper: SourcePathMapper) throws -> NormalizedCoverage {
        let export: Export
        do {
            export = try JSONDecoder().decode(Export.self, from: data)
        } catch {
            throw LLVMCoverageReaderError.malformedJSON(error.localizedDescription)
        }
        guard export.type == Self.exportType else {
            throw LLVMCoverageReaderError.unsupportedType(export.type)
        }
        guard let majorText = export.version.split(separator: ".").first,
              let major = Int(majorText), Self.supportedMajorVersions.contains(major)
        else {
            throw LLVMCoverageReaderError.unsupportedVersion(export.version)
        }

        var mapped: [RepositoryPath: (source: String, counts: [Int: Int])] = [:]
        for datum in export.data {
            for file in datum.files {
                let mappedPath: RepositoryPath?
                do { mappedPath = try pathMapper.map(file.filename) }
                catch {
                    throw LLVMCoverageReaderError.invalidPath(
                        source: file.filename,
                        reason: String(describing: error)
                    )
                }
                guard let path = mappedPath else { continue }
                let counts = try lineCounts(for: file)
                if let existing = mapped[path] {
                    throw LLVMCoverageReaderError.ambiguousPath(
                        path: path,
                        sources: [existing.source, file.filename].sorted()
                    )
                }
                mapped[path] = (file.filename, counts)
            }
        }

        do {
            return try NormalizedCoverage(files: mapped.map { path, entry in
                try FileCoverage(path: path, lines: entry.counts.map { try LineCoverage(line: $0.key, executionCount: $0.value) })
            })
        } catch {
            throw LLVMCoverageReaderError.invalidCoverageModel(String(describing: error))
        }
    }

    private func lineCounts(for file: File) throws -> [Int: Int] {
        let segments = try file.segments.enumerated().map { index, values -> Segment in
            guard values.count >= 6,
                  let line = values[0].int,
                  let column = values[1].int,
                  let count = values[2].int,
                  let hasCount = values[3].bool,
                  let isGap = values[5].bool,
                  line > 0, column > 0, count >= 0
            else { throw LLVMCoverageReaderError.malformedSegment(file: file.filename, index: index) }
            return Segment(line: line, column: column, count: count, hasCount: hasCount, isGap: isGap)
        }

        var result: [Int: Int] = [:]
        for index in segments.indices.dropLast() {
            let segment = segments[index]
            let next = segments[index + 1]
            guard (next.line, next.column) > (segment.line, segment.column) else {
                throw LLVMCoverageReaderError.malformedSegment(file: file.filename, index: index + 1)
            }
            guard segment.hasCount, !segment.isGap else { continue }
            let endLine = next.line - (next.column == 1 ? 1 : 0)
            guard endLine >= segment.line else { continue }
            for line in segment.line...endLine {
                result[line] = max(result[line] ?? 0, segment.count)
            }
        }
        return result
    }
}

private struct Export: Decodable {
    let data: [Datum]
    let type: String?
    let version: String
}

private struct Datum: Decodable { let files: [File] }
private struct File: Decodable { let filename: String; let segments: [[JSONScalar]] }
private struct Segment { let line: Int; let column: Int; let count: Int; let hasCount: Bool; let isGap: Bool }

private enum JSONScalar: Decodable {
    case int(Int)
    case bool(Bool)

    init(from decoder: Decoder) throws {
        let value = try decoder.singleValueContainer()
        if let int = try? value.decode(Int.self) { self = .int(int); return }
        if let bool = try? value.decode(Bool.self) { self = .bool(bool); return }
        throw DecodingError.typeMismatch(Self.self, .init(codingPath: decoder.codingPath, debugDescription: "Expected integer or Boolean"))
    }

    var int: Int? { if case .int(let value) = self { value } else { nil } }
    var bool: Bool? { if case .bool(let value) = self { value } else { nil } }
}
