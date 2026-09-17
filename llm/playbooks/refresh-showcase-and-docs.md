# Refresh Showcase And Docs

## Use When

Use this playbook when a public API, package target, or user-facing demo changes.

## Steps

1. Update the relevant source files.
2. Update `Examples/LMShowcase` if the concept should be visible in the demo.
3. Regenerate the Xcode project:

```sh
xcodegen generate --spec Examples/LMShowcase/project.yml
```

4. Run:

```sh
swift build
swift test
```

5. Update durable docs in `docs/`.
6. Update agent routing in `llm/` only when file ownership or playbooks change.

## Generated Output

Do not commit generated `.xcodeproj` files.

## Read Next

- `../../docs/README.md`
- `../capabilities/repo-map.md`
