import AppKit
import SwiftUI

/// NSOpenPanel for the directory, then an NSAlert with a text field for the description.
@MainActor
enum AddFolderFlow {
    static func run(store: ConfigStore) {
        let open = NSOpenPanel()
        open.canChooseDirectories = true
        open.canChooseFiles = false
        open.allowsMultipleSelection = false
        open.canCreateDirectories = true
        open.prompt = "Choose"
        open.message = "Choose a folder to add to the shelf"
        NSApp.activate(ignoringOtherApps: true)
        guard open.runModal() == .OK, let url = open.url else { return }

        let alert = NSAlert()
        alert.messageText = "What belongs in “\(url.lastPathComponent)”?"
        alert.informativeText = "This description is sent to the classifier to decide which dragged files match this folder."
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 380, height: 48))
        field.placeholderString = "e.g. Supplier invoices, receipts and bills"
        field.lineBreakMode = .byWordWrapping
        field.usesSingleLineMode = false
        alert.accessoryView = field
        alert.addButton(withTitle: "Add")
        alert.addButton(withTitle: "Cancel")
        alert.window.initialFirstResponder = field
        guard alert.runModal() == .alertFirstButtonReturn else { return }

        store.addFolder(path: url, description: field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines))
    }
}

struct SettingsView: View {
    @ObservedObject var store: ConfigStore
    @State private var apiKey: String = KeychainStore.read() ?? ""
    @State private var testResult: String = ""

    var body: some View {
        Form {
            Section("Classifier") {
                Picker("Engine", selection: $store.config.engine) {
                    Text("TypeSafe Jev (cloud, ~100 ms)").tag(Engine.jev)
                    Text("Apple on-device (offline, 1–3 s)").tag(Engine.onDevice)
                }
                .pickerStyle(.radioGroup)

                if store.config.engine == .jev {
                    SecureField("TypeSafe API key", text: $apiKey)
                        .onChange(of: apiKey) { _, newValue in
                            KeychainStore.write(newValue.trimmingCharacters(in: .whitespacesAndNewlines))
                        }
                    HStack {
                        Button("Test key") { testKey() }
                        Text(testResult).font(.caption).foregroundStyle(.secondary)
                    }
                    Text("Get a key at console.typesafe.ai. Only file names, extensions and sizes are sent.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }

            Section("App") {
                Toggle("Show in Dock", isOn: $store.config.showInDock)
                Text("Clicking the Dock icon opens this window. Without it: Spotlight → “DnD Categoriser” → Return, or double-click the app.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section("Folders") {
                if store.config.folders.isEmpty {
                    Text("No folders yet. Add one below or with the “+” tile on the shelf.")
                        .foregroundStyle(.secondary)
                }
                ForEach($store.config.folders) { $folder in
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            TextField("Name", text: $folder.name).font(.headline)
                            Spacer()
                            Text(folder.path.path)
                                .font(.caption).foregroundStyle(.secondary)
                                .lineLimit(1).truncationMode(.middle)
                                .frame(maxWidth: 200, alignment: .trailing)
                            Button { NSWorkspace.shared.open(folder.path) } label: {
                                Image(systemName: "folder")
                            }
                            .buttonStyle(.borderless)
                            .help("Open in Finder")
                            Button(role: .destructive) { store.removeFolder(id: folder.id) } label: {
                                Image(systemName: "trash")
                            }
                            .buttonStyle(.borderless)
                            .help("Remove from shelf (folder on disk is untouched)")
                        }
                        TextField("What belongs here? (sent to the classifier)", text: $folder.description, axis: .vertical)
                            .lineLimit(1...3)
                    }
                    .padding(.vertical, 4)
                }
                Button("Add folder…") { AddFolderFlow.run(store: store) }
            }
        }
        .formStyle(.grouped)
        .frame(width: 560, height: 600)
    }

    private func testKey() {
        testResult = "Testing…"
        let classifier = JevClassifier(apiKey: { apiKey })
        let file = FileInfo(id: "f0", url: URL(fileURLWithPath: "/tmp/invoice_march.pdf"), name: "invoice_march", ext: "pdf", sizeBytes: 200_000)
        let folder = Folder(id: "invoices", path: URL(fileURLWithPath: "/tmp"), name: "Invoices", description: "Supplier invoices and receipts")
        Task { @MainActor in
            do {
                let result = try await classifier.classify(files: [file], folders: [folder])
                testResult = result["f0"] == "invoices" ? "Key works." : "Key works (answer: \(result["f0"] ?? "none"))."
            } catch let error as ClassifierError {
                testResult = error.message
            } catch {
                testResult = error.localizedDescription
            }
        }
    }
}

@MainActor
final class SettingsWindowController {
    private let store: ConfigStore
    private var window: NSWindow?

    init(config: ConfigStore) {
        store = config
    }

    func show() {
        if window == nil {
            let w = NSWindow(contentViewController: NSHostingController(rootView: SettingsView(store: store)))
            w.title = "DnD Categoriser Settings"
            w.styleMask = [.titled, .closable, .miniaturizable]
            w.isReleasedWhenClosed = false
            w.center()
            window = w
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    func addFolderFlow() {
        AddFolderFlow.run(store: store)
    }
}
