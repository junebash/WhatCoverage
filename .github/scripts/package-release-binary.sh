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

build_arguments=(-c release)
if [[ "$static_swift_stdlib" == "true" ]]; then
    build_arguments+=(--static-swift-stdlib)
fi

swift build "${build_arguments[@]}" --product what-coverage
swift build "${build_arguments[@]}" --product what-coverage-pr-comment
binary_directory="$(swift build -c release --show-bin-path)"
binaries=("$binary_directory/what-coverage" "$binary_directory/what-coverage-pr-comment")
for binary in "${binaries[@]}"; do
    test -x "$binary"
done

case "$(uname -s)" in
    Darwin)
        test "$(uname -m)" = "$expected_architecture"
        for binary in "${binaries[@]}"; do
            file "$binary" | grep -Fq "$expected_architecture"
            xcrun vtool -show-build "$binary" | grep -Eq 'minos 13(\.0)?'
        done
        ;;
    Linux)
        for binary in "${binaries[@]}"; do
            file "$binary" | grep -Fq "$expected_architecture"
            ldd "$binary" | grep -Fq 'libc.so.6'
            ! ldd "$binary" | grep -Eiq 'lib(swift|Foundation).*\.so'
            glibc_floor="$(readelf --version-info "$binary" | grep -oE 'GLIBC_[0-9.]+' | sort -Vu | tail -n1)"
            test "$(printf '%s\n' "$glibc_floor" GLIBC_2.35 | sort -Vu | tail -n1)" = "GLIBC_2.35"
        done
        ;;
    *)
        echo "unsupported build host: $(uname -s)" >&2
        exit 1
        ;;
esac

mkdir -p "$output_directory/stage"
cp "${binaries[@]}" "$output_directory/stage/"
archive="$output_directory/what-coverage-$target.tar.gz"
tar -C "$output_directory/stage" -czf "$archive" what-coverage what-coverage-pr-comment
(cd "$output_directory" && sha256sum "$(basename "$archive")" > "$(basename "$archive").sha256")

smoke_directory="$(mktemp -d)"
trap 'rm -rf "$smoke_directory"' EXIT
tar -C "$smoke_directory" -xzf "$archive"
"$smoke_directory/what-coverage" --help >/dev/null
"$smoke_directory/what-coverage-pr-comment" --help >/dev/null
mkdir -p "$smoke_directory/repository/Sources"
printf 'covered\nuncovered\n' > "$smoke_directory/repository/Sources/App.swift"
cat > "$smoke_directory/report.json" <<'JSON'
{"schemaVersion":1,"coverageInput":{"kind":"xcode"},"comparison":{"resolvedHead":"head"},"policy":{"status":"failed","threshold":100,"actual":50},"totals":{"covered":1,"uncovered":1,"executable":2,"percentage":50},"wholeProjectCoverage":{"covered":1,"uncovered":1,"executable":2,"percentage":50},"files":[{"path":"Sources/App.swift","counts":{"covered":1,"uncovered":1,"executable":2,"percentage":50},"coveredLines":[1],"uncoveredLines":[2]}]}
JSON
touch "$smoke_directory/another-file"
"$smoke_directory/what-coverage-pr-comment" render \
    --report "$smoke_directory/report.json" \
    --head head \
    --repo-root "$smoke_directory/repository" \
    --run-url https://ci.example/run \
    --output "$smoke_directory/comment.md"
grep -Fq '<!-- whatcoverage:pr-report:v1 -->' "$smoke_directory/comment.md"
grep -Fq '<summary>Uncovered source (1 lines)</summary>' "$smoke_directory/comment.md"
