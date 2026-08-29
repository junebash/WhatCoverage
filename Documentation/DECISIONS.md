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
the executable boundary; parsed values will be passed to the existing library
modules for coverage reading, Git discovery, calculation, and rendering. The
dependency is deferred until the command-line product phase and is not part of
the current library implementation slice.

## Pending

### P-001: JSON compatibility policy

Define the precise guarantees attached to schema version 1, including treatment
of additive optional fields and enum expansion.

Resolve before Phase 5.

### P-002: Xcode multi-action aggregation

`xccov` exposes one coverage archive from a result bundle. Verify its behavior
when the bundle contains multiple test actions. Preserve a deterministic native
aggregate when available; otherwise require an explicit failure or selection
policy before completing the Xcode reader.

Resolve during Phase 4 before fixing the reader's public behavior.
