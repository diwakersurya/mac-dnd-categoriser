Requires macOS 26 on Apple silicon.

The zip is ad-hoc signed and not notarized (no paid Apple developer account behind this free app), so macOS blocks
the first launch. Two ways past it, pick one:

**Terminal, one line, nothing to click**

```bash
curl -fsSL https://github.com/diwakersurya/mac-dnd-categoriser/releases/latest/download/DnDCategoriser.zip -o /tmp/DnDCategoriser.zip && rm -rf /Applications/DnDCategoriser.app && ditto -x -k /tmp/DnDCategoriser.zip /Applications && open /Applications/DnDCategoriser.app
```

`curl` downloads carry no quarantine flag, so Gatekeeper never fires.

**Finder**

1. Unzip, drag `DnDCategoriser.app` to Applications, double-click. macOS says it could not verify the app. Click Done.
2. System Settings → Privacy & Security → scroll down → "DnDCategoriser was blocked" → **Open Anyway** → authenticate.
3. Open the app again and confirm.

Or clear the flag yourself: `xattr -dr com.apple.quarantine /Applications/DnDCategoriser.app`.

The app lives in the menubar; Settings opens on first launch. Source, configuration guide and architecture notes are
in the repository README.
