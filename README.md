# WhatCoverage

WhatCoverage answers one question for Swift changes: **are the executable lines
changed by this work covered by tests?** It reads an existing SwiftPM LLVM JSON
export or Xcode `.xcresult`, intersects its line coverage with a Git diff, and
writes provider-neutral Markdown and/or versioned JSON reports.

WhatCoverage does not run tests, upload results, or contact a CI or source-hosting
service. The build that produces the coverage artifact remains a separate step.

## Requirements

- Swift 6.2 or newer (the package declares Swift tools version 6.2)
- Git and enough local history to resolve the requested revisions
- macOS 13 or newer for the package's declared Apple platform
- Xcode 16 or newer, including `xcrun`, to read `.xcresult` input

LLVM JSON input is decoded directly. Xcode input is macOS-only because its reader
invokes `xcresulttool` and `xccov`; the library's fixture-based tests are otherwise
platform-neutral and also run in the project's Linux development orb.

## Build

Clone the repository and build the executable with Swift Package Manager:

```sh
swift build -c release --product what-coverage
.build/release/what-coverage --help
```

For development, `swift run what-coverage --help` builds and runs the debug
executable in one command.

## Usage

First generate coverage in the repository whose diff will be measured. For a
Swift package:

```sh
swift test --enable-code-coverage
swift test --show-codecov-path
```

The second command prints the LLVM JSON path to pass to `--input`. For an Xcode
project or workspace, run the existing test command with coverage enabled and a
result-bundle path, for example:

```sh
xcodebuild test \
  -scheme MyScheme \
  -destination 'platform=macOS' \
  -enableCodeCoverage YES \
  -resultBundlePath .build/MyScheme.xcresult
```

Then run WhatCoverage from the root of that Git repository:

```sh
.build/release/what-coverage \
  --input .build/debug/codecov/MyPackage.json \
  --base origin/main \
  --markdown-output coverage.md \
  --json-output coverage.json \
  --minimum 80
```

The input and output paths may be absolute or relative to the current repository.
Their parent directories must already exist. If coverage was captured in a
different checkout, remap its absolute source paths with the original checkout
root:

```sh
.build/release/what-coverage \
  --input artifacts/coverage.json \
  --base origin/main \
  --captured-source-root /builds/ci/project \
  --json-output coverage.json
```

### Options and comparison behavior

Run `what-coverage --help` for the generated option reference. The key behavior
is:

- `--input` and `--base` are required.
- At least one of `--markdown-output` or `--json-output` is required; both may be
  supplied, but they must be different paths.
- `--format llvm` or `--format xcode` overrides extension inference. Without it,
  `.json` means LLVM and `.xcresult` means Xcode.
- `--head` defaults to `HEAD`.
- `--comparison merge-base` is the default and measures the merge base of
  `base` and `head` through `head`, equivalent to pull-request `base...head`
  semantics. `--comparison direct` measures literal `base..head` changes.
- `--minimum` accepts a percentage from 0 through 100. Policy evaluation uses
  the unrounded value.
- A diff with no changed executable lines is reported as not applicable and
  succeeds rather than being treated as either 0% or 100%.

Only executable lines added or modified on the head side contribute to the
denominator. Deleted lines, binary files, and submodules do not. Renames use the
head-side path.

### Exit statuses

| Status | Meaning |
| ---: | --- |
| 0 | Report completed successfully, including a not-applicable diff |
| 2 | Report completed and was written, but failed `--minimum` |
| 64 | Invalid command invocation |
| 65 | Missing, malformed, or unreadable coverage input |
| 66 | Git comparison failure, including missing revisions or history |
| 74 | Report output failure |

## Development

```sh
swift build
swift test
```

Tests use Swift Testing and include unit, golden-output, temporary-Git-repository,
and artifact-to-report integration coverage. The checked-in fixture package under
`Fixtures/XcodeFixture` regenerates the Xcode result used by the macOS smoke
workflow; its generated `.xcresult` is intentionally not committed. See
[`Fixtures/XcodeFixture/README.md`](Fixtures/XcodeFixture/README.md) for that
workflow.

The package is split into focused targets under `Sources/`: `CoverageModel`,
`CoverageReaders`, `DiffCoverage`, `GitDiff`, `ProcessSupport`,
`ReportRendering`, and the `WhatCoverage` executable. Contributor guidance and
target ownership are documented in [`AGENTS.md`](AGENTS.md).

## Project documentation

- [Project overview](Documentation/PROJECT.md)
- [Requirements](Documentation/REQUIREMENTS.md)
- [Architecture and report contract](Documentation/ARCHITECTURE.md)
- [Decision log](Documentation/DECISIONS.md)
- [Implementation roadmap](Documentation/ROADMAP.md)
- [Release guide](Documentation/RELEASES.md)
- [Pull-request coverage workflow](Documentation/PR_COVERAGE.md)
- [JSON report schema v1](Documentation/whatcoverage-report-v1.schema.json)
