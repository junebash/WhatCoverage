# WhatCoverage

WhatCoverage is a Swift command-line tool for reporting code coverage on lines
changed between Git revisions. It consumes existing coverage artifacts from
Xcode projects and Swift packages, then produces CI-neutral Markdown and JSON.

The `what-coverage` CLI reads LLVM exported JSON or Xcode `.xcresult` coverage,
compares changed lines, and writes Markdown and/or JSON reports. It never runs a
build or contacts a network service.

```sh
what-coverage \
  --input .build/debug/codecov/coverage.json \
  --base origin/main \
  --captured-source-root /builds/project \
  --markdown-output coverage.md \
  --json-output coverage.json \
  --minimum 80
```

`--format llvm` or `--format xcode` overrides inference (`.json` and
`.xcresult`, respectively). `--head` defaults to `HEAD`; `--comparison`
defaults to `merge-base` (`base...head`) and can be `direct` (`base..head`).
At least one output path is required. Exit statuses are 0 for success (including
not-applicable diffs), 2 for a failed threshold after reports are written, 64 for
an invalid invocation, 65 for coverage input failures, 66 for Git failures, and
74 for output failures.

Start with the
[project overview](Documentation/PROJECT.md), then see the
[requirements](Documentation/REQUIREMENTS.md),
[architecture](Documentation/ARCHITECTURE.md), and
[roadmap](Documentation/ROADMAP.md). Accepted and pending design choices live in
the [decision log](Documentation/DECISIONS.md).
