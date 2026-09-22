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
    @ObservedObject var session: SessionLog

    var body: some View {
        TabView {
            GeneralTab(store: store)
                .tabItem { Label("General", systemImage: "gearshape") }
            FoldersTab(store: store)
                .tabItem { Label("Folders", systemImage: "folder") }
            AdvancedTab(store: store, session: session)
                .tabItem { Label("Advanced", systemImage: "curlybraces") }
        }
        .frame(width: 700, height: 680)
    }
}

// MARK: - General

struct GeneralTab: View {
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
                    Text("Get a key at console.typesafe.ai. What is sent per file is listed under Advanced.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }

            Section("Shelf") {
                Picker("Appears at", selection: $store.config.edge) {
                    ForEach(ShelfEdge.allCases) { edge in Text(edge.label).tag(edge) }
                }
                .pickerStyle(.segmented)
                Text(store.config.edge == .top || store.config.edge == .bottom
                     ? "Tiles form a row along that edge; file names pop out toward the screen centre."
                     : "Tiles stack along that edge; file names pop out toward the screen centre.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section("App") {
                Toggle("Show in Dock", isOn: $store.config.showInDock)
                Text("Clicking the Dock icon opens this window. Without it: Spotlight → “DnD Categoriser” → Return, or double-click the app.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    private func testKey() {
        testResult = "Testing…"
        let classifier = JevClassifier(apiKey: { apiKey }, template: store.config.payload)
        let file = PayloadPreview.sampleFiles[0]
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

// MARK: - Folders

struct FoldersTab: View {
    @ObservedObject var store: ConfigStore

    var body: some View {
        Form {
            Section {
                if store.config.folders.isEmpty {
                    Text("No folders yet. Add one below.").foregroundStyle(.secondary)
                }
                ForEach($store.config.folders) { $folder in
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            TextField("Name", text: $folder.name, prompt: Text("Name"))
                                .labelsHidden()
                                .font(.headline)
                            Spacer()
                            Text(folder.path.path)
                                .font(.caption).foregroundStyle(.secondary)
                                .lineLimit(1).truncationMode(.middle)
                                .frame(maxWidth: 220, alignment: .trailing)
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
                        TextField("Description", text: $folder.description, prompt: Text("What belongs here? (sent to the classifier)"), axis: .vertical)
                            .labelsHidden()
                            .lineLimit(1...3)
                    }
                    .padding(.vertical, 4)
                }
                Button("Add folder…") { AddFolderFlow.run(store: store) }
            } footer: {
                Text("Folder names and descriptions are the classifier's criteria. Be concrete: “Supplier invoices, receipts, bills” beats “Finance”.")
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Advanced

struct AdvancedTab: View {
    @ObservedObject var store: ConfigStore
    @ObservedObject var session: SessionLog
    @State private var previewSource: PreviewSource = .sample
    @State private var showLog = false

    enum PreviewSource: String, CaseIterable { case lastDrag = "Last drag", sample = "Sample files" }

    private var previewFiles: [FileInfo] {
        previewSource == .lastDrag && !session.lastFiles.isEmpty ? session.lastFiles : PayloadPreview.sampleFiles
    }

    private var previewText: String {
        PayloadPreview.render(engine: store.config.engine, files: previewFiles, folders: store.config.folders, template: store.config.payload)
    }

    var body: some View {
        Form {
            Section("Payload template") {
                templateField("Task statement", text: $store.config.payload.task, defaultValue: PayloadTemplate.defaultTask)
                templateField("Per-file question", text: $store.config.payload.question, defaultValue: PayloadTemplate.defaultQuestion)
                templateField("“No folder” option", text: $store.config.payload.noneDescription, defaultValue: PayloadTemplate.defaultNoneDescription)
                HStack {
                    TextField("Jev model", text: $store.config.payload.model)
                    TextField("Timeout (s)", value: $store.config.payload.timeoutSeconds, format: .number)
                        .frame(width: 140)
                }
            }

            Section {
                ForEach(FileField.allCases) { field in
                    Toggle(isOn: fieldBinding(field)) {
                        HStack(spacing: 6) {
                            Text(field.label)
                            if let w = field.warning {
                                Label(w, systemImage: "exclamationmark.triangle.fill")
                                    .font(.caption).foregroundStyle(.orange).labelStyle(.titleAndIcon)
                            }
                        }
                    }
                    .disabled(field == .name)
                }
            } header: {
                Text("Sent per file")
            } footer: {
                Text("File name is always sent. Everything else is off unless you turn it on. Content is never read unless the last option is on.")
            }

            Section {
                HStack {
                    Picker("Preview with", selection: $previewSource) {
                        ForEach(PreviewSource.allCases, id: \.self) { source in
                            Text(source.rawValue).tag(source)
                                .disabled(source == .lastDrag && session.lastFiles.isEmpty)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    Spacer()
                    Text("≈ \(PayloadPreview.estimatedTokens(previewText)) tokens")
                        .font(.caption).foregroundStyle(.secondary).monospacedDigit()
                    Button("Copy") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(previewText, forType: .string)
                    }
                }
                ScrollView {
                    Text(previewText)
                        .font(.system(.caption, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(8)
                }
                .frame(height: 220)
                .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 6))
            } header: {
                Text(store.config.engine == .jev ? "Exact request to api.typesafe.ai" : "Exact prompt to the on-device model")
            } footer: {
                Text(session.lastFiles.isEmpty ? "Drag some files once and “Last drag” becomes available." : "“Last drag” uses the \(session.lastFiles.count) file(s) from the most recent shelf session.")
            }

            Section("Request log") {
                Toggle("Keep the last 10 requests and responses (memory only, cleared on quit)", isOn: $store.config.logRequests)
                HStack {
                    Button("View log… (\(session.entries.count))") { showLog = true }
                        .disabled(session.entries.isEmpty)
                    Button("Clear") { session.entries.removeAll() }
                        .disabled(session.entries.isEmpty)
                }
            }
        }
        .formStyle(.grouped)
        .sheet(isPresented: $showLog) { RequestLogView(session: session) }
    }

    @ViewBuilder
    private func templateField(_ title: String, text: Binding<String>, defaultValue: String) -> some View {
        HStack(alignment: .top) {
            TextField(title, text: text, axis: .vertical).lineLimit(1...3)
            Button { text.wrappedValue = defaultValue } label: { Image(systemName: "arrow.counterclockwise") }
                .buttonStyle(.borderless)
                .disabled(text.wrappedValue == defaultValue)
                .help("Reset to default")
        }
    }

    private func fieldBinding(_ field: FileField) -> Binding<Bool> {
        Binding(
            get: { store.config.payload.fields.contains(field) },
            set: { on in
                if on { store.config.payload.fields.insert(field) } else if field != .name { store.config.payload.fields.remove(field) }
            }
        )
    }
}

struct RequestLogView: View {
    @ObservedObject var session: SessionLog
    @Environment(\.dismiss) private var dismiss
    @State private var selected: RequestLogEntry.ID?

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Request log").font(.headline)
                Spacer()
                Button("Done") { dismiss() }.keyboardShortcut(.defaultAction)
            }
            .padding()
            HSplitView {
                List(session.entries, selection: $selected) { entry in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(entry.date, format: .dateTime.hour().minute().second())
                        Text("\(entry.engine == .jev ? "Jev" : "On-device") · \(Int(entry.latency * 1000)) ms")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    .tag(entry.id)
                }
                .frame(minWidth: 160, maxWidth: 200)
                ScrollView {
                    if let entry = session.entries.first(where: { $0.id == selected }) ?? session.entries.first {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("REQUEST").font(.caption.bold()).foregroundStyle(.secondary)
                            Text(entry.request).font(.system(.caption, design: .monospaced)).textSelection(.enabled)
                            Text("RESPONSE").font(.caption.bold()).foregroundStyle(.secondary)
                            Text(entry.response).font(.system(.caption, design: .monospaced)).textSelection(.enabled)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding()
                    } else {
                        Text("No entries").foregroundStyle(.secondary).padding()
                    }
                }
            }
        }
        .frame(width: 760, height: 520)
    }
}

// MARK: - Window

@MainActor
final class SettingsWindowController {
    private let store: ConfigStore
    private let session: SessionLog
    private var window: NSWindow?

    init(config: ConfigStore, session: SessionLog) {
        store = config
        self.session = session
    }

    func show() {
        if window == nil {
            let w = NSWindow(contentViewController: NSHostingController(rootView: SettingsView(store: store, session: session)))
            w.title = "DnD Categoriser Settings"
            w.styleMask = [.titled, .closable, .miniaturizable]
            w.isReleasedWhenClosed = false
            w.center()
            window = w
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}
