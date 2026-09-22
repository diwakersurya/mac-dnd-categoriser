# Manual smoke checklist

Run `make run`. The app has no Dock icon; look for the tray icon in the menubar.

Setup: `mkdir -p ~/Desktop/dnd-test/{Invoices,Screenshots,inbox}` and put three files in `inbox`:
`invoice_march.pdf`, `Screenshot 2026-09-21.png`, `notes.txt`. Add `Invoices` and `Screenshots` via Settings with
descriptions "Supplier invoices, receipts, bills" and "Screenshots and screen recordings".

- [ ] Drag the three files from Finder. Shelf appears at the right edge, centred on the pointer, with 2 tiles.
- [ ] Tiles show a spinner, then a count badge and accent border on every matching tile. Jev: well under a second. On-device: 1–3 s.
- [ ] Invoices shows 1, Screenshots shows 1, a muted "No folder · 1" slot appears for `notes.txt`.
- [ ] Moving the pointer near a tile (within ~24 pt, not necessarily inside) fills it and a flyout to the left lists its files with icons. Moving onto the flyout keeps it open; dropping there drops on that tile.
- [ ] Release the mouse away from the shelf: it hides within ~250 ms.
- [ ] Drag again, drop anywhere on the panel: the PDF moves to Invoices and the PNG to Screenshots in one go. Each tile shows "Moving n of m" with a bar, then "Moved n" with a green check. `notes.txt` stays in `inbox`. Panel hides ~0.6 s after the last move.
- [ ] Drop a set where nothing matched any folder: all tiles flash red, nothing moves.
- [ ] Drop before results arrive (on-device engine makes this easy): tiles flash red, nothing moves.
- [ ] Drag a file whose name already exists in the target: it lands as `name (2).ext`.
- [ ] Hover "No folder": flyout lists unmatched files.
- [ ] Cross-volume move (e.g. to an external disk): progress bar advances per file; UI stays responsive.
- [ ] Settings: switch engine, quit, relaunch: choice persisted. Shelf badge shows "Jev" or "On-device".
- [ ] Settings with no key and engine = Jev: tiles show "Add a TypeSafe API key in Settings"; drop refused.
- [ ] Remove a folder in Settings: its tile is gone on the next drag.
- [ ] Rename or delete a configured folder on disk: its tile shows "Missing folder" and is not used for classification.
- [ ] Drag text from a browser (no file URLs): shelf does not appear.
- [ ] Full-screen app in front: shelf still appears over it.
- [ ] Settings → Advanced: edit the task statement; preview updates live; ↺ resets. Toggle "Size" off: `size_kb` disappears from the preview. Turn on "First 512 bytes": preview for a text file shows `snippet`.
- [ ] Advanced → "Last drag" becomes selectable after one drag and shows those file names.
- [ ] Advanced → enable request log, drag once, View log shows the request JSON and `f0 → folder` lines with latency.
- [ ] Settings → General → Shelf → Top: next drag shows a row of tiles along the top edge centred on the pointer; hovering a tile pops names below it. Bottom mirrors upward; Left mirrors Right.
- [ ] Drop on the transparent area beside/below the shelf: cursor shows no-drop, nothing moves.
