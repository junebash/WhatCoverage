# LLVM fixture provenance

`llvm-export.json` is a synthetic LLVM 2.x export covering region transitions,
captured-root and repository-relative paths, and an external path.

`llvm-export-swift-6.2.1.json` was generated from a temporary library created by
`swift package init`, tested with `swift test --enable-code-coverage`, and read
from the path printed by `swift test --show-codecov-path` using Swift 6.2.1. It
is reduced to the real test-source file's `filename` and `segments`, with the
temporary checkout prefix replaced by `/captured/project`.

The workflow integration test combines the synthetic fixture with a real
temporary Git repository.
