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

The generated bundle is intentionally not checked in. Unit tests use the small
captured archive JSON in `Tests/CoverageReadersTests/Fixtures` and scripted
process results.
