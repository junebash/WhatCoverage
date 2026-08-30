#!/usr/bin/env bash
set -euo pipefail

usage() {
    echo "usage: $0 --version <version> [--prefix <directory>]" >&2
}

version=""
prefix="${HOME}/.local"
while [[ $# -gt 0 ]]; do
    case "$1" in
        --version)
            version="${2:-}"
            shift 2
            ;;
        --prefix)
            prefix="${2:-}"
            shift 2
            ;;
        *)
            usage
            exit 64
            ;;
    esac
done

if [[ ! "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    usage
    exit 64
fi

case "$(uname -s)-$(uname -m)" in
    Darwin-arm64)
        target="macos-arm64"
        ;;
    Darwin-x86_64)
        target="macos-x86_64"
        ;;
    Linux-x86_64)
        target="linux-x86_64"
        ;;
    *)
        echo "unsupported platform: $(uname -s)-$(uname -m)" >&2
        exit 1
        ;;
esac

release_url="https://github.com/junebash/WhatCoverage/releases/download/v$version"
archive="what-coverage-v$version-$target.tar.gz"
temporary_directory="$(mktemp -d)"
trap 'rm -rf "$temporary_directory"' EXIT

curl --fail --location --silent --show-error --output "$temporary_directory/$archive" "$release_url/$archive"
curl --fail --location --silent --show-error --output "$temporary_directory/SHA256SUMS" "$release_url/SHA256SUMS"

expected="$(awk -v archive="$archive" '$2 == archive { print $1 }' "$temporary_directory/SHA256SUMS")"
if [[ ! "$expected" =~ ^[[:xdigit:]]{64}$ ]]; then
    echo "missing checksum for $archive" >&2
    exit 1
fi

actual="$(shasum -a 256 "$temporary_directory/$archive" | awk '{ print $1 }')"
if [[ "$actual" != "$expected" ]]; then
    echo "checksum mismatch for $archive" >&2
    exit 1
fi

mkdir -p "$prefix/bin"
tar -C "$temporary_directory" -xzf "$temporary_directory/$archive"
install -m 755 "$temporary_directory/what-coverage" "$prefix/bin/what-coverage"
echo "Installed what-coverage v$version to $prefix/bin/what-coverage"
