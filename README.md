# WhatCoverage

WhatCoverage answers one question for Swift changes: **are the executable lines
changed by this work covered by tests?** It reads an existing SwiftPM LLVM JSON
export or Xcode `.xcresult`, intersects its line coverage with a Git diff, and
writes provider-neutral Markdown and/or versioned JSON reports.

WhatCoverage does not run tests, upload results, or contact a CI or source-hosting
service. The build that produces the coverage artifact remains a separate step.

## Requirements

- A prebuilt binary for macOS 13+ (Apple Silicon or Intel) or Debian 12+/Ubuntu
  22.04+ x86_64. Linux releases require glibc 2.35+ and Git.
- Git and enough local history to resolve the requested revisions
- Xcode 16 or newer, including `xcrun`, to read `.xcresult` input

Building from source instead requires Swift 6.2 or newer. LLVM JSON input is
decoded directly. Xcode input is macOS-only because its reader invokes
`xcresulttool` and `xccov`; the reader's fixture-based tests are otherwise
platform-neutral and also run in the project's Linux development orb.

## Install a release binary

Each GitHub Release includes native `macos-arm64`, `macos-x86_64`, and
`linux-x86_64` archives plus `SHA256SUMS`. Pin the version you choose; do not
pipe an unpinned network response into a shell. For example, install the first
binary-bearing release, v0.3.0, on Linux x86_64:

```sh
version=0.3.0
archive="what-coverage-v${version}-linux-x86_64.tar.gz"
base="https://github.com/junebash/WhatCoverage/releases/download/v${version}"
curl -fLO "$base/$archive"
curl -fLO "$base/SHA256SUMS"
grep " $archive$" SHA256SUMS | sha256sum --check
tar -xzf "$archive"
install -m 755 what-coverage ~/.local/bin/what-coverage
```

On macOS, substitute `macos-arm64` or `macos-x86_64` in the archive name and
verify with `shasum -a 256 -c` after extracting the matching line from
`SHA256SUMS`. The checked-in installer offers the same pinned, checksum-verified
flow:

```sh
curl -fsSLO https://raw.githubusercontent.com/junebash/WhatCoverage/v0.3.0/scripts/install.sh
bash install.sh --version 0.3.0 --prefix ~/.local
```

Add `~/.local/bin` to `PATH` if needed, then confirm the installed archive:

```sh
what-coverage --help
```

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
- `--minimum` accepts a percentage from 0 through 100 and overrides a configured
  `minimum`. Policy evaluation uses the unrounded value.
- The command discovers `.whatcoverage.toml` only at the resolved Git repository
  root (including when invoked from a subdirectory). `--config PATH` replaces
  that discovery; `--no-config` disables it. A missing discovered file preserves
  the pre-configuration behavior, while an explicitly requested file must exist.
- A diff with no changed executable lines is reported as not applicable and
  succeeds rather than being treated as either 0% or 100%.

Only executable lines added or modified on the head side contribute to the
denominator. Deleted lines, binary files, and submodules do not. Renames use the
head-side path.

### Coverage configuration

The versioned configuration can define a repository-wide minimum and path
selection. A measured percentage equal to the minimum passes; one below it
fails. Path rules select changed files before coverage is calculated, so they
affect file rows, totals, JSON, policy, exit status, and PR-comment artifacts
equally:

```toml
schema_version = 1
minimum = 60

[[paths]]
pattern = "Sources/**/*.swift"
action = "include"

[[paths]]
pattern = "**/Generated/**"
action = "exclude"

[[paths]]
pattern = "Sources/Generated/Important.swift"
action = "include"
```

Paths are normalized repository-relative `/` paths. Rules are evaluated in file
order and the last matching rule wins. Unmatched files are included, so an
allowlist starts with `pattern = "**"` and `action = "exclude"`. `*` matches
zero or more non-`/` characters in one component, `?` matches one non-`/`
character, and a `**` component matches zero or more components. Matching is
case-sensitive; dotfiles and Unicode have no special treatment. Bracket classes,
brace expansion, negation, and escapes are not glob features.

Patterns must be nonempty, relative, slash-separated, and canonical. Absolute,
drive-rooted, backslash, empty-component, `.`, `..`, and embedded-`**` patterns
are rejected. The parser strictly requires `schema_version = 1`; each optional
`[[paths]]` table requires quoted `pattern` and `action` strings.
`minimum` must be an unquoted, finite number from 0 through 100 and must precede
the first `[[paths]]` table. It is optional, as are path rules. The parser
rejects unknown or duplicate keys, malformed values, unsupported schema
versions, and invalid rules as invocation errors. No TOML dependency is used:
the implementation intentionally accepts only this small, validated TOML subset
rather than introducing a supply-chain dependency.

### Exit statuses

| Status | Meaning |
| ---: | --- |
| 0 | Report completed successfully, including a not-applicable diff |
| 2 | Report completed and was written, but failed the configured minimum |
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
