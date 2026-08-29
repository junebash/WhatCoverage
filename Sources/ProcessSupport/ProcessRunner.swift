import Foundation

public struct ProcessResult: Equatable, Sendable {
    public let exitCode: Int32
    public let standardOutput: Data
    public let standardError: String

    public init(exitCode: Int32, standardOutput: Data, standardError: String) {
        self.exitCode = exitCode
        self.standardOutput = standardOutput
        self.standardError = standardError
    }
}

public protocol ProcessRunning: Sendable {
    func run(command: String, arguments: [String], currentDirectory: URL) throws -> ProcessResult
}

public enum ProcessRunnerError: Error, Equatable, Sendable {
    case couldNotLaunch(command: String, reason: String)
    case couldNotCaptureOutput(reason: String)
}

public struct FoundationProcessRunner: ProcessRunning, Sendable {
    public init() {}

    public func run(command: String, arguments: [String], currentDirectory: URL) throws -> ProcessResult {
        let process = Process()
        let temporaryDirectory = FileManager.default.temporaryDirectory
        let outputURL = temporaryDirectory.appending(path: "whatcoverage-stdout-\(UUID().uuidString)")
        let errorURL = temporaryDirectory.appending(path: "whatcoverage-stderr-\(UUID().uuidString)")
        defer {
            try? FileManager.default.removeItem(at: outputURL)
            try? FileManager.default.removeItem(at: errorURL)
        }
        guard FileManager.default.createFile(atPath: outputURL.path, contents: nil),
              FileManager.default.createFile(atPath: errorURL.path, contents: nil)
        else { throw ProcessRunnerError.couldNotCaptureOutput(reason: "Could not create temporary files") }
        let output: FileHandle
        let errorOutput: FileHandle
        do {
            output = try FileHandle(forWritingTo: outputURL)
            errorOutput = try FileHandle(forWritingTo: errorURL)
        } catch {
            throw ProcessRunnerError.couldNotCaptureOutput(reason: error.localizedDescription)
        }
        defer {
            try? output.close()
            try? errorOutput.close()
        }
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = [command] + arguments
        process.currentDirectoryURL = currentDirectory
        process.standardOutput = output
        process.standardError = errorOutput
        do {
            try process.run()
        } catch {
            throw ProcessRunnerError.couldNotLaunch(command: command, reason: error.localizedDescription)
        }
        process.waitUntilExit()
        try output.close()
        try errorOutput.close()
        let outputData = try Data(contentsOf: outputURL)
        let errorData = try Data(contentsOf: errorURL)
        return ProcessResult(
            exitCode: process.terminationStatus,
            standardOutput: outputData,
            standardError: String(decoding: errorData, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        )
    }
}
