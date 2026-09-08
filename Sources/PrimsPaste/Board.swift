import AppKit
import Combine
import Foundation
import LocalAuthentication
import PrimsPasteCore
import SwiftUI

@MainActor
final class Board: ObservableObject {
    @Published var items: [ItemMeta] = []
    @Published var tabs: [BoardTab] = []
    @Published var chat = ChatSettings.none
    @Published var locked = true
    @Published var shuttered = false
    @Published var selectedTabID = ItemMeta.today()
    @Published var pin = CGPoint(x: 360, y: 240)
    @Published var selectedID: String?
    @Published var errorText: String?
    @Published var pasteSheet = false
    @Published var typedPaste = ""
    @Published var unlockedOnce = false
    @Published var drag: StickyDrag?
    @Published var tabFrames: [String: CGRect] = [:]
    @Published var hoverTabID: String?
    @Published var showSettings = false
    @Published var showNewTab = false
    @Published var showCalendar = false
    @Published var calendarSpan: DateSpan?
    @Published var calendarDate = Date()
    @Published var viewMode: BoardViewMode = .layout
    @Published var newTabTitle = ""
    @Published var newTabColor = Color(red: 0.77, green: 0.36, blue: 0.15)
    @Published var taskSession: TaskSession?
    @Published var primSession: PrimSession?
    @Published var showPrimLibrary = false
    @Published var showRecovery = false
    @Published var recoveryNeeded = false
    @Published var reloadGeneration = 0
    private struct PendingNote {
        var text: String
        let expected: Data
        var recoveryID = "draft_" + UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased()
    }
    private var pendingNotes: [String: PendingNote] = [:]

    struct PrimSession: Identifiable {
        let id: String
        let sourceID: String?
        let existingID: String?
        let kit: PrimKit
        let record: PrimJSON
        let expected: Data?
    }

    struct TaskSession: Identifiable {
        var stickyID: String
        var card: DocketCard
        var id: String { stickyID }
    }

    let cache = BlobCache(cap: 8)
    let voice = VoiceAsk()
    private(set) var store: NotebookStore?
    private var noteTasks: [String: Task<Void, Never>] = [:]
    private var lastPoke = Date()

    var visibleItems: [ItemMeta] {
        var vis = items.filter { $0.tabID == selectedTabID }
        vis = CalendarLens.filter(vis, date: calendarDate, span: calendarSpan)
        return DragMath.paintOrder(vis, draggingID: drag?.id)
    }

    var calendarLabel: String {
        let f = DateFormatter()
        switch calendarSpan ?? (viewMode == .layout ? nil : spanForView) {
        case .day: f.dateFormat = "EEE d MMM yyyy"
        case .week: f.dateFormat = "'week of' d MMM"
        case .month: f.dateFormat = "MMMM yyyy"
        case .year: f.dateFormat = "yyyy"
        case .none: f.dateFormat = "d MMM yyyy"
        }
        if calendarSpan == .week || viewMode == .week {
            return f.string(from: CalendarLens.startOfWeek(calendarDate))
        }
        return f.string(from: calendarDate)
    }

    private var spanForView: DateSpan? {
        switch viewMode {
        case .layout, .timeline: return calendarSpan
        case .week: return .week
        case .month: return .month
        case .year: return .year
        }
    }

    func displayOrigin(_ item: ItemMeta) -> CGPoint {
        let map = CalendarLens.placed(
            visibleItems,
            mode: viewMode,
            date: calendarDate,
            sticky: CGSize(width: item.width, height: item.height)
        )
        let base = map[item.id] ?? CGPoint(x: item.x, y: item.y)
        if drag?.id == item.id, viewMode == .layout {
            return DragMath.position(start: base, translation: drag?.translation ?? .zero)
        }
        if drag?.id == item.id {
            return DragMath.position(start: base, translation: drag?.translation ?? .zero)
        }
        return base
    }

    func shiftCalendar(_ delta: Int) {
        let span = calendarSpan ?? spanForView ?? .day
        let cal = Calendar.current
        let unit: Calendar.Component = {
            switch span {
            case .day: return .day
            case .week: return .weekOfYear
            case .month: return .month
            case .year: return .year
            }
        }()
        calendarDate = cal.date(byAdding: unit, value: delta, to: calendarDate) ?? calendarDate
        poke()
    }

    var selectedTab: BoardTab? {
        tabs.first { $0.id == selectedTabID }
    }

    var working: Bool {
        drag != nil
            || voice.phase != .idle
            || pasteSheet
            || showSettings
            || showNewTab
            || showCalendar
            || showPrimLibrary
            || primSession != nil
            || showRecovery
    }

    var hoverTab: BoardTab? {
        tabs.first { $0.id == hoverTabID }
    }

    func poke() {
        lastPoke = Date()
        if shuttered && working { shuttered = false }
        refreshCover()
    }

    func refreshCover(windowActive: Bool? = nil) {
        let windowActive = windowActive ?? NSApp.isActive
        let idle = Date().timeIntervalSince(lastPoke)
        if locked { return }
        let want = CoverPolicy.shouldCover(
            working: working,
            windowActive: windowActive,
            idleFor: idle,
            unlocked: unlockedOnce && !locked
        )
        if want && !shuttered {
            cache.removeAll()
            shuttered = true
        } else if !want && shuttered && working {
            shuttered = false
        }
    }

    func unlock() async {
        errorText = nil
        let ctx = LAContext()
        ctx.localizedCancelTitle = "Cancel"
        var laError: NSError?
        let policy = LAPolicy.deviceOwnerAuthenticationWithBiometrics
        guard ctx.canEvaluatePolicy(policy, error: &laError) else {
            errorText = "Touch ID is required to open Primboard"
            return
        }
        do {
            let ok = try await ctx.evaluatePolicy(policy, localizedReason: "Open Primboard")
            if ok { openStore() }
        } catch {
            errorText = "Touch ID cancelled"
        }
    }

    func lockNotebook() {
        flushNotes()
        for task in noteTasks.values { task.cancel() }
        noteTasks.removeAll()
        cache.removeAll()
        typedPaste = ""
        selectedID = nil
        drag = nil
        voice.cancel()
        primSession = nil
        taskSession = nil
        showPrimLibrary = false
        showRecovery = false
        store = nil
        items = []
        tabs = []
        chat = .none
        locked = true
        shuttered = false
    }

    func toggleShutter() async {
        poke()
        if shuttered {
            shuttered = false
        } else {
            cache.removeAll()
            shuttered = true
        }
    }

    private func openStore() {
        do {
            let key = try KeychainKey.loadOrCreate()
            let store = try NotebookStore(root: Paths.defaultRoot, key: key)
            if StartupPolicy.developerSeedsEnabled() {
                try? store.seedFeaturesWanted()
            }
            self.store = store
            let idx = try store.loadIndex()
            items = idx.items
            tabs = idx.tabs
            chat = idx.chat
            selectedTabID = StartupPolicy.initialTabID(idx.tabs)
            locked = false
            unlockedOnce = true
            shuttered = false
            lastPoke = Date()
            recoveryNeeded = false
        } catch {
            self.store = nil
            items = []; tabs = []; cache.removeAll()
            errorText = "The notebook could not be opened. Its files have been preserved. Open Recovery to retry or restore a backup to a separate folder."
            recoveryNeeded = true
            locked = true
            shuttered = false
        }
    }

    func reloadNotebook() {
        guard let store, !locked else { return }
        do {
            let index = try store.loadIndex()
            items = index.items; tabs = index.tabs; chat = index.chat
            cache.removeAll(); reloadGeneration += 1
            recoveryNeeded = false
            errorText = nil
        } catch {
            recoveryNeeded = true
            errorText = "Recovery could not finish. Keep this notebook and its key. You can restore an encrypted backup to a separate folder."
            showRecovery = true
        }
    }

    func storeFailed(_ error: Error) {
        // A journal may already have committed. Reconcile before accepting another write.
        for task in noteTasks.values { task.cancel() }
        noteTasks.removeAll()
        reloadNotebook()
        errorText = recoveryNeeded
            ? "The notebook needs recovery. Files and pending edits have been preserved."
            : "The notebook was reloaded after a storage error. Check the latest contents before repeating the operation. Pending note edits remain available in Recovery."
        showRecovery = true
    }

    func flushNotes() {
        guard !locked, !recoveryNeeded else { return }
        for (id, draft) in Array(pendingNotes) { writeNote(id, text: draft.text) }
    }

    var pendingEditCount: Int { pendingNotes.count }

    func retryPendingNotes() {
        reloadNotebook()
        guard !recoveryNeeded else { return }
        flushNotes()
    }

    func savePendingCopies() {
        guard let store, !locked, !recoveryNeeded else { return }
        for (id, draft) in Array(pendingNotes) {
            do {
                _ = try store.saveDraftCopy(sourceID: id, plaintext: Data((draft.text.isEmpty ? " " : draft.text).utf8), operationID: draft.recoveryID)
                pendingNotes.removeValue(forKey: id)
            } catch { storeFailed(error); return }
        }
        reloadNotebook()
    }

    func startPrim(_ kit: PrimKit) {
        do {
            let source = items.first { $0.id == selectedID }
            let record = try kit.draft(title: source?.caption)
            primSession = PrimSession(id: "prim_" + UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased(),
                                      sourceID: source?.id, existingID: nil, kit: kit, record: record, expected: nil)
            showPrimLibrary = false
        } catch { errorText = error.localizedDescription }
    }

    func openPrim(_ id: String) {
        guard let store, let item = items.first(where: { $0.id == id }), let pin = item.primPin else { return }
        do {
            let kit = try PrimLibrary.bundled().kit(for: pin)
            let data = try store.readBlob(id: id)
            let record = try PrimJSON.parse(data)
            primSession = PrimSession(id: id, sourceID: item.primSourceID, existingID: id, kit: kit, record: record, expected: data)
        } catch { errorText = error.localizedDescription }
    }

    func savePrim(_ session: PrimSession, record: PrimJSON) throws {
        guard let store, !locked, !recoveryNeeded else { throw PrimLibraryError.invalid("Unlock and recover the notebook before saving.") }
        let meta: ItemMeta
        do {
            if let existing = session.existingID, let expected = session.expected {
                meta = try store.updatePrim(existing, kit: session.kit, record: record, expected: expected)
            } else {
                meta = try store.createPrim(sourceID: session.sourceID, kit: session.kit, record: record, operationID: session.id)
            }
        } catch let error as PrimLibraryError { throw error }
        catch { storeFailed(error); throw error }
        reloadNotebook()
        selectedID = meta.id; selectedTabID = meta.tabID
        primSession = nil
    }

    func exportPrim(_ id: String) {
        guard let store, !locked, !recoveryNeeded else { return }
        let panel = NSSavePanel(); panel.nameFieldStringValue = "Record.prim"
        panel.message = "Export a new Prim folder. These files are readable outside Primboard and are not encrypted."
        guard panel.runModal() == .OK, let target = panel.url else { return }
        do {
            try store.exportPrim(id, library: PrimLibrary.bundled(), to: target)
            NSWorkspace.shared.activateFileViewerSelecting([target])
        } catch { errorText = error.localizedDescription }
    }

    func importPrim() {
        guard !locked, !recoveryNeeded else { return }
        let panel = NSOpenPanel(); panel.canChooseFiles = false; panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let source = panel.url else { return }
        do {
            let (kit, record) = try PrimPack.read(source, library: PrimLibrary.bundled())
            primSession = PrimSession(id: "prim_" + UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased(),
                                      sourceID: nil, existingID: nil, kit: kit, record: record, expected: nil)
        } catch { errorText = error.localizedDescription }
    }

    func authenticateForRecovery() async -> Bool {
        if !locked { return true }
        let context = LAContext()
        do { return try await context.evaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, localizedReason: "Restore a Primboard backup") }
        catch { return false }
    }

    func payload(_ id: String) -> Data? {
        if let hit = cache.get(id) { return hit }
        guard let store, !locked, !recoveryNeeded else { return nil }
        do {
            let data = try store.readBlob(id: id)
            cache.set(id, data)
            return data
        } catch {
            storeFailed(error)
            return nil
        }
    }

    func payloadString(_ id: String) -> String {
        guard let data = payload(id) else { return "" }
        return String(data: data, encoding: .utf8) ?? ""
    }

    func dropPaste(_ text: String, at point: CGPoint? = nil) {
        poke()
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let guess = KeyDetector.inspect(trimmed)
        let caption = guess.isKey ? guess.label : ""
        guard let meta = add(
            .paste,
            Data(trimmed.utf8),
            at: point,
            size: BoardMetrics.stickySize,
            caption: caption,
            looksLikeKey: guess.isKey,
            keyKind: guess.isKey ? guess.kind : nil
        ) else { return }
        Task { await askWhatItWas(meta.id) }
    }

    func dropClipboard(at point: CGPoint? = nil) {
        poke()
        if let img = imageFromPasteboard() {
            let kind = selectedID.flatMap { id in items.first(where: { $0.id == id })?.kind }
            if point == nil, ImagePaste.attachToSelected(kind), let id = selectedID {
                attachImage(to: id, img)
            } else {
                dropImage(img, at: point)
            }
            return
        }
        let text = NSPasteboard.general.string(forType: .string) ?? ""
        if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            typedPaste = ""
            pasteSheet = true
            return
        }
        dropPaste(text, at: point)
    }

    func dropImage(_ data: Data, at point: CGPoint? = nil) {
        poke()
        guard !data.isEmpty else { return }
        add(
            .image,
            data,
            at: point,
            size: BoardMetrics.stickySize,
            caption: "screenshot"
        )
    }

    func attachImage(to id: String, _ data: Data) {
        poke()
        guard let store, !locked, !recoveryNeeded, !data.isEmpty else { return }
        do {
            try store.writeImage(id, png: data)
            if let i = items.firstIndex(where: { $0.id == id }) {
                items[i].hasImage = true
            }
            cache.set("\(id)-img", data)
        } catch {
            storeFailed(error)
        }
    }

    func imageAttachment(_ id: String) -> Data? {
        if let hit = cache.get("\(id)-img") { return hit }
        guard let store, !locked, !recoveryNeeded else { return nil }
        do {
            let data = try store.readImage(id)
            if let data { cache.set("\(id)-img", data) }
            return data
        } catch {
            return nil
        }
    }

    func dropNote(at point: CGPoint? = nil, text: String = " ") {
        poke()
        add(.note, Data(text.utf8), at: point, size: BoardMetrics.stickySize)
    }

    func dropAudioPlaceholder(at point: CGPoint? = nil) -> ItemMeta? {
        poke()
        return add(.audio, Data([0x00]), at: point, size: BoardMetrics.audioSize)
    }

    @discardableResult
    func add(
        _ kind: ItemKind,
        _ data: Data,
        at point: CGPoint?,
        size: CGSize,
        caption: String = "",
        looksLikeKey: Bool = false,
        keyKind: String? = nil
    ) -> ItemMeta? {
        guard let store, !locked, !recoveryNeeded else { return nil }
        let p = point ?? pin
        do {
            let meta = try store.add(
                kind: kind,
                plaintext: data,
                at: p,
                size: size,
                caption: caption,
                looksLikeKey: looksLikeKey,
                keyKind: keyKind,
                tabID: selectedTabID
            )
            cache.set(meta.id, data)
            items.append(meta)
            selectedID = meta.id
            return meta
        } catch NotebookError.emptyPayload {
            return nil
        } catch {
            storeFailed(error)
            return nil
        }
    }

    func beginDrag(id: String) {
        guard let i = items.firstIndex(where: { $0.id == id }) else { return }
        poke()
        selectedID = id
        items[i].z = DragMath.nextZ(items)
        drag = StickyDrag(id: id, start: displayOrigin(id: id))
    }

    func displayOrigin(id: String) -> CGPoint {
        guard let item = items.first(where: { $0.id == id }) else { return .zero }
        return displayOrigin(item)
    }

    func updateDrag(translation: CGSize, location: CGPoint) {
        guard drag != nil else { return }
        drag?.translation = translation
        drag?.location = location
        hoverTabID = DragMath.tabHit(location, frames: tabFrames)
    }

    func endDrag() {
        defer {
            drag = nil
            hoverTabID = nil
        }
        guard let store, !locked, !recoveryNeeded, let session = drag,
              let i = items.firstIndex(where: { $0.id == session.id }) else { return }
        do { items[i] = try store.bringToFront(session.id) }
        catch { storeFailed(error); return }
        if let tabID = hoverTabID, tabID != items[i].tabID {
            do {
                items[i] = try store.assignTab(session.id, tabID: tabID)
                selectedTabID = tabID
            } catch {
                storeFailed(error)
            }
            return
        }
        guard CalendarLens.canPersistLayout(viewMode) else { return }
        let next = DragMath.clamp(
            session.current,
            board: CGSize(width: BoardMetrics.width, height: BoardMetrics.height),
            sticky: CGSize(width: items[i].width, height: items[i].height)
        )
        do { try store.updateFrame(
            session.id,
            x: next.x,
            y: next.y,
            width: items[i].width,
            height: items[i].height
        )
            items[i].x = next.x; items[i].y = next.y
        } catch { storeFailed(error) }
    }

    func createTab() {
        let title = newTabTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty, let store, !locked, !recoveryNeeded else { return }
        do {
            let tab = try store.addTab(title: title, colorHex: newTabColor.hex)
            tabs.append(tab)
            selectedTabID = tab.id
            newTabTitle = ""
            showNewTab = false
            poke()
        } catch {
            storeFailed(error)
        }
    }

    func saveChatSettings() {
        if chat.rejectedBecauseOnline {
            errorText = "local models only — endpoint must be localhost"
            return
        }
        do {
            guard let store, !locked, !recoveryNeeded else { return }
            try store.saveChat(chat)
        } catch { storeFailed(error); return }
        showSettings = false
        poke()
    }

    func askWhatItWas(_ id: String) async {
        guard let said = await voice.captureCaption(for: id) else { return }
        saveCaption(id, said)
    }

    func convert(_ id: String, to target: ConvertTarget) {
        Task {
            do {
                _ = try await convertNow(id, to: target)
            } catch {
                storeFailed(error)
            }
        }
    }

    func convertNow(_ id: String, to target: ConvertTarget) async throws -> ItemMeta {
        poke()
        guard let store, !locked, !recoveryNeeded else { throw NotebookError.convert("store closed") }
        if target == .note {
            if let conv = items.first(where: { $0.id == id })?.conversion {
                try ConvertLive.shared.revert(conv)
            }
            let meta = try store.clearConversion(id)
            if let i = items.firstIndex(where: { $0.id == id }) {
                items[i] = meta
            }
            return meta
        }
        let caption = items.first(where: { $0.id == id })?.caption ?? ""
        let conv = try ConvertLive.shared.convert(
            target: target,
            stickyID: id,
            caption: caption
        )
        let meta = try store.convert(id, conversion: conv)
        if let i = items.firstIndex(where: { $0.id == id }) {
            items[i] = meta
        }
        return meta
    }

    func openTaskEditor(_ id: String) {
        poke()
        Task {
            do {
                var item = items.first(where: { $0.id == id })
                if item?.conversion?.target != .docketTask {
                    item = try await convertNow(id, to: .docketTask)
                }
                guard let item, let tid = Convert.docketID(from: item.conversion?.ref ?? "") else {
                    throw NotebookError.convert("no docket card")
                }
                let card = try ConvertLive.shared.viewTask(id: tid)
                taskSession = TaskSession(stickyID: id, card: card)
            } catch {
                storeFailed(error)
            }
        }
    }

    func closeTaskEditor() {
        taskSession = nil
        poke()
    }

    func saveTask(stickyID: String, card: DocketCard) {
        poke()
        do {
            try ConvertLive.shared.saveTask(card)
            if let store {
                _ = try store.updateCaption(stickyID, caption: card.title)
            }
            if let i = items.firstIndex(where: { $0.id == stickyID }) {
                items[i].caption = card.title
                if var conv = items[i].conversion {
                    conv.title = card.title
                    items[i].conversion = conv
                }
            }
            if var session = taskSession {
                session.card = card
                taskSession = session
            }
        } catch {
            storeFailed(error)
        }
    }

    func revertToNote(_ id: String) {
        convert(id, to: .note)
    }

    func saveCaption(_ id: String, _ caption: String) {
        guard let store, !locked, !recoveryNeeded else { return }
        do {
            let meta = try store.updateCaption(id, caption: caption)
            if let i = items.firstIndex(where: { $0.id == id }) {
                items[i] = meta
            }
        } catch {
            storeFailed(error)
        }
    }

    func saveNote(_ id: String, text: String) {
        poke()
        guard let store, !locked, !recoveryNeeded else { return }
        do {
            let expected: Data
            if let prior = pendingNotes[id]?.expected ?? cache.get(id) { expected = prior }
            else { expected = try store.readBlob(id: id) }
            var draft = pendingNotes[id] ?? PendingNote(text: text, expected: expected)
            draft.text = text
            pendingNotes[id] = draft
        } catch { storeFailed(error); return }
        noteTasks[id]?.cancel()
        noteTasks[id] = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 350_000_000)
            guard !Task.isCancelled else { return }
            self?.writeNote(id, text: text)
        }
    }

    private func writeNote(_ id: String, text: String) {
        guard let store, !locked, !recoveryNeeded else { return }
        let data = Data(text.utf8)
        guard !data.isEmpty else { return }
        do {
            let meta = try store.updatePayload(id, plaintext: data, expected: pendingNotes[id]?.expected)
            cache.set(id, data)
            pendingNotes.removeValue(forKey: id)
            if let i = items.firstIndex(where: { $0.id == id }) {
                items[i] = meta
            }
        } catch NotebookError.emptyPayload {
            return
        } catch {
            storeFailed(error)
        }
    }

    func saveAudio(_ id: String, data: Data) {
        guard let store, !locked, !recoveryNeeded else { return }
        do {
            let meta = try store.updatePayload(id, plaintext: data)
            cache.set(id, data)
            if let i = items.firstIndex(where: { $0.id == id }) {
                items[i] = meta
            }
        } catch {
            storeFailed(error)
        }
    }

    func deleteSelected() {
        guard let id = selectedID else { return }
        delete(id)
    }

    func delete(_ id: String) {
        guard let store, !locked, !recoveryNeeded else { return }
        do {
            try store.remove(id)
            noteTasks[id]?.cancel()
            noteTasks.removeValue(forKey: id)
            pendingNotes.removeValue(forKey: id)
            cache.remove(id)
            items.removeAll { $0.id == id }
            if selectedID == id { selectedID = nil }
        } catch {
            storeFailed(error)
        }
    }

    func commitTypedPaste() {
        dropPaste(typedPaste)
        typedPaste = ""
        pasteSheet = false
    }

    private func imageFromPasteboard() -> Data? {
        let pb = NSPasteboard.general
        if let png = pb.data(forType: .png), !png.isEmpty { return png }
        if let tiff = pb.data(forType: .tiff),
           let img = NSImage(data: tiff),
           let tiffRep = img.tiffRepresentation,
           let rep = NSBitmapImageRep(data: tiffRep),
           let png = rep.representation(using: .png, properties: [:]) {
            return png
        }
        return nil
    }
}

extension Color {
    var hex: String {
        let n = NSColor(self)
        guard let s = n.usingColorSpace(.sRGB) else { return "#888888" }
        return String(format: "#%02X%02X%02X", Int(s.redComponent * 255), Int(s.greenComponent * 255), Int(s.blueComponent * 255))
    }

    init(hex: String) {
        var h = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if h.hasPrefix("#") { h.removeFirst() }
        var n: UInt64 = 0
        Scanner(string: h).scanHexInt64(&n)
        self.init(
            red: Double((n >> 16) & 0xFF) / 255,
            green: Double((n >> 8) & 0xFF) / 255,
            blue: Double(n & 0xFF) / 255
        )
    }
}
