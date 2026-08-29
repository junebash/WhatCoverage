# Roadmap

Each phase ends with tested, usable behavior and a documentation update. Plans
for a phase should be written immediately before implementation so they can
reflect what earlier work taught us.

**Status:** Planning foundation recorded; implementation has not started.

**Next:** Resolve the Phase 1 model details in a short implementation plan, then
write the first failing calculation test.

## Phase 1: Domain model and diff calculation

**Outcome:** Pure Swift code calculates a diff-coverage report from normalized
coverage and changed-line values.

- Define source paths, executable-line coverage, changed files, report totals,
  percentages, and policy outcomes.
- Define repository path identity and the contract for unambiguous source-path
  mapping.
- Define rounding and empty-denominator semantics.
- Implement per-file and total aggregation.
- Evaluate an optional threshold after calculation.
- Build fixture-free unit tests for calculation edge cases.
- Record the initial report contract.
- Enable complete Swift 6.2 strict concurrency checking and keep the package
  building with it from this phase onward.

**Requirements:** CALC-001–006, QUAL-001–002, QUAL-004.

**Exit criteria:** The calculation matrix is fully tested without reading files
or launching processes.

## Phase 2: Git changed-line discovery

**Outcome:** The library resolves head-side changed lines between two revisions.

- Introduce an isolated process runner.
- Implement merge-base-to-head as the default and direct comparison as an
  explicit mode.
- Combine a zero-context patch with machine-oriented path/status information.
- Parse added and modified line ranges.
- Handle deletion, rename, binary-file, submodule, empty-diff, and malformed-diff
  fixtures.
- Provide Git-specific errors with actionable context.

**Requirements:** GIT-001–010, QUAL-003.

**Exit criteria:** Integration tests against temporary repositories agree with
parser fixtures for every supported diff shape.

## Phase 3: SwiftPM LLVM coverage input

**Outcome:** Existing LLVM coverage JSON normalizes into the shared model.

- Capture minimal representative fixtures and document their provenance.
- Validate the LLVM coverage export type and supported schema versions.
- Derive executable-line counts from LLVM segment transitions.
- Normalize absolute and repository-relative source paths.
- Apply the caller's captured source root when artifacts came from another
  checkout and test that behavior end to end.
- Reject unsupported or malformed input explicitly.
- Verify the reader against an artifact from a small Swift package.

**Requirements:** IN-002–007.

**Exit criteria:** An LLVM artifact and Git diff can produce an in-memory report
through the public library API.

## Phase 4: Xcode coverage input

**Outcome:** An existing Xcode result bundle normalizes into the same model.

- Establish supported `xccov` and result-bundle version assumptions.
- Read line data using `xcrun xccov view --archive --json`; do not substitute the
  summary-only report JSON.
- Normalize Xcode source paths and line execution data.
- Distinguish missing coverage, invalid bundles, and tool failures.
- Verify how `xccov` aggregates result bundles containing multiple test actions;
  preserve its deterministic aggregate or fail explicitly if it cannot produce
  one archive.
- Verify against a fixture project result bundle without committing unnecessarily
  large generated artifacts.

**Requirements:** IN-001, IN-003–007.

**Exit criteria:** Equivalent logical coverage from Xcode and LLVM inputs yields
the same normalized values. A checked-in minimal fixture project and documented
generation command can reproduce the integration `.xcresult`; unit tests use
small captured `xccov` JSON and process-runner fixtures instead of committing the
generated bundle.

## Phase 5: JSON and Markdown rendering

**Outcome:** A report can be serialized for machines and rendered for people.

- Publish JSON schema version 1 and golden fixtures.
- Render concise Markdown totals and per-file details.
- Keep ordering and percentage formatting deterministic.
- Represent not-applicable and threshold-failure results explicitly.
- Document compatibility expectations for downstream consumers.

**Requirements:** OUT-001–006.

**Exit criteria:** Golden tests demonstrate that both renderers express the same
report and policy outcome.

## Phase 6: Command-line product

**Outcome:** Users can run the complete artifact-to-report workflow locally or
in any CI provider.

- Design and implement the command interface.
- Infer input format where unambiguous and permit an explicit override.
- Accept a captured source root and demonstrate cross-machine path remapping.
- Support simultaneous Markdown and JSON outputs.
- Write reports before returning a threshold-failure status.
- Define and document stable exit statuses and diagnostics.
- Exercise end-to-end workflows for both artifact types.

**Requirements:** CLI-001–007, QUAL-005.

**Exit criteria:** Documented invocations process Xcode and SwiftPM artifacts,
including one with paths from another checkout, write both report formats, and
gate correctly on a threshold.

## Later: Whole-project coverage delta

**Outcome:** Two normalized artifacts reveal base-versus-head changes at project,
target, and file granularity.

This begins only after the v1 report contract is stable. It will reuse artifact
readers while keeping its comparison semantics distinct from changed-line
coverage.

**Requirements:** DELTA-001–002.
