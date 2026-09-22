import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let config = ConfigStore()
    private var shelf: ShelfController!
    private var statusItem: NSStatusItem!
    private var settings: SettingsWindowController!

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        settings = SettingsWindowController(config: config)
        shelf = ShelfController(config: config)
        shelf.presentAddFolder = { [weak self] in self?.settings.addFolderFlow() }

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = NSImage(systemSymbolName: "tray.and.arrow.down.fill", accessibilityDescription: "DnD Categoriser")
        let menu = NSMenu()
        let settingsItem = NSMenuItem(title: "Settings…", action: #selector(openSettings), keyEquivalent: ",")
        settingsItem.target = self
        menu.addItem(settingsItem)
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit DnD Categoriser", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        statusItem.menu = menu

        Notifier.requestPermission()
        if config.config.folders.isEmpty { openSettings() }
    }

    @objc func openSettings() {
        settings.show()
    }
}

MainActor.assumeIsolated {
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    app.run()
}
