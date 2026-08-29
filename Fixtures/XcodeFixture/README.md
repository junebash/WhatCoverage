# Xcode coverage fixture

This small Swift package reproducibly generates an Xcode result bundle on a
macOS host with Xcode 16 or newer:

```sh
rm -rf .build/XcodeFixture.xcresult
xcodebuild test \
  -scheme XcodeFixture \
  -destination 'platform=macOS' \
  -enableCodeCoverage YES \
  -resultBundlePath .build/XcodeFixture.xcresult
xcrun xccov view --archive --json .build/XcodeFixture.xcresult
```

The generated bundle is intentionally not checked in. The archive format was
last verified with Xcode 26.3: its reduced capture in
`Tests/CoverageReadersTests/Fixtures/xccov-archive-xcode-26.3.json` drives a
reader-to-diff-calculator test containing one covered and one uncovered changed
line. The matching metadata capture tests archive discovery. A macOS CI smoke
test also generates a fresh bundle and invokes the CLI against a real Git diff.
Unit tests use compact captures rather than committing the result bundle.
