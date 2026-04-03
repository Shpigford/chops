# Utilities AGENTS.md

## Scope
- This file governs `Chops/Utilities/`.
- Keep this folder for stateless transformations, parsing helpers, and rendering utilities that can be reused from services and views.

## Always
- Keep utility APIs deterministic and side-effect-light.
- Keep parser output shapes small and explicit so services and views can compose them predictably.
- Keep markdown and frontmatter parsing behavior compatible with the document formats the rest of the app already scans and edits.
- Keep resource lookup and rendering logic resilient to bundle layout while remaining local to the renderer utility.

## Existing Patterns To Preserve
- `FrontmatterParser` owns the basic `---` frontmatter contract and returns typed `ParsedSkill` data.
- `MDCParser` stays a narrow rule-file adapter rather than a second full parser stack.
- `MarkdownRenderer` owns markdown-to-HTML conversion and code highlighting for preview surfaces.
- Utilities do not own app state, file watching, SwiftData, or view presentation.

## Never
- Never add `AppState`, `ModelContext`, or network/process dependencies to this folder.
- Never move workflow-specific decision logic here just because multiple call sites need it once.
- Never let utility helpers silently redefine the source format in ways the scanner, editor, and preview layers do not all agree on.

## Validation
- After editing this folder, verify every consumer that depends on the changed transformation, especially scanner parsing and detail preview rendering.
