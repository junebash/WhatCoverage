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

The workflow fetches complete history, installs the locked release tooling, and
runs `semantic-release`. On a releasable commit, it creates the annotated `v*`
tag and GitHub Release with generated notes. It publishes no npm package and
does not comment on pull requests or issues.

The workflow needs `contents: write`, which its job declares. Repository or
organization Actions settings must also allow the `GITHUB_TOKEN` to write
contents. A failure after a tag is created but before its GitHub Release exists
can be repaired without moving the tag:

```sh
gh release create v0.1.0 --verify-tag --generate-notes
```

For a local dry run, use `npm ci && npx semantic-release --dry-run`. It checks
the next version and generated notes without creating a tag or release.
