# Shared Views AGENTS.md

## Scope
- This file governs `Chops/Views/Shared/`.
- Treat this subtree as the home for reusable view primitives and cross-feature workflow surfaces.

## Primitive Versus Workflow Ownership
- Keep tiny reusable presentation elements small and dumb: badges, icons, markdown text wrappers, and thinking blocks.
- Let workflow-owning shared views keep their own local workflow state when they represent a complete reusable surface, such as `ComposePanel`, `RegistrySheet`, or diff review.
- Keep transport, persistence, and external integration logic in services; shared workflow views may coordinate those services, not replace them.

## Existing Shared Patterns
- Use `ToolIcon` and `ToolBadge` as the canonical tool identity primitives.
- Use `MarkdownMessageView` for compact assistant-text rendering rather than custom rich-text logic in each workflow.
- Use `ThinkingView` for collapsible reasoning state and keep it visually subordinate to the main answer.
- Use `DiffReviewPanel` for explicit reviewable file changes and keep diff computation off the main actor.
- Use `ComposePanel` as the reference pattern for inline assistant workflows: compact top bar, explicit connection state, chat transcript, explicit diff acceptance, and local dismissal behavior.
- Use `RegistrySheet` as the reference pattern for searchable install/browse flows that fetch external content and then apply a filesystem-backed install.
- Keep `ComposePanel` wired through `ACPConfiguration.shared`, `TemplateManager.shared`, and `ACPAgentFactory`. Do not fork assistant setup logic into feature-specific panels.
- Keep assistant-proposed writes reviewable by default: pending writes stay deferred until accept/reject unless ACP bypass mode is explicitly in effect.

## UI Consistency
- Keep shared workflow panels compact, technical, and low-chrome.
- Keep monospaced text in diffs, logs, raw previews, and machine-readable content.
- Use grouped backgrounds, separators, and small controls rather than heavy card systems.
- Prefer explicit accept/reject actions over silent mutation when a workflow proposes file changes.
- Keep long-running shared workflow work visibly stateful with progress, connection, or “thinking” affordances instead of hidden background transitions.

## Never
- Never let a shared workflow silently mutate files if the current pattern requires review, except for explicit bypass modes already defined by ACP session configuration.
- Never duplicate tool badges, diff UIs, or assistant-message formatting in feature-specific code when a shared implementation already exists here.
- Never move ACP session transport or registry fetching into view code that should stay reusable and presentation-oriented.

## Validation
- After editing this subtree, verify the full reusable workflow that changed, not just the individual view in isolation.
