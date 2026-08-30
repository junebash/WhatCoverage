# Competitive analysis

This document records the feature survey used to prioritize the configuration
and rendering work in this pull request. It is a product-planning aid, not a
claim that every listed tool has identical input, language, or service scope.

## WhatCoverage baseline

WhatCoverage is a local Swift command-line tool: it consumes an existing SwiftPM
LLVM JSON export or Xcode `.xcresult`, intersects executable coverage with the
head-side Git diff, and writes deterministic reports. It does not run tests,
upload coverage, retain history, or call a source-hosting provider. See the
[project overview](PROJECT.md) and [architecture](ARCHITECTURE.md).

## Surveyed tools

| Tool | Relevant documented capability | Relationship to WhatCoverage |
| --- | --- | --- |
| [diff-cover](https://github.com/Bachmann1234/diff_cover) | Cobertura, Clover, JaCoCo XML, and LCOV inputs; multiple reports; HTML output; patch/diff controls. | It has broader artifact formats and report merging, while WhatCoverage has native SwiftPM LLVM and Xcode result-bundle readers. |
| [Codecov](https://docs.codecov.com/docs/commit-status) | Hosted patch statuses, flags, path configuration, uploads, and retained coverage data. | Service features are intentionally outside WhatCoverage's artifact-in/report-out boundary. |
| [Coveralls](https://docs.coveralls.io/build-types) | Hosted build aggregation, parallel-build coverage, comments, statuses, and history. | Parallel artifact aggregation is relevant; hosted workflow features are not immediate CLI scope. |
| [SonarQube](https://docs.sonarsource.com/sonarqube-server/user-guide/about-new-code) | New-code quality and coverage gates within a broader analysis platform. | Branch-aware/new-code policy is valuable but does not fit a line-only artifact reader without a model expansion. |
| [Undercover](https://github.com/grodowski/undercover) | Ruby SimpleCov changed-line and branch coverage enforcement. | It demonstrates the value of changed-code branch coverage, but relies on a different coverage model and ecosystem. |

## Current differentiators

- **Swift-native artifacts:** first-class SwiftPM LLVM JSON and Xcode
  `.xcresult` support, including line-level Xcode data.
- **Provider-neutral local operation:** no conversion service, upload token, or
  provider account is required.
- **Cross-checkout mapping:** `--captured-source-root` maps artifacts created in
  another checkout; ambiguous mapping fails rather than silently losing data.
- **Auditable report contract:** versioned JSON preserves requested and resolved
  revisions, comparison mode, coverage input identity, path mapping, totals, and
  policy outcome.
- **PR-correct default:** merge-base comparison (`base...head`) is the default;
  direct comparison is explicit and both resolved revisions are retained.

## Features implemented from this survey

### Ordered path selection

This pull request adds repository-root `.whatcoverage.toml` configuration with
strict schema version 1. Ordered `[[paths]]` include/exclude rules operate on
canonical repository-relative paths and use last-match-wins semantics. The
selection is applied once before calculation, so the same selected files control
Markdown, JSON, totals, policy, exit status, and PR-comment artifacts. See the
[README configuration reference](../README.md#path-selection-configuration).

This offers a local, deterministic alternative to service configuration: no
ancestor-directory search, no implicit working-directory behavior, and no
separate filter implementations for different report formats.

### Self-contained HTML report

This pull request also adds `--html-output`. `HTMLReportRenderer` presents the
existing `CoverageReportDocument` as escaped HTML, including per-file covered
and uncovered changed-line numbers. It does not read source files, recalculate
coverage, upload data, or call GitHub. It therefore remains within the renderer
and artifact-in/report-out boundaries.

## Prioritized next candidates

| Priority | Feature | Why it is useful | Scope decision |
| ---: | --- | --- | --- |
| 1 | Merge multiple coverage artifacts | Supports parallel or sharded test jobs; a line is covered if any shard covers it. | Defer until coverage-input provenance and JSON compatibility are designed explicitly. |
| 2 | LCOV reader | Broadens artifact compatibility while preserving the same normalized model. | Candidate for a dedicated reader-focused change with captured fixtures. |
| 3 | `--diff-file` | Helps CI or review systems that provide a patch but cannot expose full Git history. | Candidate after defining patch provenance and report metadata semantics. |
| 4 | Changed-line branch coverage | Can enforce a stronger coverage signal than line counts alone. | Defer: requires a format-independent branch model and support across readers. |

## Deliberately out of scope

Hosted dashboards, uploads, badges, notifications, provider-native statuses,
and source-hosting API calls belong to coverage services or repository-specific
integrations, not the WhatCoverage CLI. The repository's existing secure PR
comment workflow consumes the validated JSON report rather than changing that
boundary.
