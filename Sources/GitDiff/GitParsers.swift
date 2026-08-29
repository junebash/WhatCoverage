import CoverageModel
import Foundation

public enum GitParseError: Error, Equatable, Sendable {
    case malformedRawRecord(String)
    case missingPath(String)
    case invalidPath(String)
    case malformedHunk(String)
}

public struct GitRawChange: Equatable, Sendable {
    public let status: Character
    public let oldMode: String
    public let newMode: String
    public let oldPath: String?
    public let newPath: String?
}

public enum GitRawDiffParser {
    public static func parse(_ data: Data) throws -> [GitRawChange] {
        let fields = try data.split(separator: 0, omittingEmptySubsequences: false).map { field -> String in
            guard let value = String(data: field, encoding: .utf8) else {
                throw GitParseError.invalidPath("Git path is not valid UTF-8")
            }
            return value
        }
        var index = 0
        var changes: [GitRawChange] = []
        while index < fields.count, !fields[index].isEmpty {
            let metadata = fields[index]
            index += 1
            let parts = metadata.split(separator: " ")
            guard parts.count == 5, parts[0].hasPrefix(":"), let status = parts[4].first else {
                throw GitParseError.malformedRawRecord(metadata)
            }
            guard index < fields.count, !fields[index].isEmpty else { throw GitParseError.missingPath(metadata) }
            let firstPath = fields[index]
            index += 1
            let oldPath: String?
            let newPath: String?
            if status == "R" || status == "C" {
                guard index < fields.count, !fields[index].isEmpty else { throw GitParseError.missingPath(metadata) }
                oldPath = firstPath
                newPath = fields[index]
                index += 1
            } else if status == "D" {
                oldPath = firstPath
                newPath = nil
            } else {
                oldPath = nil
                newPath = firstPath
            }
            changes.append(GitRawChange(
                status: status,
                oldMode: String(parts[0].dropFirst()),
                newMode: String(parts[1]),
                oldPath: oldPath,
                newPath: newPath
            ))
        }
        return changes
    }
}

public enum UnifiedDiffParser {
    public static func addedLines(_ patch: String) throws -> Set<Int> {
        var result: Set<Int> = []
        for line in patch.split(separator: "\n", omittingEmptySubsequences: false) where line.hasPrefix("@@") {
            guard let plus = line.firstIndex(of: "+"),
                  let end = line[plus...].firstIndex(of: " ")
            else { throw GitParseError.malformedHunk(String(line)) }
            let range = line[line.index(after: plus)..<end].split(separator: ",", omittingEmptySubsequences: false)
            guard (1...2).contains(range.count),
                  let start = Int(range[0]), start >= 0,
                  let count = range.count == 1 ? 1 : Int(range[1]),
                  count >= 0
            else { throw GitParseError.malformedHunk(String(line)) }
            if count > 0 {
                guard start > 0 else { throw GitParseError.malformedHunk(String(line)) }
                result.formUnion(start..<(start + count))
            }
        }
        return result
    }
}
