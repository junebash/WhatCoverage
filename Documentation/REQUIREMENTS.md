# Requirements

Requirement IDs are stable references for roadmap phases, tests, and future
design decisions.

## Coverage inputs

- **IN-001:** The tool accepts an existing Xcode result bundle containing code
  coverage.
- **IN-002:** The tool accepts existing LLVM coverage JSON produced for a Swift
  package.
- **IN-003:** The tool does not run `xcodebuild`, `swift test`, or another build
  command.
- **IN-004:** Both input formats normalize into the same source-file and
  executable-line model before diff calculation.
- **IN-005:** Paths from coverage data are mapped to repository-relative paths
  through one explicit path-normalization policy.
- **IN-006:** Ambiguous or unsuccessful path mappings fail explicitly rather
  than silently dropping measurable files.
- **IN-007:** When artifact paths were captured under a different checkout root,
  the caller can provide that original source root for deterministic remapping
  into the current repository.

## Git comparison

- **GIT-001:** The caller can provide base and head Git revisions.
- **GIT-002:** The head revision defaults to `HEAD`.
- **GIT-003:** Candidates are the head-side added line ranges in a zero-context
  patch. A source edit is represented by its deleted base lines and added head
  lines; only the latter are candidates.
- **GIT-004:** Deleted lines do not contribute to the denominator.
- **GIT-005:** Renamed files correlate with coverage using their head-side path.
- **GIT-006:** Binary files and submodules do not contribute coverage lines.
- **GIT-007:** Invalid revisions and unavailable repository history produce a
  Git-specific diagnostic.
- **GIT-008:** The selected revision-range semantics are exposed in report
  metadata and documented for callers.
- **GIT-009:** The default comparison is the merge base of base and head through
  head, matching `base...head` pull-request semantics.
- **GIT-010:** The caller can request direct `base..head` semantics for literal
  commit-to-commit comparison.

## Calculation

- **CALC-001:** A changed line contributes to the denominator only when the
  coverage artifact marks it executable.
- **CALC-002:** An executable changed line is covered when its execution count is
  greater than zero.
- **CALC-003:** The report includes covered, uncovered, and executable changed-line
  counts for each file and in total.
- **CALC-004:** Percentage calculation and rounding are consistent across every
  output format.
- **CALC-005:** A diff with no changed executable lines has an explicit
  not-applicable result and succeeds by default.
- **CALC-006:** A configurable minimum percentage can fail the policy without
  hiding the calculated report.

## Output

- **OUT-001:** The tool can write a human-readable Markdown report.
- **OUT-002:** Markdown includes the total result, the configured threshold when
  present, and per-file results.
- **OUT-003:** The tool can write a versioned JSON report.
- **OUT-004:** JSON exposes totals, per-file results, resolved revision SHAs,
  revision-range semantics, artifact identity and format, path-remapping
  configuration, policy outcome, and schema version.
- **OUT-005:** Ordering is deterministic.
- **OUT-006:** Reports distinguish a valid policy failure from an operational
  failure.

## Command-line behavior

- **CLI-001:** Arguments identify the coverage input, optional explicit format,
  base revision, optional head revision, comparison mode, optional captured
  source root, output destinations, and optional threshold.
- **CLI-002:** Invalid arguments fail before artifact parsing or Git work begins.
- **CLI-003:** Exit statuses distinguish success, threshold failure, invalid
  invocation, invalid coverage input, and Git failure.
- **CLI-004:** Diagnostics are concise and actionable.
- **CLI-005:** The command can emit both Markdown and JSON in one invocation.
- **CLI-006:** Input format is inferred from a recognized artifact type when
  unambiguous; an explicit format overrides inference.
- **CLI-007:** Unknown or ambiguous input types require an explicit format and
  produce an invocation diagnostic otherwise.
- **CLI-008:** The command discovers an optional `.whatcoverage.toml` only at the
  resolved compared repository root. `--config` selects one explicit file and
  `--no-config` disables automatic configuration loading.
- **CLI-009:** Version 1 configuration accepts an optional finite minimum from
  0 through 100 and deterministic, ordered, last-match-wins path rules over
  canonical repository-relative paths. Invalid or unsafe configuration is an
  invocation error.
- **CLI-010:** An explicit `--minimum` overrides the configured minimum;
  `--no-config` disables both configured policy and path selection.

## Quality attributes

- **QUAL-001:** Core calculation is pure and independent of process execution and
  file-system access.
- **QUAL-002:** Format parsers, Git integration, calculation, policy evaluation,
  and rendering have separate interfaces.
- **QUAL-003:** Fixture tests cover additions, modifications, deletions, renames,
  non-executable lines, partial coverage, complete coverage, and no measurable
  lines.
- **QUAL-004:** Every phase builds under Swift 6.2 complete strict concurrency
  checking.
- **QUAL-005:** The executable never requires network access or API credentials.

## Deferred requirements

- **DELTA-001:** Compare normalized whole-project reports from base and head
  artifacts.
- **DELTA-002:** Report project, target, and file coverage changes independently
  of the Git line diff.
- **INT-001:** Provide optional source-hosting integrations without coupling them
  to the calculation library.
