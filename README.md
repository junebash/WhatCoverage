# WhatCoverage

WhatCoverage answers one question for Swift changes: **are the executable lines
changed by this work covered by tests?** It reads an existing SwiftPM LLVM JSON
export or Xcode `.xcresult`, intersects its line coverage with a Git diff, and
writes provider-neutral Markdown and/or versioned JSON reports. With a second
base artifact, it also reports whole-project coverage change independently of
the diff. Every report includes current whole-project coverage from the head
artifact without requiring that second artifact.

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

Each installation method below installs both `what-coverage` and
`what-coverage-pr-comment`. Releases support macOS arm64 and x86_64 plus Linux
x86_64.

### mise with aqua (recommended for CI)

WhatCoverage publishes a small first-party aqua registry. Pin both that registry
definition and the tool version in `mise.toml`; mise does not require a separate
aqua installation:

```toml
[settings]
aqua.registries = [
  "https://raw.githubusercontent.com/junebash/WhatCoverage/v0.10.0/aqua/registry.yaml",
]

[tools]
"aqua:junebash/WhatCoverage" = "0.10.0"
```

Then install the pinned tools and verify both entry points:

```sh
mise install
what-coverage --help
what-coverage-pr-comment --help
```

Direct aqua users can use the same package and release:

```yaml
registries:
  - name: whatcoverage
    type: github_content
    repo_owner: junebash
    repo_name: WhatCoverage
    ref: v0.10.0
    path: aqua/registry.yaml
packages:
  - name: junebash/WhatCoverage@v0.10.0
    registry: whatcoverage
```

Because aqua requires an explicit policy for non-standard registries, add the
following reviewed `aqua-policy.yaml` beside the aqua configuration:

```yaml
registries:
  - name: whatcoverage
    type: github_content
    repo_owner: junebash
    repo_name: WhatCoverage
    ref: 'Version == "v0.10.0"'
    path: aqua/registry.yaml
packages:
  - registry: whatcoverage
```

Approve that policy once, then install:

```sh
aqua policy allow aqua-policy.yaml
aqua install
```

The registry reference is an immutable WhatCoverage Git tag. Its definition
maps aqua's Linux/macOS architectures to the release assets, exposes both
executables, and verifies each archive with that release's `SHA256SUMS`.
Consumers do not need to copy platform digests into their own repositories. The
registry definition and tool version may be pinned independently when a future
tool release does not change the package layout.

### Tagged installer (no package manager)

The checked-in installer is the fallback when aqua or mise is unavailable. Pin
both the installer URL and `--version` to the same Git tag; do not pipe an
unpinned network response into a shell:

```sh
version=0.10.0
curl -fsSLO "https://raw.githubusercontent.com/junebash/WhatCoverage/v${version}/scripts/install.sh"
bash install.sh --version "$version" --prefix ~/.local
export PATH="$HOME/.local/bin:$PATH"
```

The installer downloads the matching release archive and `SHA256SUMS`, verifies
the archive, and installs both executables into the selected prefix's `bin`
directory.

### Manual release download

Each GitHub Release includes native `macos-arm64`, `macos-x86_64`, and
`linux-x86_64` archives plus `SHA256SUMS`. Starting with v0.9.0, every archive
contains both executables. For example, install v0.10.0 on Linux x86_64:

```sh
version=0.10.0
archive="what-coverage-v${version}-linux-x86_64.tar.gz"
base="https://github.com/junebash/WhatCoverage/releases/download/v${version}"
curl -fLO "$base/$archive"
curl -fLO "$base/SHA256SUMS"
grep " $archive$" SHA256SUMS | sha256sum --check
tar -xzf "$archive"
install -m 755 what-coverage ~/.local/bin/what-coverage
install -m 755 what-coverage-pr-comment ~/.local/bin/what-coverage-pr-comment
```

On macOS, substitute `macos-arm64` or `macos-x86_64` in the archive name and
verify with `shasum -a 256 -c` after extracting the matching line from
`SHA256SUMS`. Add `~/.local/bin` to `PATH` if needed, then confirm the installed
archive:

```sh
what-coverage --help
what-coverage-pr-comment --help
```

## Build

Clone the repository and build the executable with Swift Package Manager:

```sh
swift build -c release --product what-coverage
swift build -c release --product what-coverage-pr-comment
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

To add a base-versus-head whole-project comparison, preserve the coverage
artifact produced at the base revision and pass it separately. `--input` is
always the head artifact:

```sh
.build/release/what-coverage \
  --input artifacts/head-coverage.json \
  --base-input artifacts/base-coverage.json \
  --base origin/main \
  --markdown-output coverage.md \
  --json-output coverage.json
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
- `--base-input` enables whole-project delta. Its format is inferred independently
  or selected with `--base-format`; `--base-captured-source-root` remaps absolute
  paths recorded in that artifact.
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

Current whole-project coverage aggregates normalized repository-relative files
in the head artifact. It is informational and does not affect changed-line
policy or exit status. Schema v1 and schema v2's default include files excluded
from changed-line coverage; schema v2 can apply the same path selection with
`path_scope.whole_project = true`. With no selected executable lines it is
`N/A`, not 0% or 100%.

Whole-project delta instead compares every normalized file with executable lines
in the union of the base and head artifacts. It reports each side's executable
and covered counts, coverage percentage, and the percentage-point change at
project, target, and file granularity. A missing file has zero counts on that
side. If either side has no executable lines, its percentage and the change are
`N/A`. Target groups
are portable source-layout groups because LLVM and Xcode line artifacts do not
share build-target metadata: `Sources/<name>` and `Tests/<name>` use `<name>`,
other nested paths use their first component, and root files use `(root)`.
Schema v2 can also apply path selection to delta with
`path_scope.coverage_delta = true`. Delta never affects policy or exit status.

### Coverage configuration

The versioned configuration can define a repository-wide minimum and path
selection. A measured percentage equal to the minimum passes; one below it
fails. Schema v1 preserves the original behavior: path rules affect only
changed-line file rows, totals, policy, and exit status. Schema v2 adds explicit
scope and optional SonarQube property import:

```toml
schema_version = 2
minimum = 60

[path_scope]
changed_lines = true
whole_project = true
coverage_delta = true

[sonar]
properties_file = "sonar-project.properties"
use_sources_as_allowlist = true
use_exclusions = true
use_coverage_exclusions = true
use_test_paths_as_exclusions = true

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
order and the last matching rule wins. Imported Sonar rules run first, in the
order `sonar.sources` allowlist, `sonar.exclusions`,
`sonar.coverage.exclusions`, and `sonar.tests`; explicit `[[paths]]` rules can
therefore override them. Unmatched files are included, so an
allowlist starts with `pattern = "**"` and `action = "exclude"`. `*` matches
zero or more non-`/` characters in one component, `?` matches one non-`/`
character, and a `**` component matches zero or more components. Matching is
case-sensitive; dotfiles and Unicode have no special treatment. Bracket classes,
brace expansion, negation, and escapes are not glob features.

In schema v2 and imported Sonar settings, a pattern with no `*` or `?` is a
directory-tree token: `Tests` has the same selection effect on repository files
as `Tests/**`. Existing wildcard patterns are not rewritten; `Tests/**` and
`Tests/**/*` retain their normal glob meanings and both select files below
`Tests`. Schema v1 keeps its exact matching, so its bare `Tests` pattern does not
match `Tests/AppTests.swift`.

The Sonar importer reads comma-separated values and Java-properties `\` line
continuations from the four selected keys. Missing keys are harmless and other
Sonar properties are ignored. A missing properties file, property escapes,
empty entries, absolute or malformed paths, and unsupported brace, character
class, or negation patterns are invocation errors rather than silently changed
semantics. `properties_file` is relative to `.whatcoverage.toml` (or the file
selected by `--config`). Each `use_...` option defaults to `false`.

Patterns must be nonempty, relative, slash-separated, and canonical. Absolute,
drive-rooted, backslash, empty-component, `.`, `..`, and embedded-`**` patterns
are rejected. The parser requires `schema_version = 1` or `2`; each optional
`[[paths]]` table requires quoted `pattern` and `action` strings.
`minimum` must be an unquoted, finite number from 0 through 100 and must precede
the first table header. It is optional, as are path rules. The parser
rejects unknown or duplicate keys, malformed values, unsupported schema
versions, and invalid rules as invocation errors. No TOML dependency is used:
the implementation intentionally accepts only this small, validated TOML subset
rather than introducing a supply-chain dependency.

### Rich pull-request comments in generic CI

The flat `--markdown-output` report remains suitable for job summaries. For the
same rich comment used by this repository's GitHub workflow—including the stable
marker, status, diff and whole-project totals, collapsed uncovered source, and
collapsed file table—render the JSON report from a trusted local checkout:

```sh
what-coverage-pr-comment render \
  --report what-coverage-report.json \
  --head "$CM_COMMIT" \
  --repo-root . \
  --run-url "https://codemagic.io/app/.../build/..." \
  --output coverage-comment.md
```

Post `coverage-comment.md` with the CI provider's sticky-comment mechanism. This
mode validates the report and reads only bounded UTF-8 source files under
`--repo-root`; missing, binary, oversized, or escaping symlink targets simply do
not receive excerpts. It is intended for trusted CI checkouts. It does not
replace the trust-split GitHub Actions design described in
[`Documentation/PR_COVERAGE.md`](Documentation/PR_COVERAGE.md).

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
`CoverageReaders`, `CoverageDelta`, `DiffCoverage`, `GitDiff`, `ProcessSupport`,
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
