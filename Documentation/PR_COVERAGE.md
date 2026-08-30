# Pull-request coverage comments

The repository's **PR Coverage** workflow runs on opened, reopened, and updated
pull requests. It runs the Swift tests with coverage enabled, locates SwiftPM's
LLVM coverage export, builds `what-coverage`, and compares the PR head against
its GitHub base SHA. The resulting comment gives the changed-line coverage and
policy outcome at a glance. A collapsed **Uncovered source** section shows a
small, line-numbered excerpt around uncovered lines; the per-file table remains
inside a separate `<details>` element.

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
   checks out only the trusted default-branch renderer, never PR code. With
   `actions: read`, `contents: read`, and `pull-requests: read`, it independently
   matches the run to the current PR, downloads the artifact, validates all
   counts, paths, and line lists against strict size limits, then fetches small
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

The comment begins with a stable hidden marker. Reruns update that comment
rather than creating duplicates, and the workflow removes accidental duplicate
comments authored by `github-actions[bot]`. Before writing, it confirms that the
PR still has the same head SHA, branch, and repository as the completed run, so
an older run cannot overwrite coverage for a newer push.

## Operational notes

- Both workflows must be present on the default branch before GitHub can run the
  complete `workflow_run` chain. The pull request that first adds them may not
  receive a comment itself.
- Artifacts are retained for seven days. Canceled or infrastructure-failed runs
  may not reach artifact upload; their comment links to the failing run.
- The check uses `macos-15` and Xcode 26.3, matching the Xcode smoke workflow.
- Repository Actions settings must permit the default `GITHUB_TOKEN` to create
  issue comments for the final job. No repository secret is required.
