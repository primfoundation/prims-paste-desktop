import AppKit
import PrimsPasteCore
import SwiftUI

struct PrimLibrarySheet: View {
    @ObservedObject var board: Board
    @State private var kits: [PrimKit] = []
    @State private var error = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Create a Prim").font(.title2.bold())
            Text("Choose a definition. Your record stays encrypted on this Mac. The original sticky is preserved.")
                .foregroundStyle(.secondary)
            ForEach(kits) { kit in
                Button { board.startPrim(kit) } label: {
                    HStack {
                        VStack(alignment: .leading) {
                            Text(kit.name).font(.headline)
                            Text(kit.pin.version).font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Image(systemName: "chevron.right")
                    }.padding(10)
                }.buttonStyle(.bordered)
            }
            Text("Development definitions. Validation checks structure and recorded references; it does not verify facts or permission to act.")
                .font(.caption).foregroundStyle(.secondary)
            if !error.isEmpty { Text(error).foregroundStyle(.red) }
            HStack { Spacer(); Button("Cancel") { board.showPrimLibrary = false }.keyboardShortcut(.cancelAction) }
        }.padding(24).frame(width: 520)
            .task {
                do { kits = try PrimLibrary.bundled().kits }
                catch { self.error = error.localizedDescription }
            }
    }
}

struct PrimEditor: View {
    @ObservedObject var board: Board
    let session: Board.PrimSession
    @State private var record: PrimJSON
    @State private var raw = ""
    @State private var advanced = false
    @State private var error = ""
    @State private var validationMessage = ""

    init(board: Board, session: Board.PrimSession) {
        self.board = board; self.session = session
        _record = State(initialValue: session.record)
    }

    private var fields: [String] {
        (session.kit.schema["properties"].object ?? [:]).keys.filter {
            ![session.kit.identityField, "profile", "profile_version", "format", "version"].contains($0)
        }.sorted { a, b in
            if a == session.kit.titleField { return true }
            if b == session.kit.titleField { return false }
            return a < b
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(session.kit.name).font(.title2.bold())
            Text("Private, encrypted record · \(session.kit.pin.version)").font(.caption).foregroundStyle(.secondary)
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    ForEach(fields, id: \.self) { field in fieldEditor(field) }
                    DisclosureGroup("All fields as JSON", isExpanded: $advanced) {
                        Text("Use this for collections and additional fields. Unrecognized fields are preserved.").font(.caption)
                        TextEditor(text: $raw).font(.system(.body, design: .monospaced)).frame(minHeight: 220)
                    }
                    .onChange(of: advanced) { _, expanded in
                        if expanded {
                            if raw.isEmpty { raw = String(decoding: (try? record.encoded()) ?? Data(), as: UTF8.self) }
                        } else if applyJSON() { raw = "" }
                    }
                }.padding(.vertical, 8)
            }
            if !error.isEmpty { Text(error).font(.caption).foregroundStyle(.red).textSelection(.enabled) }
            if error.isEmpty, !validationMessage.isEmpty { Text(validationMessage).font(.caption).foregroundStyle(.secondary) }
            HStack {
                Button("Cancel") { board.primSession = nil }.keyboardShortcut(.cancelAction)
                Spacer()
                Button("Check") { check() }
                Button("Save Prim") {
                    guard check() else { return }
                    do { try board.savePrim(session, record: record) }
                    catch { self.error = error.localizedDescription }
                }.keyboardShortcut(.defaultAction).buttonStyle(.borderedProminent)
            }
        }.padding(24).frame(width: 640, height: 620)
    }

    @ViewBuilder private func fieldEditor(_ field: String) -> some View {
        let schema = session.kit.schema["properties"][field]
        let label = field.replacingOccurrences(of: "_", with: " ").capitalized
        VStack(alignment: .leading, spacing: 5) {
            Text(label).font(.headline)
            if let choices = schema["enum"].array, choices.allSatisfy({ $0.string != nil }) {
                Picker(label, selection: binding(field)) {
                    ForEach(choices.compactMap(\.string), id: \.self) { Text($0).tag($0) }
                }.labelsHidden()
            } else if record[field].array != nil || record[field].object != nil {
                Text("\(record[field].array?.count ?? record[field].object?.count ?? 0) entries · edit in All fields as JSON")
                    .font(.caption).foregroundStyle(.secondary)
            } else {
                TextField(label, text: binding(field), axis: .vertical).textFieldStyle(.roundedBorder).lineLimit(1...5)
            }
        }.disabled(advanced)
    }

    private func binding(_ field: String) -> Binding<String> {
        Binding(get: { record[field].string ?? "" }, set: { value in
            var object = record.object ?? [:]
            let types = session.kit.schema["properties"][field]["type"].array ?? []
            object[field] = value.isEmpty && types.contains(.string("null")) ? .null : .string(value)
            record = .object(object)
        })
    }

    @discardableResult private func applyJSON() -> Bool {
        do { record = try PrimJSON.parse(Data(raw.utf8)); error = ""; return true }
        catch { self.error = error.localizedDescription; advanced = true; return false }
    }

    @discardableResult private func check() -> Bool {
        if advanced && !applyJSON() { return false }
        do { try session.kit.requireValid(record); error = ""; validationMessage = "Structure and declared references checked."; return true }
        catch { self.error = error.localizedDescription; return false }
    }
}

struct RecoverySheet: View {
    @ObservedObject var board: Board
    @State private var message = ""
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Notebook recovery").font(.title2.bold())
            Text(board.recoveryNeeded
                 ? "Primboard could not safely read or finish a notebook operation. Keep the notebook and its original Keychain key."
                 : "The notebook is available. Backups are encrypted and require its original Keychain key.")
            Button(board.locked ? "Unlock and retry" : "Reload notebook") {
                if board.locked { Task { await board.unlock() } } else { board.reloadNotebook() }
            }
            if board.pendingEditCount > 0 {
                Text("\(board.pendingEditCount) pending note edits are held in this app session. Keep the app open until you save them.")
                Button("Retry pending note saves") { board.retryPendingNotes() }
                    .disabled(board.locked || board.recoveryNeeded)
                Button("Save pending edits as separate notes") { board.savePendingCopies() }
                    .disabled(board.locked || board.recoveryNeeded)
            }
            Button("Save encrypted backup…") { backup() }.disabled(board.locked || board.recoveryNeeded)
            Button("Restore backup to a separate folder…") {
                Task { if await board.authenticateForRecovery() { restore() } }
            }
            Text("Restoring creates a separate notebook folder. Your active notebook stays in place. A missing Keychain key cannot be recovered from a same-key backup.")
                .font(.caption).foregroundStyle(.secondary)
            if !message.isEmpty { Text(message).font(.callout).textSelection(.enabled) }
            HStack { Spacer(); Button("Close") { board.showRecovery = false }.keyboardShortcut(.cancelAction) }
        }.padding(24).frame(width: 570)
    }

    private func backup() {
        let panel = NSSavePanel(); panel.nameFieldStringValue = "Primboard-backup.pboard"
        guard panel.runModal() == .OK, let target = panel.url, let store = board.store else { return }
        do { try store.exportBackup(to: target); message = "Encrypted backup saved." }
        catch { message = error.localizedDescription }
    }

    private func restore() {
        let panel = NSOpenPanel(); panel.canChooseDirectories = false; panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let source = panel.url else { return }
        let destination = NSSavePanel(); destination.nameFieldStringValue = "Primboard-restored"
        destination.message = "Choose a new folder name. Existing folders cannot be replaced."
        guard destination.runModal() == .OK, let target = destination.url else { return }
        do {
            guard let key = try KeychainKey.load() else { throw PrimLibraryError.invalid("The original Keychain key is unavailable. No replacement key was created.") }
            try NotebookStore.restoreBackup(from: source, to: target, key: key)
            message = "Backup validated and restored to a separate folder. The active notebook is unchanged."
            NSWorkspace.shared.activateFileViewerSelecting([target])
        } catch { message = error.localizedDescription }
    }
}
