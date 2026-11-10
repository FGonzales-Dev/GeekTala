# Noote — Decisions & Plan

## 1. Overview

**Noote** is an offline-first note-taking app for **macOS, Windows, Linux, iOS, Android, and Web**, built as a single Flutter codebase, with sync to a central database, rich note formatting, photo attachments, and folder/note sharing & co-authoring.

---

## 2. Core Stack Decisions

| Area | Decision | Why |
|---|---|---|
| Cross-platform framework | **Flutter** (targets: macOS, Windows, Linux, iOS, Android, **Web**) | Single codebase for all 6 targets; mature SQLite tooling; strong offline story; Flutter Web is a first-class build target alongside the rest |
| State management | **Riverpod** | Pairs naturally with Drift's reactive streams; less boilerplate than Bloc for this use case |
| Local database | **Drift** (SQLite wrapper) — native SQLite on desktop/mobile, **`drift_wasm` (sql.js/OPFS-backed) on Web** | Type-safe, code-gen, reactive queries; Drift has a dedicated web backend so the same DAO/repository code works unmodified — only the database initialization differs per platform |
| Backend database | **Supabase (Postgres)** | Relational model suits notes/folders/tags/sharing, built-in Row Level Security for permissions |
| Backend business logic | **Postgres stored procedures (plpgsql), called via Supabase RPC — no direct table writes from the client** | Centralizes validation, permission checks, and conflict-merge logic (see §6) atomically inside Postgres instead of scattering it across the Flutter app and its sync code; the client/sync surface becomes a thin set of RPC calls. See §5 for the procedure list and §4 for where this plugs into the sync layer |
| Sync engine | **None — app code: local outbox + `push_changes` RPC** *(replaced PowerSync 2026-11-09)* | No extra service to host or pay for. SQLite triggers log every local change to an outbox; **Upload** sends it to one Postgres function in batches, **Download** replaces local data with the server copy (plain Supabase queries under RLS). Manual (buttons in Settings) for now — see §6. Works on web too, since it's only Supabase + Drift calls |
| Auth | **Supabase Auth** | Native pairing with Supabase; same flow works on web via redirect/PKCE |
| Navigation | **go_router** | Declarative, URL-based; handles desktop window states and deep-linking better than manual Navigator 2.0 — also gives Web real, shareable URLs per note/folder "for free" |
| Model classes | **freezed** | Immutability + copyWith, useful when sync callbacks update fields |
| Rich text editor | **appflowy_editor** (6.x) | Tree-based node model (supports nesting for lists/tables, unlike flat-list editors); core ships paragraph, headings, lists, quote, todo, table, image, and divider block components; supports markdown import/export and construction from JSON/Markdown/Quill Delta; **confirmed web platform support** |
| Code blocks | **Custom block component**, built on the `highlight` package | Revised 2026-08-19: the standalone `appflowy_code_block` plugin is unmaintained (last published 2 years ago, pinned to `appflowy_editor ^2.3.3` and `intl ^0.18.x`) and fails to resolve against current `appflowy_editor` 6.x (`intl ^0.20.x`). Code blocks are **not** a core block type in appflowy_editor 6.x either — confirmed against the current `lib/src/editor/block_component/` source, which only has paragraph/heading/list/quote/todo/table/image/divider. Plan: write our own `CodeBlockComponentBuilder` (AppFlowy Editor's block component system is designed to be extended this way — see `image_block_widget.dart` in §4 for the same pattern already planned for images) using `highlight` directly for syntax highlighting, same as the abandoned plugin did internally. No plugin package needed. |
| Photo storage | **Supabase Storage** (local-first cache + background upload queue) | Decoupled from row-level sync since it's blob data, not structured data; on Web, "local cache" uses browser storage (see §7) instead of a filesystem path |
| UI font | **Inter** | Clean, highly legible at small sizes, screen-optimized, wide weight range, free/open — standard choice for neutral off-white/grey UI in both light and dark mode |
| Monospace font (code blocks) | **JetBrains Mono** | Clear character distinction (0/O, 1/l/I), free/open |

---

## 3. Design & Theming

**Palette: off-white / greyscale, no accent-heavy branding — light and dark mode both required.**

Canonical values, as implemented in `noote-ui-concepts.html` (source of truth — kept in sync with `core/theme/` if either changes):

| Token | Light mode | Dark mode |
|---|---|---|
| `bg` (base background) | `#FAFAF7` | `#121212` |
| `surface` | `#FFFFFF` | `#1C1C1C` |
| `surfaceAlt` (sidebar, chips, code lang label) | `#F2F1EE` | `#202020` |
| `surfaceRaised` | `#FBFBF9` | `#232323` |
| `border` | `#E4E3DF` | `#2C2C2A` |
| `borderSoft` (list dividers) | `#EDEDE9` | `#252523` |
| `text` (primary) | `#1A1A18` | `#EDEDEA` |
| `textMuted` (secondary) | `#6B6B66` | `#9A9A94` |
| `textFaint` (timestamps, placeholders) | `#A3A39D` | `#68685F` |
| `focus` | `#8A8D91` | `#7C8085` |
| `selectionBg` | `#ECEBE7` | `#262624` |
| `activeBg` (active nav item) | `#F0EFEB` | `#242422` |
| `codeBg` | `#F4F3F0` | `#181818` |
| `codeBorder` | `#E6E5E1` | `#2A2A28` |
| `avatar1` / `avatar2` / `avatar3` (collaborator avatar backgrounds) | `#9CAF9A` / `#9AAAB8` / `#C2A490` | `#7C9A78` / `#7C93A6` / `#AC8B72` |
| Radius | `10px` default, `6px` small | (same both modes) |

Notes:
- Keep the palette strictly neutral (grey scale with warm-off-white undertone, not blue-grey) — the avatar colors above are the one deliberate exception (§ note in the original draft), used only for collaborator identity, never as a UI accent color.
- Respect system-level light/dark preference by default (`ThemeMode.system`), with a manual override in Settings.
- Define both palettes as Flutter `ColorScheme`s plus a `ThemeExtension<NooteColors>` for the tokens above that don't map onto `ColorScheme`'s standard roles, centralized in `core/theme/` — never hardcode hex values in feature widgets.

**Typography:**

| Use | Font | Notes |
|---|---|---|
| UI (navigation, buttons, note titles, body text) | **Inter** | Variable weight range (400–600 covers most UI needs); via `google_fonts` package or bundled locally to avoid a network fetch on first load |
| Code blocks | **JetBrains Mono** | Register as the font for the custom `CodeBlockComponentBuilder` (§2) specifically, not app-wide |

Alternative pairing if a slightly warmer, more distinct look is wanted later: **IBM Plex Sans** (UI) + **IBM Plex Mono** (code) — same type family, guaranteed to pair well, a bit more character than Inter.

Implementation note: bundle fonts as local assets (`assets/fonts/`) rather than fetching via `google_fonts` at runtime — this matters more than usual here since the app must work fully offline, including on first launch before any network call has ever succeeded.

---

## 4. Architecture Pattern

**Feature-first, layered (MVVM-ish) with Riverpod.** Not strict Clean Architecture (too much ceremony for this scope) and not pure MVC (doesn't map to Flutter's reactive model).

```
lib/
  core/
    theme/
    router/                    # go_router
    utils/
  data/
    database/
      app_database.dart        # Drift database definition
      tables/                  # notes.dart, folders.dart, tags.dart, attachments.dart, shares.dart
      daos/                    # NotesDao, FoldersDao, etc.
    sync/
      sync_service.dart          # upload: outbox -> push_changes RPC (never raw table writes); download: replace local copy
      sync_remote.dart           # Supabase calls behind an interface (faked in tests)
      pending_writes.dart        # flushes the editor's debounced saves before a sync
    repositories/
      notes_repository.dart        # wraps DAO, exposes clean streams, hides Drift details
      folders_repository.dart
      attachments_repository.dart  # local cache + upload queue
      sharing_repository.dart      # folder_shares / note_shares CRUD
    services/
      markdown_converter.dart      # import/export, wraps appflowy_editor's markdown support
  features/
    notes_list/
      providers/
      widgets/
      notes_list_screen.dart
    note_editor/
      providers/
      widgets/
        image_block_widget.dart    # custom node renderer, shows upload state
        code_block_widget.dart     # custom CodeBlockComponentBuilder, wraps `highlight` (see §2 — no plugin package)
      note_editor_screen.dart
    folders/
    sharing/
      providers/
      widgets/
        share_sheet.dart           # invite by email, set role
        permission_badge.dart      # shown on shared folders/notes
    settings/
      sync_status/
      account/
  app.dart
  main.dart
```

**Layer responsibilities:**

| Layer | Owns | Never does |
|---|---|---|
| Drift tables/DAOs | Schema, raw queries | Business logic |
| Repositories | Combine DAOs + expose clean streams/futures | Know about widgets |
| Riverpod providers/notifiers | Screen-level state, loading/error handling | Direct DB/SQL access |
| Widgets | Render state, dispatch user actions | Business logic, DB access |
| Sync layer | `SyncService` (outbox upload, full download, account switching), `SupabaseSyncRemote`, sync status | UI concerns |
| Postgres (stored procedures) | Validation, permission checks, block-level conflict merge, all row mutations | Own client-side state; never called directly by widgets/providers — only reached via the sync connector's upload path |

Note: reads are unaffected by this — Download reads the tables directly, limited to the caller's rows by RLS (see §6), not via RPC. The stored-procedure requirement applies to **writes only**: every insert/update/delete that reaches Postgres, whether from the app or (later) any admin tooling, goes through a named procedure, never a bare `INSERT`/`UPDATE`/`DELETE` against a table from client code.

---

## 5. Data Model

```
notes
  id (uuid, pk)
  folder_id (uuid, fk, nullable)
  title (text)
  body_json (jsonb)          -- AppFlowy Editor document tree (blocks, incl. tables/code/images by reference)
  created_at, updated_at (datetime)
  is_deleted (bool)          -- tombstone, not hard delete
  device_id (text)
  version / hlc (for conflict tracking)

folders
  id, name, parent_id, owner_id, updated_at, is_deleted

tags
notes_tags (join table)

attachments
  id, note_id, storage_path, local_cache_path
  status (pending_upload | uploaded | failed)
  created_at

folder_shares
  folder_id, user_id, role (viewer | editor | owner)

note_shares                  -- override for one-off note sharing outside folder permissions
  note_id, user_id, role
```

Notes:
- Each block/node inside `body_json` carries its own stable `id` and `updated_at` for block-level conflict merging.
- Permissions inherit down the folder tree by default; `note_shares` overrides for individual notes.
- Images are referenced by `attachment_id`, never inlined into `body_json`.

**Mutation access — stored procedures only:**

Every write in §4's "Postgres (stored procedures)" layer is one of these `SECURITY DEFINER` plpgsql functions, called via Supabase RPC (`.rpc(...)`), defined as SQL migrations in `supabase/migrations/` (see §9). No table in this section is ever written to directly by client code.

```
notes:        upsert_note(note_id, folder_id, title, body_patch, client_updated_at)  -- see §6 for merge behavior
              delete_note(note_id)                          -- sets is_deleted tombstone
              move_note(note_id, target_folder_id)

folders:      upsert_folder(folder_id, name, parent_id)
              delete_folder(folder_id)                       -- tombstone; cascades to contained notes' visibility, not their rows

tags:         upsert_tag(tag_id, name)
              attach_tag(note_id, tag_id)
              detach_tag(note_id, tag_id)

attachments:  register_attachment(attachment_id, note_id, storage_path)  -- called on upload start
              mark_attachment_uploaded(attachment_id)
              mark_attachment_failed(attachment_id)

sharing:      share_folder(folder_id, user_id, role)
              share_note(note_id, user_id, role)
              revoke_folder_share(folder_id, user_id)
              revoke_note_share(note_id, user_id)
```

Each procedure re-checks the caller's permission (via `folder_shares`/`note_shares`, same source RLS reads from) before mutating — so permission logic lives in exactly one place rather than being duplicated between RLS policies and application code.

---

## 6. Sync & Conflict Resolution

> **What's built (2026-11-09):** manual, whole-row sync with no sync server — this replaces PowerSync and is simpler than the block-level design below, which remains the goal.
> - SQLite triggers (`lib/data/database/sync.drift`) log every local insert/update/delete into a `sync_outbox` table, one entry per record.
> - **Upload** (`lib/data/sync/sync_service.dart`) sends the outbox to `push_changes(jsonb)` in batches of ≤100; each batch is one server transaction, and outbox entries are removed only after the server accepts them.
> - Conflicts: **newest `updated_at` wins per note/folder** (device clock); older incoming edits are skipped and reported. No per-block merge yet.
> - **Download** replaces all local data with the server copy (paged reads under RLS) and refuses to run while changes are waiting to upload unless the user chooses to discard them.
> - Trash is a tombstone (`is_deleted`), as below. **Delete forever is a real delete** on the server too — with full-replace downloads nothing can "revive" it, and a tombstone would bring it back into the trash.
> - Primary keys are `(owner_id, id)`, so seeded ids like `personal` don't clash between accounts.
> - If a different account signs in on a device, its local data is cleared first (`SyncService.adoptAccount`).
> - **Automatic sync** (on by default; Settings → "Sync automatically"; `_AutoSync` in `lib/data/providers/sync_provider.dart`): uploads 5 s after changes appear (back-off on failure), uploads right away when the app goes to the background, and on open / sign-in / return after 5+ min uploads anything waiting then runs a full Download. A Download that finds new local edits is skipped (no editor reload). Still whole-copy downloads — fetching only what changed needs server-set timestamps on every table plus a deletion log.

**Chosen approach: V1 — Async co-editing (block-level last-write-wins)**

- Every write goes to the local Drift/SQLite database first — UI never waits on network.
- Each block/node has its own `updated_at`.
- On sync: if two users edited *different* blocks, merge cleanly. If the same block was edited by both, last-write-wins with a "conflicting edit" notice.
- Deletions use tombstones (`is_deleted`), never hard deletes, so they sync correctly instead of "reviving" on merge.
- **The merge itself runs inside `upsert_note` (§5), server-side.** The connector's `uploadData()` sends the changed blocks (not a whole-document overwrite) to `upsert_note`; the procedure compares each incoming block's `updated_at` against the stored block's `updated_at` and only replaces blocks that are actually newer. This makes the merge atomic and authoritative in Postgres regardless of network reordering — two devices racing to push conflicting edits can't have the "last request to arrive" silently clobber a newer block just because it happened to land second.

**Deferred (V2, not required for launch): true real-time collaboration**
- Would require wrapping the node tree in a CRDT (e.g. Yjs) plus a live transport (Supabase Realtime channels or a dedicated WebSocket server) for live cursors/presence.
- Explicitly scoped out of V1 — block-level merge covers "co-author a note/folder" for the common case (people editing while each is online, not literally the same second).

**Sharing/permissions enforcement:**
- Supabase **Row Level Security** policies enforce access based on `folder_shares` / `note_shares`.
- Download's queries are limited by those same RLS policies, so a user only pulls notes/folders they own or have been shared into.

**Testing requirement:** deliberately test conflict scenarios — airplane mode edits, two devices/users editing the same note, same table cell edited concurrently (must merge per-cell, not per-whole-table).

---

## 7. Feature-Specific Notes

### Rich formatting
- Bulleted/numbered lists, nested lists: native to AppFlowy Editor's tree-based node model.
- Tables (rows/columns): AppFlowy Editor table/grid node type.
- Markdown-style typing shortcuts (e.g. `` ``` `` → code block, `-` + space → bullet): built into AppFlowy Editor's shortcut event system, no extra package.

### Markdown import/export
- Separate from typing shortcuts — this is file-level conversion.
- Use AppFlowy Editor's built-in markdown import/export (JSON ⇄ Markdown).
- Add `markdown_converter.dart` service wrapping this.
- Features: "Import .md file" (notes list), "Export as Markdown" (note editor menu).
- **Import Folder…** (built 2026-11-09, desktop/mobile — not web): the notes list's import menu picks a folder and recreates it as a Noote folder with its subfolders; every `.md`/`.markdown`/`.txt` file becomes a note (title = file name, date = file modified time), in one transaction (`lib/features/note_editor/folder_import/`). Used to bring in an Apple Notes export (converted to Markdown outside the app via the Notes scripting dictionary — attachments aren't carried over).
- **Must verify round-trip fidelity** (JSON → Markdown → JSON) for tables and code blocks specifically before relying on it — markdown table syntax is more limited than the rich table node.
- **Pasting Markdown (built 2026-11-09):** ⌘V/Ctrl+V with text that looks like Markdown (`looksLikeMarkdown` in `markdown_convert.dart`) pastes it formatted, or as the raw text per Settings → "When pasting Markdown"; a bar over the editor then offers the other version until the next edit (swap = restore the pre-paste note and paste again). Other text pastes as before; ⌘⇧V still pastes raw. Mobile: "Paste Markdown" in the editor's ••• menu (the phone's paste menu bypasses the editor's paste shortcut). appflowy_editor's converter drops fenced code blocks, so `noteMarkdownToDocument` adds a parser for them (code-styled paragraph, until real code blocks exist) — used by import too.
- Not built yet: a whole-note Markdown source view (risk: Markdown can't hold text colors/highlights).

### Organizing notes and folders (built 2026-11-09)
- Desktop/web: drag a note (or a ⌘/Ctrl- or Shift-click selection of notes) from the notes list onto a sidebar folder, or onto Recently Deleted. Drag a folder onto another folder (middle of the row = inside it; top/bottom edge = above/below it, i.e. reorder), onto the "Folders" heading (first at the top level), or onto Recently Deleted (the usual delete dialog). Every move/delete shows an Undo snack bar. The sidebar auto-scrolls while dragging near its edges.
- Mobile: notes and folders are on separate tabs, so no dragging — the long-press menus have "Move to…" (a folder picker), also in the desktop right-click menus.
- Rules (`FolderTree.canMove`): a folder can't go into itself or its subfolders; Personal and Shared only move within the top level.
- Folder order is `folders.sort_order` (a fraction: a dropped folder gets the midpoint of its neighbours; the list is renumbered only when there's no room). A move is an ordinary edit (bumps `updated_at`), so sync needs nothing special.
- A folder whose parent is missing, or that's in a parent loop (two devices moved folders into each other), is shown at the top level instead of disappearing.

### Tags & settings (built 2026-11-09)
- Tags: right-click/long-press a tag in the sidebar, or in a note's tag picker (the way in on mobile) → Rename / Delete. Delete removes the tag from its notes (they stay) and offers Undo. Tag ids are derived from the name (uuid v5) so the same new tag on two devices merges; a new tag reusing a renamed tag's old name gets a random id instead.
- Device settings (theme, pane widths, paste-Markdown, auto sync) are remembered per device in the local `sync_state` key/value table (`deviceSettingsProvider`), never uploaded.

### Attachments — images (built 2026-11-10)
- A note refers to an image as an image block with `url: attachment://<uuid>.<ext>` (`lib/data/attachments/`). The file lives in the app's private data folder (`attachments/`) and in the private Supabase Storage bucket `attachments` under `<user id>/<id>` (migration `20261110090000_attachments.sql`: owner-only read/write, 50 MB, images only). A local `attachments_table` (schema v3) tracks which files still need uploading; it isn't synced — other devices learn about a file from the note and download it when it's first shown.
- Upload sends new files before any note changes and stops if one fails, so a note never reaches the server pointing at a missing file. Photos over 2,560 px are scaled down (EXIF orientation applied); pasted BMPs (Windows) become PNG.
- Adding: toolbar image button (desktop), the mobile toolbar's image icon, dragging image files into a note (desktop, `desktop_drop`), ⌘V of copied images or image files (`pasteboard`; text on the clipboard wins).
- `AttachmentImageBlockComponentBuilder` replaces appflowy's image block so `attachment://` images resolve to the device copy, downloading if needed (placeholder + "Try again" when offline).
- Unused files are removed from the device once per app run (`collectGarbage`, after a 10-minute grace period). Not built yet: other file types (PDFs, recordings), removing server copies of unused files, images in Export as Markdown, web support.
- Import Folder… brings in images linked by relative path (`![](_attachments/x.png)`) and skips folders that hold only such files. The Apple Notes export (outside the app) saves attachments through Notes' scripting; tables are attachments in Notes' model but already in the note text.

### Photo attachments
- Saved to local storage immediately on attach (offline-first, usable right away) — filesystem on native platforms, browser storage (IndexedDB/OPFS) on Web.
- Background upload queue to Supabase Storage, decoupled from the row sync (§6).
- Thumbnail generated on-device for list previews; full-res fetched on demand.
- On another device/browser: note body syncs first (fast/small); images show a loading/placeholder state until the attachment downloads.

### Code blocks
- No usable plugin exists (see §2) — build a custom `CodeBlockComponentBuilder`, registered in the block builder map same as any other custom node (pattern matches `image_block_widget.dart`).
- Use the `highlight` package directly for syntax highlighting inside the custom widget.
- Language stored as a node attribute so it round-trips through sync and markdown export.
- Decide on line numbers / copy button UX ourselves since there's no reference plugin implementation to inherit it from.

### Sharing & co-authoring
- Share a folder → applies to sub-folders/notes by inheritance.
- `note_shares` overrides for sharing an individual note outside its folder's permission set.
- Roles: viewer / editor / owner.

---

## 8. Platform-Specific Considerations

- **Linux**: packaging (`.deb`/Flatpak/AppImage) is the weak point — test early, not at the end.
- **macOS**: sandboxing/entitlements for file access and network can trip up first builds.
- **Desktop menu bars**: not free in Flutter — use `flutter_menu_bar` or platform channels for a proper native menu.
- **Web**:
  - **Local database**: use Drift's web backend (`drift_wasm`), backed by OPFS where available, falling back to IndexedDB — same DAOs/repositories as native, only the database-opening code differs (isolate this behind a small per-platform init function).
  - **File/attachment storage**: no filesystem access — the "local cache" for pending photo uploads lives in browser storage (IndexedDB/OPFS blobs) instead of a file path; `attachments.local_cache_path` becomes a browser-storage key on Web rather than a filesystem path. Abstract this behind `AttachmentsRepository` so the rest of the app doesn't care.
  - **Image picking/upload**: use `file_picker`/`image_picker`'s web support (browser file input) — works, but there's no native camera capture flow like mobile has.
  - **Auth**: Supabase Auth's redirect-based flow (PKCE) is required on web instead of the native deep-link flow used on mobile/desktop.
  - **PWA/installability**: decide whether to ship it as an installable PWA (manifest + service worker) — affects offline behavior specifically in the browser (service worker caching is separate from your Drift/outbox offline story and only affects asset loading, not data).
  - **Browser storage limits/eviction**: browsers can evict IndexedDB/OPFS data under storage pressure (especially without PWA installation) — worth surfacing a "last synced" indicator so users trust that a local wipe won't silently lose data once it's synced.

---

## 9. Local Development Environment

**Run the backend locally during development — don't touch the hosted Supabase project for day-to-day work.**

| Component | Local dev approach |
|---|---|
| Supabase | **Supabase CLI** (`supabase init`, `supabase start`) — spins up Postgres, Auth, Storage, Realtime, and Studio locally via Docker; no hosted project needed until deploying |
| Migrations | Supabase CLI migrations (`supabase migration new`, `supabase db push`) — `supabase/migrations/` is the source of truth, applied to local and hosted projects alike; table DDL and the stored procedures from §5 both live here |
| Seed data | `supabase/seed.sql` — realistic notes/folders/tags/shares fixtures loaded on every `supabase start` |
| Environment switching | Defaults point at the **production** project (changed 2026-11-09, so a build can't accidentally ship pointing at localhost); override `SUPABASE_URL` / `SUPABASE_PUBLISHABLE_KEY` with `--dart-define` or `--dart-define-from-file` (see `config/prod.example.json`) to use the local stack or another project |
| Requirements | Docker Desktop (or compatible), Supabase CLI (`brew install supabase/tap/supabase`) |

Notes:
- Local Supabase Studio (`http://localhost:54323` by default) is the fastest way to inspect rows/RLS while debugging sync.
- Author and test RLS policies and `push_changes` against the local stack first — much tighter iteration loop than against a hosted project, and mistakes here are cheap to fix locally vs. after real user data exists.
- Consider running `supabase start` in CI for integration tests against a real (local) Postgres instance rather than mocking the database layer.
- This slots in at Build Order step 6 below ("Wire up sync") — test against local Supabase before ever pointing at a hosted project.
- **Day-to-day startup** *(2026-11-09)*: just `supabase start`. The app works offline without it; Upload/Download need it running.

---

## 10. Build Order

1. **Scaffold**: `flutter create`, confirm builds on all 6 platforms early — including Web (`flutter run -d chrome`) — desktop and web quirks both surface fast and are cheaper to fix before real features are built on top.
2. **Local-only app** *(done 2026-08-19)*: Drift schema (`notes`/`folders`/`tags`/`notes_tags`), reactive UI via Drift `StreamProvider`s on both native (`NativeDatabase`) and web (`WasmDatabase`, `sqlite3.wasm` + `drift_worker.js` from the matching drift-2.34.3 GitHub release), seeded with the same content the UI-shell pass screenshot-verified. Note create + soft-delete wired to the UI; folder create/rename/delete wired to the UI too as of 2026-08-19 (see below). Two known simplifications to revisit: per-note `tagIds` isn't populated from the `notes_tags` join yet (always `[]`), and `collaboratorInitials` is hardcoded to `[]` pending the sharing tables (step 7) — both called out where they're set in `NotesRepository`.

   **Folder CRUD** *(done 2026-08-19)*: arbitrary-depth folder/subfolder creation and deletion, wired identically into the desktop sidebar and the mobile Folders screen via a shared `FolderTreeNode` widget (`lib/features/folders/widgets/`) — right-click (desktop) or long-press (mobile) opens New subfolder/Rename/Delete. `Personal` and `Shared` are permanent root folders (`FoldersRepository.protectedFolderIds`) with no delete option in either the UI or the repository (defensive `ArgumentError` if attempted). Deleting a folder cascades to every descendant subfolder; the confirmation dialog computes real affected-folder and note counts first (`FoldersRepository.previewDelete`) and offers a choice — move the notes to Personal (default) or delete them — executed atomically in a single `db.transaction()`.
3. **Rich text editor** *(done 2026-08-19)*: real `AppFlowyEditor` wired into both `EditorPane` (desktop) and `MobileNoteEditorScreen` (mobile) via a shared `NoteEditorBody` widget — title + body genuinely editable, debounced writes back to Drift's `notes.bodyJson`, which now stores appflowy_editor's own document JSON directly (the earlier UI-shell pass's custom `NoteBlock` union and static block widgets are retired). Pinned `appflowy_editor` to a GitHub commit past the 6.2.0 pub.dev release — 6.2.0 fails to compile against Flutter 3.47.0 (`TextInputClient.onFocusReceived` missing, [AppFlowy-IO/appflowy-editor#1204](https://github.com/AppFlowy-IO/appflowy-editor/issues/1204)); revert to a hosted version once a fixed release ships. Two things deliberately deferred to their own Build Order steps rather than done here: the code sample in the seed note is shown as inline `code`-styled text, not a real code block (still step 4 — no plugin exists for appflowy_editor 6.x, see §2); the seed note's image block was dropped rather than pointed at a URL that doesn't resolve (real attachments are step 5). Known cosmetic gap: appflowy_editor's default block spacing is noticeably more generous than the mockup's tight spacing — not yet tightened via `BlockComponentConfiguration`.
4. **Code blocks & markdown**: markdown import/export *(done 2026-09-02)* — `lib/features/note_editor/markdown_io.dart` wraps appflowy_editor's own built-in `markdownToDocument`/`documentToMarkdown` (no custom parser needed); "Import Markdown…" sits next to "+ New note" in the notes list, "Export as Markdown…" is in the note's "…" menu, both via `file_selector`. Still open: the custom `CodeBlockComponentBuilder` on `highlight` (§2 — no plugin package exists) — code is still inline `code`-styled text, not a real block; round-trip fidelity for tables/code through markdown not yet verified.
5. **Attachments**: local-first photo capture/storage, upload queue stub (still single-user at this point).
6. **Wire up sync** *(done 2026-09-02)*: local Supabase + self-hosted PowerSync (§9) — real, verified push **and** pull, not just wired code: `powersync/` (Docker Compose — `journeyapps/powersync-service` + a dedicated `pg-storage` Postgres for PowerSync's own bucket storage, pointed at the *existing* local Supabase Postgres via `host.docker.internal:54322`) plus the stored procedures from §5 (`upsert_note`/`delete_note`/`upsert_folder`/`delete_folder`/`upsert_tag`/`attach_tag`/`detach_tag`, `supabase/migrations/20260902141614_initial_schema.sql`). `SupabaseSyncConnector` (`lib/data/sync/sync_connector.dart`) implements `uploadData()` — re-reads each row's full current state from the local view rather than trusting a PATCH's partial diff, then calls the matching procedure; the local database itself now runs *through* PowerSync (`drift_sqlite_async`'s `SqliteAsyncDriftConnection` wrapping a `PowerSyncDatabase`, replacing the bare `NativeDatabase` — see `lib/data/database/connection/connection_native.dart`), not a separate synced copy. Confirmed end-to-end against the running app + Docker stack: created notes/folders locally → uploaded to Postgres with correct `owner_id`; added a folder server-side via RPC → a fresh local database (simulating a new device/re-install) pulled it down automatically. One gotcha worth remembering: `powersync_role` needs `ALTER ROLE powersync_role BYPASSRLS` — the replication connection has no JWT context, so the `owner_id = auth.uid()` RLS policies would otherwise hide every row from it (sync rules in `powersync/config/sync-config.yaml` are what actually apply the per-user filter when serving clients). Known gap, not solved here: seed/demo content will try to sync to whichever real account first launches against an empty local db — fine for continued dev, needs a real fix before this ships. Scoped to single-user ownership only (§ owner_id = auth.uid()); real `folder_shares`/`note_shares` permissions are still step 7.
   - *Superseded 2026-11-09:* PowerSync and the `powersync/` Docker setup were removed in favour of the manual outbox upload / full download described at the top of §6. The initial migration was rewritten (prod had never received it): no replication role or publication, `(owner_id, id)` keys, one `push_changes` function instead of the seven per-row procedures. Verified with unit tests (`test/sync_service_test.dart`) and an end-to-end run against local Supabase (upload, download on a second device, paging past 1,000 rows, stale-edit skip, per-account isolation).
7. **Sharing backend**: `folder_shares`/`note_shares` tables, the `share_folder`/`share_note`/`revoke_*` stored procedures (§5), Supabase RLS policies scoped to shares (Download reads through them). Budget real time for this — it's typically the most underestimated piece.
8. **Multi-device & multi-user conflict testing**: two devices/users editing the same note and same table concurrently; airplane-mode reconnect scenarios.
9. **Auth** *(done 2026-09-02)*: email/password sign in/sign up (`lib/features/auth/auth_screen.dart`), session-gated routing (`app_router.dart`'s `redirect`, driven by `Supabase.instance.client.auth.onAuthStateChange`), Sign Out + live account email in Settings. Device linking and sharing invite flows are still step 7/8 territory (need real sharing to mean anything).
10. **Search** *(done, revisit later)*: not FTS5 — `searchNotes` (`lib/data/models/note_search.dart`) matches every word of the query, in any order, case-insensitively, against title + full body text + tag names (`#word` = tags only), in memory over the already-streamed note list; notes with every word in the title come first. The notes list highlights matches and shows a snippet around the first match in the body (2026-11-09). Fine at current/expected local-personal-note-app scale; swap for real Drift FTS5 if/when note counts make that matter.
11. **Platform polish**: native menu bars (Mac/Windows/Linux), share-sheet integration (iOS/Android), window management (desktop).
12. **Encryption** (optional, decide early if needed — retrofitting E2E later is painful).

---

## 11. Explicitly Deferred / Out of Scope for V1

- Real-time collaborative editing (live cursors, simultaneous typing) — V2 candidate via CRDT + live transport.
- End-to-end encryption — only if required; adds design implications best decided early rather than retrofitted.
