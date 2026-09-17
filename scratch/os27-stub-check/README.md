# OS 27 stub check

Compiles `SwiftLMFoundationModels` with the OS 27 SDK gate forced on against a stub of the
FoundationModels API transcribed from Apple's OS 27 documentation. It catches type and syntax
mistakes in the gated code when Xcode 27 is not installed. It is not a substitute for building with
Xcode 27, and the stub must be updated whenever the gated code touches new SDK symbols.

```sh
scratch/os27-stub-check/check.sh "$(git rev-parse --show-toplevel)"
```

The stub mirrors what the real SDK reported in CI: `PrivateCloudComputeLanguageModel.contextSize` is
`get async throws`, and `GenerationOptions(sampling:)` is deprecated in favor of the back-deployed
`init(samplingMode:)`. Delete this folder once the Xcode 27 CI job is GA and required.
