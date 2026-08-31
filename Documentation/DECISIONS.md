# Decision Log

This file records choices that shape public behavior. Accepted decisions should
change only through an explicit replacement entry. Pending decisions must be
resolved before their roadmap phase begins.

## Accepted

### D-001: Consume existing artifacts

WhatCoverage reads coverage artifacts produced by another step. It does not run
builds or tests. This keeps the tool deterministic and independent of project
layout and CI orchestration.

### D-002: Start with changed-line coverage

The first release intersects current coverage with lines changed in Git.
Whole-project base-versus-head coverage delta is deferred because it requires a
coverage artifact from each revision and answers a different question.

### D-003: Publish Markdown and JSON

The first release writes provider-neutral Markdown and versioned JSON. It does
not call GitHub or CI-provider APIs. This avoids coupling core reporting to
credentials and permission models.

### D-004: Normalize before calculating

Xcode and LLVM readers convert their formats into one per-file executable-line
model. The calculator never knows which artifact produced its input and never
calculates from pre-aggregated percentages.

### D-005: Empty measurable diff is not applicable

When no changed line is executable, the result is explicitly not applicable and
succeeds by default. It is not reported as either zero or one hundred percent.

### D-006: Default to merge-base comparison

The default changed-line range is merge-base-to-head (`base...head`), matching
pull-request review semantics. A caller can explicitly request direct
commit-to-commit comparison (`base..head`). Reports record the mode and resolved
commit identifiers.

### D-007: Remap one captured source root

Artifact paths under the current repository root map automatically. For an
artifact produced in another checkout, the caller can provide its captured
source root, which maps to the current repository root. This covers the primary
CI artifact-transfer case without exposing a general path-rewrite language.

### D-008: Keep calculated percentages unrounded

The domain model stores the full calculated percentage and compares thresholds
against that value. Renderers may round for display, but must not feed a rounded
value back into policy evaluation. This keeps threshold behavior independent of
output formatting.

### D-009: Build the CLI with Swift Argument Parser

The command-line interface will use Apple's `swift-argument-parser` package.
Its declarative validation, generated help, and typed option parsing belong at
the executable boundary; parsed values will be passed to the existing internal
modules for coverage reading, Git discovery, calculation, and rendering. The
dependency is deferred until the command-line product phase and is not part of
the current internal implementation slice.

### D-010: Reject Xcode result bundles with multiple coverage archives

`xccov view --archive` documents extraction of a singular archive from a result
bundle. Its separate `merge` command is the only documented aggregation path,
and no deterministic implicit selection rule is published for bundles with
multiple test actions. Before reading coverage, WhatCoverage uses the Xcode 16+
legacy object view from `xcresulttool` to count distinct action coverage archive
references. Zero archives is missing coverage, one is read with
`xcrun xccov view --archive --json`, and more than one fails with an actionable
ambiguity error. A future explicit action-selection or merge feature can replace
this decision without silently changing current results.

### D-011: Version JSON by semantic compatibility

JSON reports carry integer `schemaVersion: 1` and conform to the published
version 1 schema. Within a schema version, producers may add optional object
members; consumers should ignore members they do not recognize. Removing or
renaming a member, changing its type or meaning, making an optional member
required, or adding an enum value requires a new schema version. Version 1 omits
`percentage` for a zero denominator, `capturedSourceRoot` when no remapping was
requested, `threshold` when no threshold was configured, and policy `actual`
unless the policy failed.

### D-012: Keep CLI exit statuses stable

The executable returns 0 for a successful calculation, including a
not-applicable result; 2 for a completed calculation that failed its threshold;
64 for invalid invocation; 65 for a coverage input failure; 66 for a Git
comparison failure; and 74 for report-output failure. The threshold result is
evaluated after writing each requested output so CI can retain diagnostics.

### D-013: Publish native archives with a tested Linux baseline

Each semantic-release GitHub Release publishes separately native-built macOS
arm64 and x86_64 archives and a Linux x86_64 archive. The Linux binary is built
in Swift 6.2.1's Ubuntu 22.04 image with the Swift standard library statically
linked; it still dynamically uses glibc and is therefore supported on glibc
2.35+ systems, specifically tested on Debian 12 and Ubuntu 22.04. Linux arm64
is not published because standard hosted runners do not provide a reliable
native arm64 Swift build without a paid larger runner. Every archive is
smoke-tested before publication and covered by a release-level SHA-256 manifest.

### D-014: Keep repository policy in the existing versioned configuration

Version 1 `.whatcoverage.toml` accepts an optional `minimum` alongside path
selection. The CLI loads both at the repository boundary, with `--minimum`
taking precedence, and passes the selected typed percentage to `DiffCoverage`.
This makes the PR requirement reviewable with the repository without duplicating
threshold evaluation outside the functional core. Missing configuration means
no threshold, while invalid configured values are invocation errors.

### D-015: Model whole-project delta as an optional independent comparison

`--input` remains the head artifact. Supplying `--base-input` reads a second
artifact through the same normalized boundary and adds project, target, and file
base/head counts, percentages, and percentage-point changes to both reports.
The union of canonical files measurable in either artifact is compared; a file
absent from one artifact has zero counts on that side. A percentage and therefore
a change are not applicable when their denominator is zero. Delta ignores Git
changed lines, configured path selection, and the changed-line minimum, and it
has no policy or exit status.

LLVM export and line-level Xcode archive JSON do not share a portable build-target
identifier. Target granularity is therefore a documented source-layout grouping:
`Sources/<name>` and `Tests/<name>` use `<name>`, other nested paths use the first
component, and root files use `(root)`. The optional `coverageDelta` JSON member
is an additive version-1 extension under D-011.

### D-016: Derive current whole-project coverage from normalized head coverage

Every CLI report aggregates current executable and covered counts across all
canonical repository-relative files in the normalized `--input` value. It does
not read the artifact again, require `--base-input`, use the Git diff, apply
changed-file path selection, or affect threshold policy and exit status. A zero
executable-line artifact has no percentage and renders as not applicable.

Version 1 JSON carries this as the additive optional `wholeProjectCoverage`
member so existing consumers and trusted comment renderers can continue to
accept older reports. Its name and PR-comment presentation describe only the
current head total; percentage-point change remains exclusive to
`coverageDelta` when a base artifact is explicitly supplied.

## Pending

None.
