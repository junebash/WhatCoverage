# WhatCoverage contributor guide

## Purpose and scope

WhatCoverage is a Swift 6.2 command-line package that calculates changed-line
coverage from an existing coverage artifact and a Git revision range. It does
not own test execution, coverage collection, report publication, or CI-provider
integration. Preserve that artifact-in/report-out boundary.

This file applies to the whole repository.

## Repository layout

- `Sources/CoverageModel`: format-independent paths, coverage values, report
  metadata, percentages, and policy outcomes. Keep this target free of process,
  Git, artifact-format, and rendering concerns.
- `Sources/CoverageReaders`: LLVM JSON decoding, Xcode result-bundle reading,
  and captured-root path mapping. Xcode tool invocation belongs here.
- `Sources/DiffCoverage`: pure intersection, aggregation, and threshold policy.
- `Sources/GitDiff`: Git revision resolution, status and patch parsing, and
  changed head-side line discovery.
- `Sources/ProcessSupport`: the injectable process-running abstraction shared by
  readers and Git integration.
- `Sources/ReportRendering`: deterministic Markdown and versioned JSON output.
  Renderers consume calculated values; they do not recalculate policy.
- `Sources/WhatCoverage`: Swift Argument Parser options, workflow composition,
  diagnostics, file output, and stable process exit statuses.
- `Tests/<Target>Tests`: Swift Testing suites aligned with source targets.
- `Tests/**/Fixtures`: small captured or synthetic inputs and golden reports.
- `Fixtures/XcodeFixture`: the minimal package used to generate a real Xcode
  result bundle for the macOS smoke test.
- `Documentation`: product requirements, architecture, decisions, roadmap, and
  the published JSON schema.

## Development commands

The package requires Swift 6.2 or newer. Run commands from the repository root:

```sh
swift build
swift test
swift run what-coverage --help
```

Build the distributable executable with:

```sh
swift build -c release --product what-coverage
```

The Xcode smoke path requires macOS with Xcode 16 or newer. Regenerate its local
bundle from `Fixtures/XcodeFixture` using the commands in that directory's
README. Do not commit `.build` or generated `.xcresult` bundles.

The repository has no configured formatter or linter. Follow the existing Swift
style: four-space indentation, focused value types, explicit typed errors, and
`Sendable` declarations at concurrency boundaries. Avoid formatting unrelated
code in feature changes.

## Testing and fixtures

- Add focused Swift Testing coverage (`@Suite`, `@Test`, and `#expect`) in the
  test target that owns changed behavior.
- Keep calculation tests pure. Use injected `ProcessRunning` implementations for
  process outcomes and temporary Git repositories only for integration behavior.
- Keep output ordering deterministic. When report output intentionally changes,
  update both renderer assertions and the corresponding golden fixture or JSON
  schema contract as required.
- Preserve fixture provenance in `Tests/CoverageReadersTests/Fixtures/README.md`.
  Prefer reduced captures over large generated artifacts.
- The Linux-compatible suite validates Xcode parsing with captured JSON. Changes
  to real `.xcresult` orchestration also need the macOS workflow in
  `.github/workflows/xcode-result-smoke.yml` or an equivalent local Xcode check.

## Behavioral contracts

- Coverage paths exposed to the model are canonical repository-relative paths.
  Mapping ambiguity is an error, not a reason to silently drop measurable data.
- Default Git comparison uses merge-base (`base...head`); direct `base..head` is
  an explicit option. Reports retain requested and resolved revisions.
- No changed executable lines is a successful, not-applicable result.
- Threshold failures write every requested report before returning status 2.
- Keep CLI exit statuses stable: 0 success, 2 threshold failure, 64 invocation,
  65 coverage input, 66 Git comparison, and 74 output failure.
- JSON compatibility follows `Documentation/whatcoverage-report-v1.schema.json`
  and decision D-011. Breaking member, type, meaning, requiredness, or enum
  changes require a new schema version; additive optional members may not.

Before changing public behavior, update the relevant requirements, architecture,
or decision documentation in the same change. Keep README examples synchronized
with generated CLI help and executable behavior.
