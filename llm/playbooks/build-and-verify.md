# Build And Verify

## Use When

Use this playbook when building, testing, or checking the showcase.

## Commands

```sh
swift build
swift test
swift build -Xswiftc -warnings-as-errors
./scripts/validate.sh
```

`swift test` exercises the Foundation Models adapter through fakeable closures, so it does not require the Foundation Models framework to be present locally.

Open the generated showcase manually when UI changes matter:

```sh
xcodegen generate --spec Examples/LMShowcase/project.yml
open Examples/LMShowcase/LMShowcase.xcodeproj
```

## Generated Files

Generated `.xcodeproj` files are ignored and should not be committed.

`./scripts/validate.sh` runs the package build, package tests, the README asset check, `llm/manifest.json` JSON/path validation, XcodeGen generation when available, and an unsigned showcase build when `xcodebuild` is available.

## README Assets

The README images in `docs/assets/readme`, its generated blocks, and its Swift snippets come from
`scripts/readme-assets`. After changing public API, routing, receipts, context compilation,
evaluation, or capability values, regenerate them:

```sh
swift run --package-path scripts/readme-assets ReadmeAssets
```

`--check` writes nothing and fails on drift; `validate.sh` runs it. A README Swift block must match
a marked region in `Snippets.swift`, which compiles against the package. See
`scripts/readme-assets/README.md`.

## Command Line Tools Only

`./scripts/validate.sh` also works when only Command Line Tools are selected (`xcode-select -p`
ends in `CommandLineTools`). It points `swift test` at the Swift Testing framework that ships in
Command Line Tools and skips the iOS showcase build, which needs Xcode. To run the tests by hand in
that setup, pass the same flags the script uses.

## OS 27 Gate

The OS 27 Foundation Models symbols compile only with Xcode 27 (Swift 6.4). With Xcode 26 the gated
blocks are inactive, so a green build does not prove they compile.

CI covers both sides: the `Xcode 26` job builds on `macos-26` with Xcode 26.6, and the `Xcode 27`
job builds on GitHub's `xcode-27` preview image (macOS 27 with the OS 27 SDKs). Both jobs also build
the package for iOS, visionOS, and watchOS with `xcodebuild` and warnings as errors. The Xcode 27 job
is non-blocking while that image is a preview with a beta Xcode, so read its result explicitly.

Without Xcode 27 locally, `scratch/os27-stub-check/check.sh <repo-root>` compiles
`SwiftLMFoundationModels` with the gate forced on against a stub of Apple's documented OS 27 API.

## Common Failures

- XcodeGen is not installed.
- The active Xcode toolchain does not include the required 26 SDKs.
- Foundation Models APIs changed in a new SDK. Check the gated blocks in `FoundationModelLive.swift` first.
- The README asset check failed after an intended change. Regenerate the assets, review the image diff, and commit it.

## Read Next

- `../capabilities/repo-map.md`
- `../../docs/10-open-source-readiness.md`
