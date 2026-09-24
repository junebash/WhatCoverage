# Pull-request coverage comments

The repository's **PR Coverage** workflow runs on opened, reopened, and updated
pull requests. It runs the Swift tests with coverage enabled, locates SwiftPM's
LLVM coverage export, builds `what-coverage`, and compares the PR head against
its GitHub base SHA. The resulting comment gives the changed-line coverage,
current whole-project coverage, and changed-line policy outcome at a glance. A
collapsed **Uncovered source** section shows a small, line-numbered excerpt
around uncovered lines; the per-file table remains inside a separate `<details>`
element.

The current whole-project value is calculated from every normalized
repository-relative file in the head coverage artifact already read by the CLI.
Schema v2 can opt into applying path rules to this value; schema v1 and the v2
default do not. It does not require a base coverage artifact or represent a
delta. It is informational and cannot affect the changed-line policy or exit
status. If the selected artifact files contain no executable lines, the comment
says `Not applicable (0/0 executable lines)` instead of displaying 0%.

The repository's [`.whatcoverage.toml`](../.whatcoverage.toml) sets the required
changed-line coverage to 60%. The report step selects that file explicitly, so a
missing or invalid policy configuration fails rather than silently running
without a requirement. A measured result below 60% fails the check while exactly
60% passes. Change `minimum` in that file to adjust the requirement; an explicit
`--minimum` would override it. A failed threshold still produces and uploads the
report because WhatCoverage writes outputs before returning status 2. The comment
states the measured and required percentages for both passing and failing results.

A diff with no changed executable lines is not applicable and succeeds. Missing
or malformed coverage artifacts are operational failures, not 0% policy results;
the PR check fails and the comment workflow posts its failure fallback when no
valid report is available.

## Security model

The workflow is deliberately split in two:

1. **PR Coverage** uses the `pull_request` event with only `contents: read`.
   It checks out and tests PR code, but has no write token and keeps checkout
   credentials out of Git configuration. It uploads only the JSON report.
2. **PR Coverage Comment** is triggered by completion of that workflow. It
   checks out and builds only the trusted default-branch Swift renderer, never
   PR code. With
   `actions: read`, `contents: read`, and `pull-requests: read`, it independently
   matches the run to the current PR, downloads the artifact, validates all
   changed-line and whole-project counts, paths, and line lists against strict
   size limits, then fetches small
   source files from GitHub's Contents API at the verified PR-head SHA. It
   renders new Markdown from those validated values. A separate job receives
   only the rendered body and has `pull-requests: write` to upsert the comment.

This keeps a fork PR from obtaining a write-capable token. The comment workflow
never trusts a PR number, raw Markdown, shell command, link, or source excerpt
supplied by the artifact. Source retrieval is capped (10 files, 20 requests,
64 KiB per file, 512 KiB total); comments also cap excerpt targets, displayed
lines, line width, file rows, and total size. Paths cannot be absolute or use
traversal segments, and malformed, binary, missing, or oversized source is
omitted. If a report is missing or invalid, it posts a short failure message
that links to the workflow run instead.

The validator and renderer live in Swift's `ReportRendering` target, with the
workflow-facing `what-coverage-pr-comment` executable selecting bounded source
requests and rendering the final base64-encoded body. The GitHub Script steps
remain limited to trusted run/PR association, Contents API retrieval, and
comment upsert operations.

The comment begins with a stable hidden marker. Reruns update that comment
rather than creating duplicates, and the workflow removes accidental duplicate
comments authored by `github-actions[bot]`. Before writing, it confirms that the
PR still has the same head SHA, branch, and repository as the completed run, so
an older run cannot overwrite coverage for a newer push.

## Generic CI and Codemagic

Starting with v0.9.0, release archives ship the same trusted renderer as
`what-coverage-pr-comment`. A CI job that already trusts its local checkout can
turn the CLI's JSON report into posting-ready rich Markdown without the GitHub
Contents API or a Swift source build:

```sh
what-coverage \
  --input UnitTests.xcresult \
  --base origin/develop \
  --json-output what-coverage-report.json \
  --markdown-output what-coverage-report.md

what-coverage-pr-comment render \
  --report what-coverage-report.json \
  --head "$CM_COMMIT" \
  --repo-root . \
  --run-url "https://codemagic.io/app/.../build/..." \
  --output coverage-comment.md
```

The first Markdown remains the flat report for summaries and simple comments.
The second contains the stable marker, policy status, diff and whole-project
counts, collapsed uncovered-source excerpts, collapsed verbose file table, and
run link. The host CI owns sticky-comment upsert.

Local mode accepts any report filename and tolerates unrelated sibling files.
It still validates the report and applies the same source and comment caps.
Only regular UTF-8 files resolving beneath `--repo-root` are read; missing,
binary, oversized, and escaping symlink paths are omitted. Use this mode only in
a trusted checkout. Fork pull requests using a write-capable GitHub token should
retain the two-workflow design above; shipping the executable does not alter
that trust boundary.

## Operational notes

- Both workflows must be present on the default branch before GitHub can run the
  complete `workflow_run` chain. The pull request that first adds them may not
  receive a comment itself.
- Artifacts are retained for seven days. Canceled or infrastructure-failed runs
  may not reach artifact upload; their comment links to the failing run.
- The check uses `macos-15` and Xcode 26.3, matching the Xcode smoke workflow.
- Repository Actions settings must permit the default `GITHUB_TOKEN` to create
  issue comments for the final job. No repository secret is required.
