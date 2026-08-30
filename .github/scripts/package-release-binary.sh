#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 3 ]]; then
    echo "usage: $0 <target> <static-swift-stdlib:true|false> <output-directory>" >&2
    exit 64
fi

target="$1"
static_swift_stdlib="$2"
output_directory="$3"

case "$target" in
    macos-arm64)
        expected_architecture="arm64"
        ;;
    macos-x86_64)
        expected_architecture="x86_64"
        ;;
    linux-x86_64)
        expected_architecture="x86-64"
        ;;
    *)
        echo "unsupported release target: $target" >&2
        exit 64
        ;;
esac

build_arguments=(-c release --product what-coverage)
if [[ "$static_swift_stdlib" == "true" ]]; then
    build_arguments+=(--static-swift-stdlib)
fi

swift build "${build_arguments[@]}"
binary="$(swift build -c release --show-bin-path)/what-coverage"
test -x "$binary"

case "$(uname -s)" in
    Darwin)
        test "$(uname -m)" = "$expected_architecture"
        file "$binary" | grep -Fq "$expected_architecture"
        xcrun vtool -show-build "$binary" | grep -Eq 'minos 13(\.0)?'
        ;;
    Linux)
        file "$binary" | grep -Fq "$expected_architecture"
        ldd "$binary" | grep -Fq 'libc.so.6'
        ! ldd "$binary" | grep -Eiq 'lib(swift|Foundation).*\.so'
        glibc_floor="$(readelf --version-info "$binary" | grep -oE 'GLIBC_[0-9.]+' | sort -Vu | tail -n1)"
        test "$glibc_floor" = "GLIBC_2.35"
        ;;
    *)
        echo "unsupported build host: $(uname -s)" >&2
        exit 1
        ;;
esac

mkdir -p "$output_directory/stage"
cp "$binary" "$output_directory/stage/what-coverage"
archive="$output_directory/what-coverage-$target.tar.gz"
tar -C "$output_directory/stage" -czf "$archive" what-coverage
(cd "$output_directory" && sha256sum "$(basename "$archive")" > "$(basename "$archive").sha256")

smoke_directory="$(mktemp -d)"
trap 'rm -rf "$smoke_directory"' EXIT
tar -C "$smoke_directory" -xzf "$archive"
"$smoke_directory/what-coverage" --help >/dev/null
