# Releases

WhatCoverage uses [Semantic Versioning](https://semver.org/) and releases from
the `main` branch through the [Release workflow](../.github/workflows/release.yml).
The repository has no version source file: Git tags and GitHub Releases are the
source of truth.

## Conventional Commits

Every commit merged to `main` must use the
[Conventional Commits](https://www.conventionalcommits.org/) format. The release
workflow analyzes the commit subjects since the last `v*` tag:

- `fix: ...` produces a patch release, such as `v0.1.0` to `v0.1.1`.
- `feat: ...` produces a minor release, such as `v0.1.0` to `v0.2.0`.
- `feat!: ...` or a `BREAKING CHANGE:` footer produces a major release.
- Other types, including `docs:`, `test:`, `build:`, and `chore:`, do not
  release by themselves.

Use the squash-merge title as the Conventional Commit when a pull request is
squash merged. A release is created only when at least one releasable commit has
reached `main`.

## Initial release

`v0.0.0` is a permanent bootstrap **Git tag**, not a published GitHub Release.
It points at the final pre-release-pipeline commit. It gives semantic-release a
pre-1.0 baseline, so the `feat(release): ...` commit that adds this pipeline
creates `v0.1.0` rather than semantic-release's default first `v1.0.0`.

Publish the bootstrap tag before pushing the release-pipeline commit to `main`:

```sh
git tag v0.0.0 <final-pre-pipeline-commit>
git push origin refs/tags/v0.0.0
git push origin main
```

The release workflow verifies that `v0.0.0` exists and is an ancestor of `HEAD`
before running. This prevents an accidental first `v1.0.0` release if the tag
was not pushed.

## What the workflow does

The workflow first builds native release executables on standard GitHub-hosted
runners: macOS arm64, macOS x86_64, and Linux x86_64. macOS builds use Xcode
26.3 and declare macOS 13 as their minimum deployment target. The Linux build
uses the digest-pinned Swift 6.2.1 Ubuntu 22.04 image with
`--static-swift-stdlib`; it is not a fully static binary, and its glibc 2.35
floor means the supported baseline is Debian 12/Ubuntu 22.04 x86_64. The exact
Linux archive is extracted and run in a clean Debian 12 container after build.

The release job only receives one-day retained build artifacts after every
matrix member and the Debian smoke test succeed. It fetches complete history,
installs the locked release tooling, and runs `semantic-release`. On a
releasable commit, its ordered prepare hook verifies the per-target checksums,
names the archives with the computed version, and creates `SHA256SUMS`. The
following GitHub plugin creates the annotated `v*` tag and exact GitHub Release
with generated notes, then attaches those prepared assets. There is no separate
release-upload workflow or tag trigger, so asset attachment cannot race release
creation. It publishes no npm package and does not comment on pull requests or
issues.

The workflow needs `contents: write`, which only its release job declares.
Build jobs receive `contents: read` only. Repository or organization Actions
settings must also allow the `GITHUB_TOKEN` to write contents. A failure after a
tag is created but before GitHub publication can leave a tag and possibly a
draft release; a semantic-release rerun may see no new version. Repair it
without moving the tag by verifying the prepared assets, then either publish the
matching draft or create/upload the release:

```sh
gh release view v0.1.0 || gh release create v0.1.0 --verify-tag --generate-notes --draft
gh release upload v0.1.0 what-coverage-v0.1.0-*.tar.gz SHA256SUMS --clobber
gh release edit v0.1.0 --draft=false
```

For a local dry run, use `npm ci && npx semantic-release --dry-run`. It checks
the next version and generated notes without creating a tag or release.
