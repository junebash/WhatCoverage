#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 2 ]]; then
    echo "usage: $0 <version> <package-directory>" >&2
    exit 64
fi

version="$1"
package_directory="$2"
release_directory="dist/release"

case "$version" in
    [0-9]*.[0-9]*.[0-9]*) ;;
    *)
        echo "invalid semantic-release version: $version" >&2
        exit 64
        ;;
esac

rm -rf "$release_directory"
mkdir -p "$release_directory"

for target in macos-arm64 macos-x86_64 linux-x86_64; do
    source_archive="$package_directory/what-coverage-$target.tar.gz"
    source_checksum="$source_archive.sha256"
    test -f "$source_archive"
    test -f "$source_checksum"
    (cd "$package_directory" && sha256sum --check "$(basename "$source_checksum")")

    destination_archive="$release_directory/what-coverage-v$version-$target.tar.gz"
    cp "$source_archive" "$destination_archive"
done

(cd "$release_directory" && sha256sum what-coverage-v*.tar.gz > SHA256SUMS)
