# WhatCoverage

WhatCoverage is a Swift command-line tool for reporting code coverage on lines
changed between Git revisions. It consumes existing coverage artifacts from
Xcode projects and Swift packages, then produces CI-neutral Markdown and JSON.

The first implementation slice now provides separate Swift library modules for
the normalized coverage model, pure diff-coverage calculation, Git changed-line
discovery, and LLVM exported-JSON input. The user-facing CLI, Xcode result-bundle
input, and Markdown/JSON rendering remain roadmap work.

Start with the
[project overview](Documentation/PROJECT.md), then see the
[requirements](Documentation/REQUIREMENTS.md),
[architecture](Documentation/ARCHITECTURE.md), and
[roadmap](Documentation/ROADMAP.md). Accepted and pending design choices live in
the [decision log](Documentation/DECISIONS.md).
