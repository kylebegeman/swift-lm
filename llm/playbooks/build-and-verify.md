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
xcodegen generate --spec Examples/LLMShowcase/project.yml
open Examples/LLMShowcase/LLMShowcase.xcodeproj
```

## Generated Files

Generated `.xcodeproj` files are ignored and should not be committed.

`./scripts/validate.sh` runs the package build, package tests, `llm/manifest.json` JSON/path validation, XcodeGen generation when available, and an unsigned showcase build when `xcodebuild` is available.

## Command Line Tools Only

`./scripts/validate.sh` also works when only Command Line Tools are selected (`xcode-select -p`
ends in `CommandLineTools`). It points `swift test` at the Swift Testing framework that ships in
Command Line Tools and skips the iOS showcase build, which needs Xcode. To run the tests by hand in
that setup, pass the same flags the script uses.

## OS 27 Gate

The OS 27 Foundation Models symbols compile only with Xcode 27 (Swift 6.4). With Xcode 26 the gated
blocks are inactive, so a green build does not prove they compile. Until Xcode 27 is installed,
`scratch/os27-stub-check/check.sh <repo-root>` compiles `SwiftLLMFoundationModels` with the gate
forced on against a stub of Apple's documented OS 27 API.

## Common Failures

- XcodeGen is not installed.
- The active Xcode toolchain does not include the required 26 SDKs.
- Foundation Models APIs changed in a new SDK. Check the gated blocks in `FoundationModelLive.swift` first.

## Read Next

- `../capabilities/repo-map.md`
- `../../docs/10-open-source-readiness.md`
