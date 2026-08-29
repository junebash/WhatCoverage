import CoverageModel
import Foundation

public enum PathMappingError: Error, Equatable, Sendable {
    case invalidRoot(String)
    case ambiguousSourcePath(source: String, candidates: [RepositoryPath])
}

public struct SourcePathMapper: Sendable {
    public let repositoryRoot: String
    public let capturedSourceRoot: String?

    public init(repositoryRoot: String, capturedSourceRoot: String? = nil) throws {
        guard repositoryRoot.hasPrefix("/") else { throw PathMappingError.invalidRoot(repositoryRoot) }
        if let capturedSourceRoot, !capturedSourceRoot.hasPrefix("/") {
            throw PathMappingError.invalidRoot(capturedSourceRoot)
        }
        self.repositoryRoot = Self.standardize(repositoryRoot)
        self.capturedSourceRoot = capturedSourceRoot.map(Self.standardize)
    }

    public func map(_ sourcePath: String) throws -> RepositoryPath? {
        if sourcePath.hasPrefix("/") {
            let path = Self.standardize(sourcePath)
            let current = try Self.relative(path, under: repositoryRoot).map(RepositoryPath.init)
            let captured = try capturedSourceRoot.flatMap { root in
                try Self.relative(path, under: root).map(RepositoryPath.init)
            }
            if let current, let captured, current != captured {
                throw PathMappingError.ambiguousSourcePath(
                    source: sourcePath,
                    candidates: [current, captured].sorted()
                )
            }
            return current ?? captured
        }
        return try RepositoryPath(sourcePath)
    }

    private static func standardize(_ path: String) -> String {
        URL(fileURLWithPath: path).standardizedFileURL.path
    }

    private static func relative(_ path: String, under root: String) -> String? {
        if path == root { return nil }
        let prefix = root == "/" ? "/" : root + "/"
        guard path.hasPrefix(prefix) else { return nil }
        return String(path.dropFirst(prefix.count))
    }
}
