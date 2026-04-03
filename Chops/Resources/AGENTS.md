# Resources AGENTS.md

## Scope
- This file governs `Chops/Resources/`.
- Treat this folder as the bundled visual and static-resource layer consumed by the app at runtime.

## Existing Contracts
- Keep asset names stable when code references them directly. `ToolSource.logoAssetName` expects the `tool-*` image-set names exactly.
- Keep tool logos visually consistent with the existing set: simple mark-only assets sized for small sidebar/icon use, with SVG sources tracked alongside `Contents.json`.
- Keep `AccentColor` and asset-catalog structure standard unless a deliberate cross-app visual refresh is being applied.

## Always
- Add a matching code mapping when adding a new tool logo or other code-addressed resource.
- Keep resource naming predictable and code-friendly; prefer the existing `tool-<name>` pattern for tool-specific assets.
- Treat bundled non-code resources as load-path contracts. If code looks up a subdirectory or filename through `Bundle.main`, preserve that path shape exactly.
- When adding future bundled templates or content resources, wire them intentionally and keep any hardcoded fallback behavior in sync with the bundled version.

## Never
- Never rename or remove an asset-catalog entry that is referenced from `ToolSource` without updating the code in the same change.
- Never assume a file is bundled just because code has a fallback lookup. Check whether the resource actually exists under `Chops/Resources/`.
- Never put workflow logic in this folder.

## Validation
- After editing this folder, verify that the affected resources still load in the app and that every renamed resource still matches its code reference.
