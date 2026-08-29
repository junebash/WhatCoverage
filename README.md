# WhatCoverage

WhatCoverage is a Swift command-line tool for reporting code coverage on lines
changed between Git revisions. It consumes existing coverage artifacts from
Xcode projects and Swift packages, then produces CI-neutral Markdown and JSON.

The library implementation now provides a normalized coverage model, pure
diff-coverage calculation, Git changed-line discovery, LLVM and Xcode coverage
inputs, and provider-neutral Markdown and versioned JSON rendering. The
user-facing CLI remains roadmap work.

Start with the
[project overview](Documentation/PROJECT.md), then see the
[requirements](Documentation/REQUIREMENTS.md),
[architecture](Documentation/ARCHITECTURE.md), and
[roadmap](Documentation/ROADMAP.md). Accepted and pending design choices live in
the [decision log](Documentation/DECISIONS.md).
