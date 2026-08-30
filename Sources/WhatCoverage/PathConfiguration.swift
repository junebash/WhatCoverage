import CoverageModel
import Foundation

public enum PathRuleAction: String, Sendable {
    case include
    case exclude
}

public struct PathRule: Sendable {
    public let pattern: String
    public let action: PathRuleAction

    public init(pattern: String, action: PathRuleAction) throws {
        try PathGlob.validate(pattern)
        self.pattern = pattern
        self.action = action
    }
}

public struct PathSelection: Sendable {
    public let rules: [PathRule]

    public init(rules: [PathRule] = []) { self.rules = rules }

    public func includes(_ path: RepositoryPath) -> Bool {
        rules.reduce(true) { selection, rule in
            PathGlob.matches(rule.pattern, path: path.value) ? rule.action == .include : selection
        }
    }

    public func filter(_ changes: ChangedLines) throws -> ChangedLines {
        try ChangedLines(files: changes.files.values.filter { includes($0.path) })
    }
}

enum PathConfigurationLoader {
    static func load(from url: URL) throws -> PathSelection {
        let text: String
        do { text = try String(contentsOf: url, encoding: .utf8) }
        catch { throw WhatCoverageError.invocation("Cannot read configuration file \(url.path): \(error.localizedDescription)") }

        var version: Int?
        var rules: [(line: Int, values: [String: String])] = []
        var currentRule: Int?
        for (index, rawLine) in text.split(omittingEmptySubsequences: false, whereSeparator: \Character.isNewline).enumerated() {
            let lineNumber = index + 1
            let line = try uncomment(String(rawLine), url: url, line: lineNumber).trimmingCharacters(in: .whitespaces)
            if line.isEmpty { continue }
            if line == "[[paths]]" {
                rules.append((lineNumber, [:]))
                currentRule = rules.count - 1
                continue
            }
            guard let equals = line.firstIndex(of: "=") else {
                throw error(url, lineNumber, "expected a key/value assignment or [[paths]]")
            }
            let key = line[..<equals].trimmingCharacters(in: .whitespaces)
            let value = line[line.index(after: equals)...].trimmingCharacters(in: .whitespaces)
            guard !key.isEmpty else { throw error(url, lineNumber, "empty key") }
            if let currentRule {
                guard key == "pattern" || key == "action" else {
                    throw error(url, lineNumber, "unknown key \(key) in paths rule \(currentRule + 1)")
                }
                guard rules[currentRule].values[key] == nil else {
                    throw error(url, lineNumber, "duplicate key \(key) in paths rule \(currentRule + 1)")
                }
                rules[currentRule].values[key] = try string(value, url: url, line: lineNumber)
            } else {
                guard key == "schema_version" else { throw error(url, lineNumber, "unknown top-level key \(key)") }
                guard version == nil else { throw error(url, lineNumber, "duplicate key schema_version") }
                guard let parsed = Int(value), !value.contains(".") else {
                    throw error(url, lineNumber, "schema_version must be an integer")
                }
                version = parsed
            }
        }
        guard let version else { throw WhatCoverageError.invocation("\(url.path): missing required schema_version") }
        guard version == 1 else { throw WhatCoverageError.invocation("\(url.path): unsupported schema_version \(version); this executable supports version 1") }
        return try PathSelection(rules: rules.enumerated().map { index, rule in
            guard let pattern = rule.values["pattern"] else { throw error(url, rule.line, "paths rule \(index + 1) is missing pattern") }
            guard let actionText = rule.values["action"] else { throw error(url, rule.line, "paths rule \(index + 1) is missing action") }
            guard let action = PathRuleAction(rawValue: actionText) else {
                throw error(url, rule.line, "paths rule \(index + 1) has unsupported action \(String(reflecting: actionText)); expected include or exclude")
            }
            do { return try PathRule(pattern: pattern, action: action) }
            catch { throw Self.error(url, rule.line, "paths rule \(index + 1) has invalid pattern \(String(reflecting: pattern)): \(error)") }
        })
    }

    private static func uncomment(_ line: String, url: URL, line number: Int) throws -> String {
        var quote: Character?
        for (index, character) in line.indices.map({ ($0, line[$0]) }) {
            if character == "\"" || character == "'" {
                if quote == character { quote = nil } else if quote == nil { quote = character }
            } else if character == "#" && quote == nil { return String(line[..<index]) }
        }
        guard quote == nil else { throw error(url, number, "unterminated string") }
        return line
    }

    private static func string(_ value: String, url: URL, line: Int) throws -> String {
        guard value.count >= 2, let first = value.first, (first == "\"" || first == "'"), value.last == first else {
            throw error(url, line, "value must be a quoted string")
        }
        let contents = String(value.dropFirst().dropLast())
        if first == "'" { return contents }
        var result = ""
        var escaped = false
        for character in contents {
            if escaped {
                guard character == "\"" || character == "\\" || character == "n" || character == "t" else { throw error(url, line, "unsupported string escape") }
                result.append(character == "n" ? "\n" : character == "t" ? "\t" : character)
                escaped = false
            } else if character == "\\" { escaped = true } else { result.append(character) }
        }
        guard !escaped else { throw error(url, line, "unterminated string escape") }
        return result
    }

    private static func error(_ url: URL, _ line: Int, _ message: String) -> WhatCoverageError {
        .invocation("\(url.path):\(line): \(message)")
    }
}

enum PathGlob {
    static func validate(_ pattern: String) throws {
        guard !pattern.isEmpty, !pattern.hasPrefix("/"), !pattern.hasPrefix("\\"), !pattern.contains("\\"),
              pattern.range(of: "^[A-Za-z]:", options: .regularExpression) == nil,
              !pattern.hasSuffix("/"), !pattern.contains("//") else { throw PatternError.malformed }
        for component in pattern.split(separator: "/", omittingEmptySubsequences: false) {
            guard component != ".", component != ".." else { throw PatternError.traversal }
            let text = String(component)
            guard text == "**" || !text.contains("**") else { throw PatternError.malformed }
        }
    }

    static func matches(_ pattern: String, path: String) -> Bool {
        let patterns = pattern.split(separator: "/").map(String.init)
        let components = path.split(separator: "/").map(String.init)
        var memo: [String: Bool] = [:]
        func match(_ patternIndex: Int, _ pathIndex: Int) -> Bool {
            let key = "\(patternIndex):\(pathIndex)"
            if let result = memo[key] { return result }
            let result: Bool
            if patternIndex == patterns.count { result = pathIndex == components.count }
            else if patterns[patternIndex] == "**" {
                result = match(patternIndex + 1, pathIndex) || (pathIndex < components.count && match(patternIndex, pathIndex + 1))
            } else {
                result = pathIndex < components.count && componentMatches(patterns[patternIndex], components[pathIndex]) && match(patternIndex + 1, pathIndex + 1)
            }
            memo[key] = result
            return result
        }
        return match(0, 0)
    }

    private static func componentMatches(_ pattern: String, _ value: String) -> Bool {
        let pattern = Array(pattern)
        let value = Array(value)
        var memo: [String: Bool] = [:]
        func match(_ i: Int, _ j: Int) -> Bool {
            let key = "\(i):\(j)"
            if let result = memo[key] { return result }
            let result: Bool
            if i == pattern.count { result = j == value.count }
            else if pattern[i] == "*" { result = match(i + 1, j) || (j < value.count && match(i, j + 1)) }
            else { result = j < value.count && (pattern[i] == "?" || pattern[i] == value[j]) && match(i + 1, j + 1) }
            memo[key] = result
            return result
        }
        return match(0, 0)
    }

    enum PatternError: Error { case malformed, traversal }
}
