# DnD Categoriser

Menubar macOS app. Start dragging files anywhere; a shelf of folder tiles appears at the right screen edge.
Each tile is a real folder with a task description. The dragged files are classified against those descriptions
(TypeSafe Jev in the cloud, or Apple's on-device model), each tile shows which of the dragged files belong to it
as you approach, and dropping on a tile moves only those files.

Requirements: macOS 26, Xcode 26. For the cloud engine, a TypeSafe API key from console.typesafe.ai.
Only file names, extensions and sizes are ever sent.

    make test     # unit tests
    make app      # build/DnDCategoriser.app (ad-hoc signed)
    make run      # build and launch
    make install  # copy to /Applications so Spotlight and Launchpad find it

Opening Settings: menubar tray icon → Settings…. If the menubar is too crowded to show the icon,
Spotlight → "DnD Categoriser" → Return (or double-click the app) opens Settings while the app runs,
and Settings has a "Show in Dock" toggle so the Dock icon does the same.

Design: docs/superpowers/specs/2026-09-22-drag-shelf-categoriser-design.md
Manual checks: docs/smoke.md
