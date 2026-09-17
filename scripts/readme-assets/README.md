# README assets

The images in [`docs/assets/readme`](../../docs/assets/readme) and the generated
blocks in the [README](../../README.md) come from real SwiftLM output. This
package builds them. After a change that affects them, run it from the
repository root:

```bash
swift run --package-path scripts/readme-assets ReadmeAssets
```

It writes the SVG images and replaces each block between
`<!-- readme-assets:begin NAME -->` and `<!-- readme-assets:end NAME -->` in the
README. `./scripts/validate.sh` runs the same command with `--check`, which
writes nothing and fails when:

- an image or a generated block differs from what the package produces now,
- a Swift block in the README is not a compiled snippet, or a snippet is not in
  the README,
- `docs/assets/readme` holds a file the generator does not make.

## How the output stays real

`Demo.swift` runs the package offline. Model replies are scripted: the
Foundation Models client is built from closures, and the Anthropic adapter gets
a transport that returns a recorded Messages API response. Everything else is
SwiftLM's own code, including routing, capability checks, request encoding,
response decoding, receipts, context compilation, and evaluation. The run ID,
timestamps, and durations are fixed afterward so the images change only when
behavior does, and the README says so next to the receipt.

`Snippets.swift` holds every Swift block the README shows, inside functions
that are compiled and never called. A line that starts with `//> ` is shown
without that prefix and is not compiled, which is how snippets show their
imports. The Package.swift blocks are the one exception, because a manifest
cannot compile inside a target. The custom model snippet needs the OS 27 SDK,
so it compiles only with Xcode 27, which CI runs.

The images are plain SVG in light and dark variants, drawn with system fonts so
they stay sharp and diff as text. The README shows them through `<picture>`
blocks whose alt text is each image's own label.

| File | What it does |
| --- | --- |
| `ReadmeAssets.swift` | The entry point: writes or checks every output |
| `Demo.swift` | The offline runs behind the images and the receipt |
| `Snippets.swift` | The README's Swift blocks, compiled |
| `Images.swift` | The mark, hero, flow, budget, and evaluation images |
| `Markdown.swift` | The capability tables, the receipt block, and the checks |
| `SVG.swift` | Colors, text measurement, drawing helpers, and Swift highlighting |

To look at the images the way GitHub shows them, render `README.md` through
GitHub's Markdown API in `markdown` mode, which is the mode README files use.
The `gfm` mode renders line breaks the way comments do.
