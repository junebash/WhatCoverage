import CoverageModel
import Foundation

public enum PathRuleAction: String, Sendable {
    case include
    case exclude
}

public struct PathRule: Sendable {
    public let pattern: String
    public let action: PathRuleAction

    private let matchingPattern: String

    public init(pattern: String, action: PathRuleAction) throws {
        try self.init(pattern: pattern, action: action, directoryTree: false)
    }

    init(pattern: String, action: PathRuleAction, directoryTree: Bool) throws {
        try PathGlob.validate(pattern)
        self.pattern = pattern
        self.action = action
        matchingPattern = directoryTree && !pattern.contains("*") && !pattern.contains("?")
            ? pattern + "/**"
            : pattern
    }

    fileprivate func matches(_ path: RepositoryPath) -> Bool {
        PathGlob.matches(matchingPattern, path: path.value)
    }
}

public struct PathSelection: Sendable {
    public let rules: [PathRule]

    public init(rules: [PathRule] = []) { self.rules = rules }

    public func includes(_ path: RepositoryPath) -> Bool {
        rules.reduce(true) { selection, rule in
            rule.matches(path) ? rule.action == .include : selection
        }
    }

    public func filter(_ changes: ChangedLines) throws -> ChangedLines {
        try ChangedLines(files: changes.files.values.filter { includes($0.path) })
    }

    public func filter(_ coverage: NormalizedCoverage) throws -> NormalizedCoverage {
        try NormalizedCoverage(files: coverage.files.values.filter { includes($0.path) })
    }
}

public struct PathScope: Sendable {
    public let changedLines: Bool
    public let wholeProject: Bool
    public let coverageDelta: Bool

    public init(changedLines: Bool = true, wholeProject: Bool = false, coverageDelta: Bool = false) {
        self.changedLines = changedLines
        self.wholeProject = wholeProject
        self.coverageDelta = coverageDelta
    }
}

struct RepositoryConfiguration: Sendable {
    let minimum: Percentage?
    let pathSelection: PathSelection
    let pathScope: PathScope

    init(
        minimum: Percentage? = nil,
        pathSelection: PathSelection = PathSelection(),
        pathScope: PathScope = PathScope()
    ) {
        self.minimum = minimum
        self.pathSelection = pathSelection
        self.pathScope = pathScope
    }
}

enum PathConfigurationLoader {
    static func load(from url: URL) throws -> RepositoryConfiguration {
        let text: String
        do { text = try String(contentsOf: url, encoding: .utf8) }
        catch { throw WhatCoverageError.invocation("Cannot read configuration file \(url.path): \(error.localizedDescription)") }

        var version: Int?
        var minimum: Percentage?
        var hasMinimum = false
        var rules: [(line: Int, values: [String: String])] = []
        var section = Section.topLevel
        var pathScope: [String: Bool] = [:]
        var sonar: [String: String] = [:]
        for (index, rawLine) in text.split(omittingEmptySubsequences: false, whereSeparator: \Character.isNewline).enumerated() {
            let lineNumber = index + 1
            let line = try uncomment(String(rawLine), url: url, line: lineNumber).trimmingCharacters(in: .whitespaces)
            if line.isEmpty { continue }
            if line == "[[paths]]" {
                rules.append((lineNumber, [:]))
                section = .pathRule(rules.count - 1)
                continue
            }
            if line == "[path_scope]" {
                section = .pathScope
                continue
            }
            if line == "[sonar]" {
                section = .sonar
                continue
            }
            guard let equals = line.firstIndex(of: "=") else {
                throw error(url, lineNumber, "expected a key/value assignment or supported table header")
            }
            let key = line[..<equals].trimmingCharacters(in: .whitespaces)
            let value = line[line.index(after: equals)...].trimmingCharacters(in: .whitespaces)
            guard !key.isEmpty else { throw error(url, lineNumber, "empty key") }
            switch section {
            case .pathRule(let currentRule):
                guard key == "pattern" || key == "action" else {
                    throw error(url, lineNumber, "unknown key \(key) in paths rule \(currentRule + 1)")
                }
                guard rules[currentRule].values[key] == nil else {
                    throw error(url, lineNumber, "duplicate key \(key) in paths rule \(currentRule + 1)")
                }
                rules[currentRule].values[key] = try string(value, url: url, line: lineNumber)
            case .pathScope:
                guard ["changed_lines", "whole_project", "coverage_delta"].contains(key) else {
                    throw error(url, lineNumber, "unknown key \(key) in path_scope")
                }
                guard pathScope[key] == nil else { throw error(url, lineNumber, "duplicate key \(key) in path_scope") }
                pathScope[key] = try boolean(value, url: url, line: lineNumber)
            case .sonar:
                let supported = [
                    "properties_file", "use_sources_as_allowlist", "use_exclusions",
                    "use_coverage_exclusions", "use_test_paths_as_exclusions",
                ]
                guard supported.contains(key) else { throw error(url, lineNumber, "unknown key \(key) in sonar") }
                guard sonar[key] == nil else { throw error(url, lineNumber, "duplicate key \(key) in sonar") }
                if key == "properties_file" {
                    sonar[key] = try string(value, url: url, line: lineNumber)
                } else {
                    sonar[key] = String(try boolean(value, url: url, line: lineNumber))
                }
            case .topLevel:
                if key == "schema_version" {
                    guard version == nil else { throw error(url, lineNumber, "duplicate key schema_version") }
                    guard let parsed = Int(value), !value.contains(".") else {
                        throw error(url, lineNumber, "schema_version must be an integer")
                    }
                    version = parsed
                } else if key == "minimum" {
                    guard !hasMinimum else { throw error(url, lineNumber, "duplicate key minimum") }
                    guard let value = Double(value), value.isFinite, (0...100).contains(value) else {
                        throw error(url, lineNumber, "minimum must be a finite percentage from 0 through 100")
                    }
                    minimum = try Percentage(value)
                    hasMinimum = true
                } else {
                    throw error(url, lineNumber, "unknown top-level key \(key)")
                }
            }
        }
        guard let version else { throw WhatCoverageError.invocation("\(url.path): missing required schema_version") }
        guard version == 1 || version == 2 else { throw WhatCoverageError.invocation("\(url.path): unsupported schema_version \(version); this executable supports versions 1 and 2") }
        guard version == 2 || pathScope.isEmpty && sonar.isEmpty else {
            throw WhatCoverageError.invocation("\(url.path): path_scope and sonar require schema_version = 2")
        }
        let explicitRules = try rules.enumerated().map { index, rule in
            guard let pattern = rule.values["pattern"] else { throw error(url, rule.line, "paths rule \(index + 1) is missing pattern") }
            guard let actionText = rule.values["action"] else { throw error(url, rule.line, "paths rule \(index + 1) is missing action") }
            guard let action = PathRuleAction(rawValue: actionText) else {
                throw error(url, rule.line, "paths rule \(index + 1) has unsupported action \(String(reflecting: actionText)); expected include or exclude")
            }
            do { return try PathRule(pattern: pattern, action: action, directoryTree: version == 2) }
            catch { throw Self.error(url, rule.line, "paths rule \(index + 1) has invalid pattern \(String(reflecting: pattern)): \(error)") }
        }
        let importedRules = try sonarRules(sonar, configurationURL: url)
        return RepositoryConfiguration(
            minimum: minimum,
            pathSelection: PathSelection(rules: importedRules + explicitRules),
            pathScope: PathScope(
                changedLines: pathScope["changed_lines"] ?? true,
                wholeProject: pathScope["whole_project"] ?? false,
                coverageDelta: pathScope["coverage_delta"] ?? false
            )
        )
    }

    private static func sonarRules(_ configuration: [String: String], configurationURL: URL) throws -> [PathRule] {
        guard !configuration.isEmpty else { return [] }
        guard let path = configuration["properties_file"], !path.isEmpty else {
            throw WhatCoverageError.invocation("\(configurationURL.path): sonar.properties_file is required when [sonar] is present")
        }
        let pathComponents = path.split(separator: "/", omittingEmptySubsequences: false)
        guard !path.hasPrefix("/"), !path.hasPrefix("\\"), !path.contains("\\"),
              path.range(of: "^[A-Za-z]:", options: .regularExpression) == nil,
              pathComponents.allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." })
        else {
            throw WhatCoverageError.invocation("\(configurationURL.path): sonar.properties_file must be a canonical path relative to the configuration file")
        }
        let propertiesURL = configurationURL.deletingLastPathComponent().appending(path: path).standardizedFileURL
        guard FileManager.default.fileExists(atPath: propertiesURL.path) else {
            throw WhatCoverageError.invocation("Sonar properties file \(propertiesURL.path) does not exist")
        }
        let properties = try SonarProperties.load(from: propertiesURL)
        var rules: [PathRule] = []

        func enabled(_ key: String) -> Bool { configuration[key] == "true" }
        func patterns(_ key: String) throws -> [String] {
            guard let value = properties[key] else { return [] }
            return try SonarProperties.patterns(value, key: key, url: propertiesURL)
        }
        func append(_ patterns: [String], action: PathRuleAction) throws {
            for pattern in patterns {
                do { rules.append(try PathRule(pattern: pattern, action: action, directoryTree: true)) }
                catch {
                    throw WhatCoverageError.invocation("\(propertiesURL.path): unsupported Sonar path pattern \(String(reflecting: pattern)): use WhatCoverage *, ?, and whole-component ** syntax")
                }
            }
        }

        if enabled("use_sources_as_allowlist") {
            let sources = try patterns("sonar.sources")
            if !sources.isEmpty {
                rules.append(try PathRule(pattern: "**", action: .exclude))
                try append(sources, action: .include)
            }
        }
        if enabled("use_exclusions") { try append(patterns("sonar.exclusions"), action: .exclude) }
        if enabled("use_coverage_exclusions") { try append(patterns("sonar.coverage.exclusions"), action: .exclude) }
        if enabled("use_test_paths_as_exclusions") { try append(patterns("sonar.tests"), action: .exclude) }
        return rules
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

    private static func boolean(_ value: String, url: URL, line: Int) throws -> Bool {
        if value == "true" { return true }
        if value == "false" { return false }
        throw error(url, line, "value must be true or false")
    }

    private static func error(_ url: URL, _ line: Int, _ message: String) -> WhatCoverageError {
        .invocation("\(url.path):\(line): \(message)")
    }

    private enum Section {
        case topLevel
        case pathRule(Int)
        case pathScope
        case sonar
    }
}

private enum SonarProperties {
    static func load(from url: URL) throws -> [String: String] {
        let text: String
        do { text = try String(contentsOf: url, encoding: .utf8) }
        catch { throw WhatCoverageError.invocation("Cannot read Sonar properties file \(url.path): \(error.localizedDescription)") }

        var logicalLines: [(line: Int, text: String)] = []
        var pending = ""
        var pendingLine = 0
        for (index, rawLine) in text.split(omittingEmptySubsequences: false, whereSeparator: \Character.isNewline).enumerated() {
            var line = String(rawLine)
            if pending.isEmpty { pendingLine = index + 1 } else { line = line.trimmingCharacters(in: .whitespaces) }
            let slashCount = line.reversed().prefix(while: { $0 == "\\" }).count
            if slashCount % 2 == 1 {
                line.removeLast()
                pending += line
            } else {
                logicalLines.append((pendingLine, pending + line))
                pending = ""
            }
        }
        guard pending.isEmpty else { throw WhatCoverageError.invocation("\(url.path):\(pendingLine): unterminated property continuation") }

        var result: [String: String] = [:]
        for logical in logicalLines {
            let line = logical.text.trimmingCharacters(in: .whitespaces)
            if line.isEmpty || line.hasPrefix("#") || line.hasPrefix("!") { continue }
            guard let separator = line.firstIndex(where: { $0 == "=" || $0 == ":" || $0.isWhitespace }) else {
                result[line] = ""
                continue
            }
            let key = String(line[..<separator]).trimmingCharacters(in: .whitespaces)
            var valueStart = separator
            while valueStart < line.endIndex && (line[valueStart] == "=" || line[valueStart] == ":" || line[valueStart].isWhitespace) {
                valueStart = line.index(after: valueStart)
            }
            let value = String(line[valueStart...]).trimmingCharacters(in: .whitespaces)
            guard !key.isEmpty else { throw WhatCoverageError.invocation("\(url.path):\(logical.line): empty property key") }
            result[key] = value
        }
        return result
    }

    static func patterns(_ value: String, key: String, url: URL) throws -> [String] {
        guard !value.contains("\\") else {
            throw WhatCoverageError.invocation("\(url.path): property escapes are unsupported in imported \(key) path settings")
        }
        let values = value.split(separator: ",", omittingEmptySubsequences: false).map {
            String($0).trimmingCharacters(in: .whitespaces)
        }
        guard values.allSatisfy({ !$0.isEmpty }) else {
            throw WhatCoverageError.invocation("\(url.path): \(key) contains an empty path pattern")
        }
        for pattern in values where pattern.hasPrefix("!") || pattern.contains("{") || pattern.contains("}") || pattern.contains("[") || pattern.contains("]") {
            throw WhatCoverageError.invocation("\(url.path): \(key) uses unsupported Sonar path pattern \(String(reflecting: pattern)); brace expansion, character classes, and negation are not supported")
        }
        return values
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
