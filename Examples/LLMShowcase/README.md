# LLMShowcase

This XcodeGen app demonstrates SwiftLLM primitives in a small iOS shell.

Current panels show on-device model availability and context window, Private Cloud Compute readiness (context window, reasoning, quota, and availability), provider routing options, token budgeting, structured schema metadata, text and transcript chunking, local retrieval with packed citation context, and prompt evaluation report metadata.

Generate the project with:

```sh
xcodegen generate --spec Examples/LLMShowcase/project.yml
```

The generated `.xcodeproj` is ignored and should not be committed.
