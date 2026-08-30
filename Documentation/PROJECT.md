# Project Overview

## Purpose

WhatCoverage answers a narrow question: **are the executable lines changed by
this work covered by tests?**

It is intended for Xcode projects and Swift packages whose CI jobs already
produce coverage artifacts. The tool replaces the conversion scripts and
provider-specific glue commonly needed to use general-purpose diff-coverage
tools in Swift repositories.

## Goals

- Report coverage for lines changed between two Git revisions.
- Read coverage produced by both Xcode and Swift Package Manager workflows.
- Produce Markdown suitable for a build summary or pull-request comment.
- Produce stable JSON for automation and future integrations.
- Fail predictably when coverage falls below a configured threshold.
- Optionally compare whole-project coverage from base and head artifacts.
- Explain input, Git, and threshold failures distinctly.
- Remain independent of CI and source-hosting providers.

## Non-goals

- Running builds or tests.
- Uploading reports or calling GitHub, GitLab, or CI-provider APIs.
- Replacing static analysis, quality gates, or other non-coverage SonarCloud
  features.
- Persisting coverage history or tracking trends across more than two artifacts.
- Rendering a hosted web dashboard.

Whole-project base-versus-head coverage delta requires two coverage artifacts
and remains deliberately separate from changed-line coverage, which requires
only the head artifact and a Git diff.

## Intended workflow

1. CI runs tests with coverage enabled.
2. CI invokes WhatCoverage with the coverage artifact and base revision.
3. WhatCoverage resolves the changed lines from Git.
4. WhatCoverage correlates those lines with executable regions in the artifact.
5. It writes Markdown and/or JSON and exits according to the configured policy.

When a base artifact is supplied, WhatCoverage also normalizes it and compares
whole-project coverage with the head artifact. This comparison does not use the
Git line diff and does not affect changed-line policy or exit status.

WhatCoverage must also work locally when given the same inputs.

## Design principles

- **Artifact in, report out.** Build orchestration is outside the tool.
- **One domain model.** Format-specific details stop at parser boundaries.
- **Focused internal modules.** Parsing and calculation remain isolated from CLI
  concerns for implementation clarity and testability.
- **Typed failures.** Missing input, malformed input, Git failure, and a failed
  coverage policy are not interchangeable.
- **Deterministic output.** The same artifact, repository state, and arguments
  produce the same report.
- **No changed executable lines is success.** The report states that there was
  nothing measurable instead of inventing a percentage.
- **Test with fixtures.** Core tests do not invoke builds, network services, or
  mutable external systems.

## Success for the first release

A repository can add one WhatCoverage invocation after its existing test step,
receive a readable diff-coverage summary, archive structured JSON, and gate the
job on a threshold without installing a second language runtime or granting API
credentials.
