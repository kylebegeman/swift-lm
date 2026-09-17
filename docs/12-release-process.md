# Release Process

## Release Branches

Recommended branch model:

- `next`: active integration and private incubation
- `master`: production-ready baseline
- release branches only when a public release needs stabilization

## Pre-Release Checklist

Before any tag:

1. Confirm the license is final.
2. Confirm `SECURITY.md` has a real reporting path.
3. Run `./scripts/validate.sh`, which also checks that the README images, generated blocks, and snippets are current.
4. Build DocC documentation.
5. Review `CHANGELOG.md`.
6. Review `docs/09-roadmap.md` and mark completed work honestly.
7. Audit examples for private app data.
8. Audit tests and docs for raw prompts, transcripts, outputs, user identifiers, or API keys.
9. Confirm generated `.xcodeproj` files and local build artifacts are ignored.
10. Confirm package products and platform minimums are intentional.

## Tagging

Public tags should use semantic versioning:

```text
0.1.0
0.1.1
1.0.0
```

Private incubation tags can use release-candidate suffixes while changes are deployed before a full release:

```text
0.1.0-rc.1
0.1.0-rc.2
```

Increment the numeric `rc` suffix from the latest tag for each deployable candidate.

## Changelog Sections

Use these sections when the changelog grows beyond a single unreleased list:

- Added
- Changed
- Deprecated
- Removed
- Fixed
- Security

## Release Notes

Release notes should include:

- the intended audience
- the most important API additions or changes
- known limitations
- migration notes for source-breaking changes
- validation summary

Avoid broad capability claims. The package improves the reliability layer around on-device models; it does not make small local models equivalent to frontier cloud systems.

## Post-Release

After a public release:

1. Verify the tag is visible.
2. Verify package resolution from a clean sample app.
3. Verify the generated documentation link.
4. Open a tracking issue for the next minor release.
