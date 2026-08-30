# Architecture

## Shape

WhatCoverage is a command-line executable over a small set of focused library
modules. The CLI coordinates dependencies; it does not contain coverage logic.

```text
Xcode result bundle ─┐
                     ├─> Coverage parser ─> normalized coverage ─┐
LLVM coverage JSON ──┘                                           │
                                                                 ├─> calculator
Git revisions ─────────> Git diff provider ─> changed lines ─────┘       │
                                                                          v
                                                              report + policy
                                                                          │
                                                               ┌──────────┴───────┐
                                                               v                  v
                                                           Markdown              JSON
```

## Module boundaries

Names are provisional until the first implementation plan validates them.

### CoverageModel

Owns format-independent values such as repository-relative source paths,
executable lines, execution counts, changed lines, file results, totals, and
policy outcomes. It has no knowledge of Xcode, LLVM JSON, Git processes, or
rendering.

The model should make invalid states difficult to represent. Examples include a
validated percentage type and an explicit not-applicable result rather than a
fabricated `100%` for an empty denominator.

### CoverageReaders

Converts supported artifacts into `CoverageModel` values. Each reader absorbs
format-specific schemas, path conventions, and tool invocation details behind a
small interface.

Line-level Xcode coverage comes from `xcrun xccov view --archive --json`. The
similarly named `--report` output contains useful summaries but lacks the
executable line records required for diff coverage. The Xcode reader owns this
process and distinguishes a missing tool, invalid result bundle, absent coverage,
and malformed output. It first inspects Xcode 16+ result-bundle action metadata
with `xcresulttool get object --legacy`: exactly one distinct coverage archive is
required. This prevents `xccov` from implicitly choosing among multiple test
actions using behavior Apple does not document as deterministic.

LLVM coverage JSON is decoded directly. Its `segments` records encode coverage
regions and transitions rather than a ready-made line map, so the reader owns
the conversion to executable lines and validates the advertised schema type and
version. The first release accepts already-exported JSON; locating binaries and
profile data or invoking `llvm-cov export` is build-environment glue and remains
out of scope.

Both formats commonly contain absolute paths from the machine that ran the
tests. Path mapping is therefore an explicit operation, not a string cleanup
detail. By default, paths under the current repository root become relative. For
artifacts produced elsewhere, the caller supplies the captured checkout's source
root, which is replaced by the current repository root. Paths outside that root
are excluded from diff correlation; collisions and ambiguous mappings fail.

### ProcessSupport

Owns the small sendable process-running interface and Foundation adapter shared
by the Xcode reader and Git provider. Keeping process mechanics here avoids a
dependency between the otherwise independent coverage-input and Git modules;
tests inject value-based scripted runners.

### GitDiff

Returns repository-relative head-side paths and changed line numbers for a
validated revision range. Process execution and unified-diff parsing are hidden
behind the same boundary so tests can use in-memory fixtures.

The initial implementation should use a zero-context patch to obtain exact
head-side line ranges and machine-oriented status/path data to avoid treating
quoted or unusual filenames as display text. Rename handling must use the new
path. Deletions, binary files, and submodules are filtered here rather than
burdening the calculator.

The default comparison uses merge-base-to-head (`base...head`) because it matches
pull-request review. Callers can select direct commit comparison (`base..head`).
The adapter records the selected mode and resolved commit identifiers in report
metadata.

### DiffCoverage

Intersects changed lines with executable coverage lines, aggregates file and
total results, and evaluates an optional threshold. This is the functional core:
its inputs and outputs are values and its tests require no processes or files.

### ReportRendering

Transforms one report model into versioned JSON or Markdown. Renderers do not
recalculate percentages or policy outcomes. This prevents output formats from
disagreeing. `CoverageReportDocument` combines the calculated result with
provider-independent revision, artifact, and path-mapping metadata before it
crosses the rendering boundary. JSON version 1 is published as
`Documentation/whatcoverage-report-v1.schema.json`; Markdown formats percentages
to two decimal places for display while JSON preserves the model's full value.

### WhatCoverage CLI

Uses Apple's `swift-argument-parser` to validate arguments, infer or select a
reader, coordinate Git and coverage input, write requested reports, print
diagnostics, and map typed outcomes to exit statuses. Its workflow only composes
the focused library modules: it contains no coverage calculation, rendering, or
Git parsing logic. Argument errors occur before input parsing or Git work;
threshold failures occur only after every requested report has been written.

The CLI resolves the Git top-level directory before loading `.whatcoverage.toml`.
Its strict version-1 parser validates ordered path rules, then filters changed
head-side files once before `DiffCoverageCalculator`. This single boundary keeps
Markdown, JSON, totals, threshold policy, exit status, and downstream PR comment
artifacts consistent. Configuration deliberately does not set thresholds or
other CLI options in version 1.

## Report contract

The report model needs enough context to render all initial formats and support
future integrations:

- schema version
- requested and resolved base and head revision identifiers
- revision-range semantics
- coverage input kind and source
- captured source root and effective path mapping, when present
- total executable, covered, and uncovered changed lines
- optional percentage when the denominator is nonzero
- deterministic per-file results
- optional threshold
- policy outcome: passed, failed, or not applicable

JSON consumers must ignore unknown object members. Additive optional members may
preserve a version; changed meaning, removed or newly required members, changed
types, and enum expansion require a new schema version.

## Error model

Errors are grouped by action the caller can take:

- invocation: fix arguments
- coverage input: regenerate or provide the correct artifact
- Git comparison: fetch history or correct revisions
- report output: fix destination permissions or paths
- policy failure: improve coverage or intentionally change the threshold

A policy failure is a valid completed calculation, so requested reports are
written before the process returns its threshold-failure status.

## Extension: base-versus-head delta

Future coverage delta consumes two values from the existing normalized coverage
boundary and produces a separate comparison result. It must not be inferred from
diff coverage. Keeping artifact readers independent from the calculator lets
this feature reuse both readers without changing the CLI's initial core.
