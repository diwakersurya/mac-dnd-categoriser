# DnD Categoriser

A menubar app for macOS. Start dragging files anywhere; a shelf of folder tiles slides in from a screen edge.
Each tile is a real folder you have described in words ("supplier invoices, receipts, bills"). While you are still
dragging, the app decides which of the dragged files belong to which folder, shows a count on every matching
tile, and lists the file names when you hover a tile. Drop anywhere on the shelf and each file moves to its folder.

```
                         ┌ Invoices ─────────────── ② ┐   ◀ accent border + count
   ┌ Invoices · 2 files ┐│   Supplier invoices, bills   │
   │ ▸ invoice_march.pdf││├ Screenshots ──────────── ① ┤
   │ ▸ receipt_0921.pdf │││   Screenshots, recordings    │
   └────────────────────┘│├ Recipes ────────────────── ┤   ◀ dimmed, nothing matched
        file names       ││   Things to cook             │
      for hovered tile   │└ No folder ────────────── ① ┘   ◀ stays where it is
                         └──────────────────────────────┘
```

Two classification engines, chosen in Settings:

- **Apple on-device** (default recommendation): Apple's Foundation Models framework, fully offline, about one to three seconds. Requires Apple Intelligence to be enabled on the Mac.
- **TypeSafe Jev**: a cloud decision model, about a hundred milliseconds. Requires your own API key from [console.typesafe.ai](https://console.typesafe.ai), or point the app at any other server that speaks the same System One API, including one running on your own machine. Only file names, extensions and sizes leave your machine unless you opt into more under Advanced.

There is no account, no telemetry, no analytics, and no third-party code. See [ARCHITECTURE.md](ARCHITECTURE.md) for how it works and exactly what is stored and sent.

## Requirements

- macOS 26 or later, Apple silicon.
- Xcode 26 (for the Swift 6.2 toolchain). No other dependencies.
- For the on-device engine: Apple Intelligence turned on in System Settings.
- For the Jev engine: a TypeSafe API key.

## Install

```bash
git clone <this repo>
cd mac-dnd-categoriser
make cert      # optional, once: creates a self-signed signing identity (see "Code signing" below)
make install   # builds and copies DnDCategoriser.app to /Applications, then open it
open /Applications/DnDCategoriser.app
```

The app has no Dock icon. Look for a tray icon in the menubar. On first launch, Settings opens automatically because
no folders are configured yet.

macOS will ask for permission the first time the app touches your Desktop, Documents or Downloads folders. These
grants are remembered under System Settings → Privacy & Security → Files and Folders.

### Code signing

`make install` signs the app with the identity named "DnDCategoriser Dev" if it exists in your login keychain, and
falls back to an ad-hoc signature otherwise. Ad-hoc signatures change on every build, and macOS treats each build as a
new app: it re-asks for folder access and for permission to read the API key from the Keychain. `make cert` creates
a self-signed code-signing certificate once so those grants persist. The certificate and its private key stay in
your keychain and are only trusted for code signing on your own machine. If you have an Apple Development
certificate you would rather use, pass it: `make install SIGN_IDENTITY="Apple Development: Your Name (TEAMID)"`.

## Configure

Open Settings from the menubar icon, or if the menubar is too crowded to show the icon: Spotlight → "DnD Categoriser"
→ Return, double-click the app, or turn on "Show in Dock" and click the Dock icon.

### Folders tab

- **Add folder…** opens a folder picker. You can create a new folder from within the picker. After choosing, you are
  asked for a description.
- **Description** is what the classifier reads, so be concrete. "Supplier invoices, receipts and bills" works far
  better than "Finance". Mention file kinds if they matter: "Screenshots and screen recordings".
- **Name** is the tile label. It defaults to the folder name and is also sent to the classifier.
- The folder icon opens the folder in Finder. The trash icon removes the tile; the folder on disk is untouched.
- A tile whose folder has been deleted or renamed shows "Missing folder" and is excluded from classification.

### General tab

- **Engine**: Apple on-device or TypeSafe Jev.
- **Jev URL**: shown only when Jev is selected. Defaults to `https://api.typesafe.ai/v1/systemone`. Point it at any
  server that speaks the TypeSafe System One API, hosted or local, e.g. `http://localhost:8080/v1/systemone`.
  Plain `http` is allowed only for localhost and local-network addresses; remote servers must use `https`.
- **API key**: stored in your login Keychain, never in a file. Required for api.typesafe.ai, optional for other
  servers (sent as `Authorization: Bearer` when set). "Test connection" sends one sample request and reports the result.
- **Shelf appears at**: Top, Right, Bottom or Left. Vertical edges stack tiles in a column; horizontal edges lay them
  in a row. File names pop out toward the screen centre.
- **Show in Dock**: adds a Dock icon that opens Settings when clicked.

### Advanced tab

Everything the classifier receives is built from a template you can edit here, and the exact request is shown live.

- **Payload template**: the task statement, the per-file question, the text describing the "no folder" option,
  the Jev model name and the request timeout. Each text has a reset button.
- **Sent per file**: the file name is always sent. Extension and size are on by default. Kind, created date,
  modified date, parent folder name and the first 512 bytes of text content are off; the last two carry a warning
  because they reveal more about your disk or your files.
- **Preview**: the exact JSON that would go to TypeSafe, or the exact prompt that would go to the on-device model,
  produced by the same code that sends it. Switch between three sample files and the files from your last drag.
  The token estimate is rough (about four characters per token).
- **Request log**: off by default. When on, the last ten requests and responses are kept in memory and shown in
  "View log…". Nothing is written to disk; the log is gone when the app quits.

## Use

1. Select files in Finder (or any app that drags file URLs) and start dragging.
2. The shelf slides in from the configured edge. Tiles show a spinner, then a count and an accent border on every
   tile that received files. Files matching nothing appear under a muted "No folder" tile.
3. Move the pointer near a tile to see its file names. You do not have to be exactly inside the tile.
4. Drop anywhere on the shelf. Each tile shows a progress bar as its files move, then "Moved n". The shelf fades
   out three seconds later. Files under "No folder" are left where they are.
5. Release the mouse anywhere else and the shelf simply hides.

A name collision in the destination is resolved as `name (2).ext`, never by overwriting. If some files fail to move
(permissions, source vanished), the rest still move and a notification lists the failures.

## Troubleshooting

| Symptom | Cause and fix |
|---|---|
| Shelf never appears | The drag carries no file URLs (text or images from a browser). Only file drags trigger it. |
| Tiles say "Add a TypeSafe API key in Settings" | Engine is Jev and no key is stored. Add one, or switch to on-device. |
| Tiles say "On-device model unavailable" | Apple Intelligence is off, still downloading, or unsupported on this Mac. |
| Tiles say "Classification unavailable: HTTP 429/529" | TypeSafe rate limit or overload. The app retries once; try again. |
| Drop flashes red, nothing moves | Classification had not finished, failed, or nothing matched any folder. |
| Keychain asks for a password on every launch | The app is ad-hoc signed. Run `make cert` then `make install`. |
| Folder access prompt on every launch | Same cause, same fix. |
| Cannot find the menubar icon | Menubar is full. Use Spotlight, the Dock toggle, or `open -a DnDCategoriser`. |

## Development

```bash
make test                                  # unit tests, no network, no model
RUN_ONDEVICE=1 swift test --filter OnDevice  # one test against the real Apple model
make app                                   # build/DnDCategoriser.app
make run                                   # build and launch from build/
```

Layout, request encoding, file moving and configuration are pure functions or small classes with XCTest coverage.
The manual checklist for anything involving a real mouse is in `docs/smoke.md`.

## License

MIT. See [LICENSE](LICENSE).

## Privacy in one paragraph

Folder paths and descriptions live in `~/Library/Application Support/DnDCategoriser/config.json`. The TypeSafe API key
lives in your login Keychain. Nothing else is written to disk. With the on-device engine nothing leaves the Mac.
With the Jev engine, file names, extensions and sizes (plus whatever you enable under Advanced) are sent to the Jev URL
you configured (`api.typesafe.ai` by default) when a drag starts; that server's handling of the data is governed by its
operator's terms. The app reads the
system drag pasteboard to learn which files you are dragging; it never reads keyboard input and needs no Accessibility
permission. Details in [ARCHITECTURE.md](ARCHITECTURE.md).
