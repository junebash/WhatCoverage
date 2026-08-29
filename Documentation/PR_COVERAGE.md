# Pull-request coverage comments

The repository's **PR Coverage** workflow runs on opened, reopened, and updated
pull requests. It runs the Swift tests with coverage enabled, locates SwiftPM's
LLVM coverage export, builds `what-coverage`, and compares the PR head against
its GitHub base SHA. The resulting comment gives the changed-line coverage and
policy outcome at a glance; per-file results are inside a `<details>` element.

The report does not configure a minimum itself. Add `--minimum <percentage>` to
the `what-coverage` invocation in
[`.github/workflows/pr-coverage.yml`](../.github/workflows/pr-coverage.yml) to
make the coverage policy a required check. A failed threshold still produces a
report and comment because WhatCoverage writes outputs before returning status 2.

## Security model

The workflow is deliberately split in two:

1. **PR Coverage** uses the `pull_request` event with only `contents: read`.
   It checks out and tests PR code, but has no write token and keeps checkout
   credentials out of Git configuration. It uploads only the JSON report.
2. **PR Coverage Comment** is triggered by completion of that workflow. It does
   not check out or execute PR code. With `actions: read` and
   `pull-requests: read`, it independently matches the run to the current PR,
   downloads the artifact, validates a bounded subset of the report schema, and
   renders new Markdown from validated values. A separate job receives only the
   rendered body and has `issues: write` to upsert the comment.

This keeps a fork PR from obtaining a write-capable token. The comment workflow
never trusts a PR number, raw Markdown, shell command, or link supplied by the
artifact. If a report is missing or invalid, it posts a short failure message
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
