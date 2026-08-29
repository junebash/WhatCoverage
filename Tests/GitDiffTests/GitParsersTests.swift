import Foundation
import GitDiff
import Testing

@Suite struct GitParsersTests {
    @Test func rawParserHandlesRenameDeletionAndUnusualPath() throws {
        let fixture = [
            ":100644 100644 aaaaaaa bbbbbbb R100", "old name.swift", "new\tname.swift",
            ":100644 000000 aaaaaaa 0000000 D", "Deleted.swift",
        ].joined(separator: "\0") + "\0"

        let changes = try GitRawDiffParser.parse(Data(fixture.utf8))

        #expect(changes.count == 2)
        #expect(changes[0].status == "R")
        #expect(changes[0].oldPath == "old name.swift")
        #expect(changes[0].newPath == "new\tname.swift")
        #expect(changes[1].newPath == nil)
    }

    @Test func unifiedDiffParserCollectsOnlyHeadRanges() throws {
        let patch = """
        diff --git a/A.swift b/A.swift
        @@ -1,2 +1,3 @@
        @@ -20 +21 @@ function
        @@ -30,2 +32,0 @@
        """
        #expect(try UnifiedDiffParser.addedLines(patch) == [1, 2, 3, 21])
    }

    @Test func unifiedDiffParserRejectsMalformedHunk() {
        #expect(throws: GitParseError.self) { try UnifiedDiffParser.addedLines("@@ malformed @@") }
    }

    @Test func rawParserRejectsMalformedRecordsAndNonUTF8Paths() {
        #expect(throws: GitParseError.self) { try GitRawDiffParser.parse(Data("bad\0path\0".utf8)) }
        let nonUTF8 = Data(":100644 100644 aaaaaaa bbbbbbb M\0".utf8) + Data([0xff, 0])
        #expect(throws: GitParseError.self) { try GitRawDiffParser.parse(nonUTF8) }
    }
}
