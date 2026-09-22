# Manual smoke checklist

Run `make run`. The app has no Dock icon; look for the tray icon in the menubar.

Setup: `mkdir -p ~/Desktop/dnd-test/{Invoices,Screenshots,inbox}` and put three files in `inbox`:
`invoice_march.pdf`, `Screenshot 2026-09-21.png`, `notes.txt`. Add `Invoices` and `Screenshots` via Settings with
descriptions "Supplier invoices, receipts, bills" and "Screenshots and screen recordings".

- [ ] Drag the three files from Finder. Shelf appears at the right edge, centred on the pointer, with 2 tiles + "Add folder".
- [ ] Tiles show a spinner, then names. Jev: well under a second. On-device: 1–3 s.
- [ ] `invoice_march.pdf` is listed under Invoices, the PNG under Screenshots, `notes.txt` under neither.
- [ ] Moving the pointer near a tile (within ~24 pt, not necessarily inside) highlights it and expands its list.
- [ ] Release the mouse away from the shelf: it hides within ~250 ms.
- [ ] Drag again, drop on Invoices: only the PDF moves. The PNG and TXT remain in `inbox`.
- [ ] Drop on a dimmed tile (no matches): nothing moves, the shelf hides.
- [ ] Drop before results arrive (on-device engine makes this easy): tile flashes red, nothing moves.
- [ ] Drag a file whose name already exists in the target: it lands as `name (2).ext`.
- [ ] Click "+" on the shelf during a drag: folder picker, then description prompt; new tile appears on the next drag.
- [ ] Settings: switch engine, quit, relaunch: choice persisted. Shelf badge shows "Jev" or "On-device".
- [ ] Settings with no key and engine = Jev: tiles show "Add a TypeSafe API key in Settings"; drop refused.
- [ ] Remove a folder in Settings: its tile is gone on the next drag.
- [ ] Rename or delete a configured folder on disk: its tile shows "Missing folder" and is not used for classification.
- [ ] Drag text from a browser (no file URLs): shelf does not appear.
- [ ] Full-screen app in front: shelf still appears over it.
