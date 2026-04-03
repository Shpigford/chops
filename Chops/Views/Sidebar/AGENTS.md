# Sidebar Views AGENTS.md

## Scope
- This file governs `Chops/Views/Sidebar/`.
- Treat this subtree as the owner of library navigation, high-level filtering, collection navigation, and list-driven selection into the detail pane.

## Navigation Model
- Keep `SidebarFilter` as the authoritative navigation mode enum for library-wide selection state.
- Keep the current section structure legible: Library, Tools, Servers, Collections.
- Keep badges and counts visible. They are part of the information scent of this app shell.
- Keep tool visibility driven by real indexed content and `ToolSource.listable`, not by a static sidebar list.

## List And Filter Rules
- Keep `SkillListView` as the owner of list-level filtering, row context actions, toolbar actions, and selection repair when filters change.
- Keep list filtering in memory over the existing `@Query` result unless the repository intentionally redesigns search and indexing. Do not bolt a second search backend onto this subtree casually.
- Keep current filter semantics aligned across shell and list: kind filters, favorites, collection membership, server scope, tool scope, and text search should continue to compose predictably.
- Keep row actions explicit and immediate: favorite toggles, collection membership, show in Finder, make global, and delete all save at the action boundary.
- Preserve drag-and-drop into collections as a sidebar/list interaction pattern.
- Keep server actions limited to explicit user-triggered sync/test affordances that call existing services. Do not make the sidebar its own sync coordinator.

## UI Consistency
- Keep sidebar and list rows compact and badge-forward.
- Reuse `ToolIcon` and existing system symbols for type signaling.
- Keep empty states in `ContentUnavailableView` style instead of custom placeholders.
- When adding a new navigation mode for a sibling-app shell, fit it into the same selection-and-badge model instead of inventing a second navigation state system.

## Never
- Never duplicate sidebar selection state outside `AppState`.
- Never move scan or sync orchestration into the sidebar beyond kicking existing service calls from explicit user actions.
- Never fork search semantics between the sidebar/list path and other library surfaces without an intentional product-wide change.

## Validation
- After editing this subtree, verify sidebar counts, filter behavior, selection persistence, empty states, context menus, and any server or collection interactions you touched.
