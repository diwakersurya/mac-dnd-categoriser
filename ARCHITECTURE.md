# Architecture

This document explains how DnD Categoriser works, where every piece of data lives, what leaves the machine, and how
the security-relevant parts are handled. It is written for someone deciding whether to run the app or contribute.

## Overview

```
 Finder drag ──▶ DragWatcher ──dragStarted(urls)──▶ ShelfController ──▶ ShelfPanel (NSPanel, one per app)
 (any app)       global mouse monitor +                 │                    │
                 drag pasteboard                        │                    ▼ pointer position
                                                        ▼               ShelfView (SwiftUI)
                                                Classifier.classify     tiles + flyout, laid out by TileLayout
                                                (Jev | OnDevice)             │
                                                        │                    ▼ drop
                                                [fileID: folderID]      FileMover.move (background task)
```

One Swift executable target, no third-party packages. AppKit owns the global drag monitor, the panel and drop
handling; SwiftUI renders tile content and the Settings window. Pure logic (layout math, request encoding, file
moving, configuration) lives in small files with unit tests.

| File | Responsibility |
|---|---|
| `DragWatcher` | Detects system-wide file drags; reports start and end. |
| `ShelfController` | Glue: shows the panel, runs classification, handles hover and drop, runs moves, logs. |
| `ShelfPanel` / `DropHostView` | Non-activating floating panel; the drag destination; animated show/hide. |
| `TileLayout` | Pure geometry for the four screen edges: tile frames, hit-testing with a vicinity margin, flyout placement. |
| `ShelfViewModel` / `ShelfView` | Tile states (pending, matches, empty, failed, moving, done), flyout content, rendering. |
| `Classifier` protocol, `JevClassifier`, `OnDeviceClassifier` | Turn files + folders + template into folder assignments. |
| `PayloadTemplate`, `FileField`, `FileMetadata`, `PayloadPreview` | What goes into a request, and a byte-exact preview of it. |
| `FileMover` | Moves files with collision renaming; per-file results. |
| `ConfigStore`, `KeychainStore` | Persistence. |
| `Settings` | Settings window (General, Folders, Advanced) and the add-folder flow. |
| `SessionLog` | Per-launch memory: last dragged files, optional request log. |
| `Notifier` | User notifications for failed moves. |
| `main.swift` | App bootstrap, menubar item, Edit menu, reopen handling, Dock toggle. |

## How a drag becomes a move

1. **Detection.** `DragWatcher` installs a global monitor for `leftMouseDragged` events. Mouse monitors do not need
   the Accessibility permission (keyboard monitors would; there are none). On each event it compares the
   `changeCount` of the system drag pasteboard (`NSPasteboard(name: .drag)`) with the last value. A new count with
   at least one file URL means a new drag session; the URLs are read once. Directories are dropped from the list
   (packages such as `.app` are kept, matching Finder), so folders are never classified or moved. Drags without
   file URLs (text, images from a browser) are ignored. End of drag is detected by polling `NSEvent.pressedMouseButtons` every 100 ms.
2. **Shelf.** `ShelfController` builds `FileInfo` values (name, extension, size) for the dragged URLs, resets the
   tiles from the configured folders, and shows the panel flush with the configured screen edge, centred on the
   pointer, with a 0.35 s fade-and-slide. The panel is an `NSPanel` with `.nonactivatingPanel`, floating level,
   joins all Spaces, so it works over full-screen apps without stealing focus from the app you are dragging from.
3. **Classification** starts immediately, not on hover, so results are usually ready before the pointer reaches
   the shelf. Folders whose path no longer exists are excluded. The result is a dictionary from file id to folder id;
   files absent from it matched nothing.
4. **Hover.** `DropHostView` receives `draggingUpdated` with the pointer location. `TileLayout.tileIndex` picks the
   tile whose frame, outset by 24 pt, contains the point (nearest centre wins on overlap). That tile is highlighted
   and a flyout lists its files. While the pointer is over the flyout the tile stays active so the list can be read.
5. **Drop.** Accepted only over the shelf itself (plus margin) or a visible flyout; elsewhere on the transparent
   panel the drag operation is "none" so the pointer shows no-drop and files are not swallowed. A drop while
   classification is pending or failed, or when nothing matched, flashes the tiles and refuses. Otherwise every
   classified file moves to its folder. Moves run on a detached task, one folder at a time, one file at a time,
   paced so each tile visibly fills (same-volume moves are instant renames). Tiles show "Moving n of m" then
   "Moved n" or a failure count. Results hold two seconds, then the panel fades out over one second. A new drag
   during a move is ignored.

`FileMover` uses `FileManager.moveItem`. If the destination name exists it appends ` (2)`, ` (3)`, … before the
extension. It never overwrites. Cross-volume moves are copy-then-delete inside `moveItem`.

## Classification

Both engines are built from the same `PayloadTemplate` (Settings → Advanced), and the Advanced preview renders
through the same builders, so the preview is what is sent.

### TypeSafe Jev

`POST` to the Jev URL from General (default `https://api.typesafe.ai/v1/systemone`; any server speaking the same API
works, including localhost) with `Authorization: Bearer <key>` when a key is set. Jev is a "System One" decision model:
you give it a `state` and a map of typed `questions`; it answers every question in one call with calibrated
probabilities and cannot return a value outside your schema. The app sends one **Choice** question per dragged
file, all sharing the same criteria: one key per folder (name + description) plus `none`. Per-file facts are
embedded in each question's structured `instructions` object and repeated in `state.files`.

```json
{
  "model": "jev-latest",
  "state": { "task": "…", "files": [ { "id": "f0", "name": "invoice_march", "ext": "pdf", "size_kb": 231 } ] },
  "questions": {
    "f0": {
      "type": "choice",
      "instructions": { "file": { "id": "f0", "name": "invoice_march", "ext": "pdf", "size_kb": 231 },
                        "question": "Which folder is the best home for this file?" },
      "criteria": { "invoices": { "name": "Invoices", "what": "Supplier invoices, bills" },
                    "none": "Does not belong in any of the listed folders" }
    }
  }
}
```

Timeout defaults to 3 s. A 429 or 529 is retried once after 400 ms. 401 becomes "API key missing or rejected"; 422 surfaces
the server's validation message. Answers naming an unknown folder, or `none`, mean "no folder".

### Apple on-device

`FoundationModels.LanguageModelSession` with guided generation: the output type is a `@Generable` list of
`(fileID, folderID)` pairs, so the model cannot produce free text. Sampling is greedy so results are deterministic.
Answers with unknown ids are dropped. The framework runs Apple's on-device model; no network is involved.
Availability is checked first and the reason is shown on the tiles if the model is unavailable.

### Template and per-file fields

`FileField` controls what is included per file. `name` is always sent. `ext` and `size` are on by default.
`kind` (UTType description), `created`, `modified`, `parent` (parent folder name) and `snippet` (first 512 bytes,
only if they decode as mostly printable UTF-8) are off by default. `FileMetadata` reads these only when the
corresponding field is enabled; the file is otherwise never opened.

## Data inventory

Everything the app persists, keeps in memory, or transmits.

| Data | Where | Lifetime | Who can read it |
|---|---|---|---|
| Folder paths, names, descriptions; engine; shelf edge; Dock toggle; payload template (incl. Jev URL); log toggle | `~/Library/Application Support/DnDCategoriser/config.json`, pretty-printed JSON, written atomically | Until you remove it | Your user account |
| TypeSafe API key | Login Keychain, generic password, service `com.dndcategoriser.typesafe-api-key`, account `api-key` | Until you clear the field (empty string deletes the item) | This app, after you click "Always Allow" once; other apps prompt you |
| Dragged file URLs and metadata | Memory only, per drag session | Until the next drag or quit | Nobody else |
| Request log (opt-in) | Memory only, last 10 entries | Until quit or "Clear" | Nobody else |
| Names of files that failed to move | macOS user notification | Notification Center retention | You |
| Diagnostic lines (config save failure, keychain write failure, and failed move names when run unbundled) | Unified log via `NSLog` | System log retention | Local admin |

Nothing else is written: no caches, no history, no crash reports, no analytics, no identifiers. The app does not
know who you are.

## Network

| Destination | When | What |
|---|---|---|
| The Jev URL from General (default `https://api.typesafe.ai/v1/systemone`) | Engine is Jev and a drag with file URLs starts; or you click "Test connection" | The request shown in Advanced → Preview: template texts, folder names and descriptions, and the enabled per-file fields. The API key in the Authorization header, if one is set. |

That is the only network destination in the codebase, and you choose it. There is no update check, no telemetry, no
crash reporter. With the on-device engine the app makes no network requests at all. TLS is provided by `URLSession`
with system trust; no certificate pinning. App Transport Security permits plain `http` only for local networking
(`NSAllowsLocalNetworking`), so a remote server must be `https`. With the default URL and no key, nothing is sent and
the shelf reports "Add a TypeSafe API key". With a custom URL the key is optional and the header is omitted when empty.
How the server's operator stores or uses submitted data is governed by their terms, not by this app.

## Security model

**Not sandboxed.** The app runs with your user's normal file permissions because it must move files into arbitrary
folders. macOS still gates Desktop, Documents, Downloads, removable volumes and network volumes behind a one-time
consent prompt (TCC), recorded per app identity. Moves never overwrite; collisions get a numbered suffix.

**No elevated privileges, no helper tools, no launch agents.** Quit the app and nothing of it is running.

**Input the app takes from the system.** It reads the drag pasteboard, which any app can do. It observes
`leftMouseDragged` events system-wide to know when a drag is happening; the event contents are discarded, only the
timing is used. It does not observe keyboard events and does not request Accessibility. It never reads file content
unless you enable the 512-byte snippet field in Advanced, where it is labelled as sending content.

**Secrets.** The API key is entered in a `SecureField`, trimmed, and written straight to the Keychain. It is never
logged, never included in the preview or the request log, and never written to `config.json`. `git grep` for
`sk-` in this repository finds nothing; there are no sample keys.

**Code signing.** Builds are signed with a self-signed identity created by `scripts/make-cert.sh`, or ad-hoc if
that identity is absent. A stable identity matters because Keychain access control and TCC grants are tied to the
signing identity: with ad-hoc signing every rebuild is a "new app" and macOS re-prompts. The self-signed
certificate is trusted for code signing only, only on the machine where you created it, and its private key never
leaves your keychain. It provides no assurance to anyone else; for distribution you would sign with Developer ID
and notarize.

**Dependencies.** None. Only Apple frameworks (AppKit, SwiftUI, Foundation, FoundationModels, UserNotifications,
Security, UniformTypeIdentifiers). No package manager resolution step, nothing fetched at build time.

**Classifier trust.** Folder descriptions are user-authored and are sent to the model as criteria. Jev returns only
keys from your schema; the on-device model returns only guided-generation structs, and any id outside the known set
is discarded. A crafted description therefore cannot make the app move files to a folder that is not on the shelf.
It could make the classifier choose wrongly, which the user sees before dropping.

**Concurrency.** AppKit and SwiftUI state live on the main actor. File moves run on a detached task and report back
through `MainActor.run`. Classification tasks are cancelled when a new drag starts.

## Things a public deployment should still consider

These are not bugs; they are properties worth knowing before relying on the app.

1. Anyone with your user account can read `config.json` (folder names and descriptions) and, if they run code as you,
   can attempt to read the Keychain item (macOS will prompt unless they are the signed app).
2. When the Jev engine is on, file names are sent to a third party on every drag, including drags that never reach the
   shelf. If that matters, use the on-device engine or keep Jev for specific sessions only.
3. Enabling the request log keeps file names in memory for the session. It is off by default for that reason.
4. Unified log entries from `NSLog` on failure paths can include file names. They stay on the machine.
5. There is no update mechanism, so users must rebuild to get fixes.

## Testing

`swift test` runs 53 unit tests without network or model access: layout geometry for all four edges, request
encoding and error mapping against a stubbed `URLSession`, template and metadata handling, file moving and
collision renaming, configuration round-trips and backward compatibility, drag-pasteboard parsing, and view-model
state transitions. One opt-in test (`RUN_ONDEVICE=1`) classifies three obvious files with the real Apple model.
Everything that needs a real mouse is on the manual checklist in `docs/smoke.md`.
