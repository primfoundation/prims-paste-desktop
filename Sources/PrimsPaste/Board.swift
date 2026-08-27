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
            errorText = "Touch ID is required to open Prims Paste"
            return
        }
        do {
            let ok = try await ctx.evaluatePolicy(policy, localizedReason: "Open Prims Paste")
            if ok { openStore() }
        } catch {
            errorText = "Touch ID cancelled"
        }
    }

    func lockNotebook() {
        cache.removeAll()
        typedPaste = ""
        selectedID = nil
        drag = nil
        voice.cancel()
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
            try? store.seedFeaturesWanted()
            self.store = store
            let idx = try store.loadIndex()
            items = idx.items
            tabs = idx.tabs
            chat = idx.chat
            selectedTabID = FeaturesWanted.tabID
            locked = false
            unlockedOnce = true
            shuttered = false
            lastPoke = Date()
        } catch {
            errorText = "\(error)"
            locked = false
            unlockedOnce = true
            shuttered = false
        }
    }

    func payload(_ id: String) -> Data? {
        if let hit = cache.get(id) { return hit }
        guard let store else { return nil }
        do {
            let data = try store.readBlob(id: id)
            cache.set(id, data)
            return data
        } catch {
            errorText = "\(error)"
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
            dropImage(img, at: point)
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
        guard let store else { return nil }
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
            errorText = "\(error)"
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
        guard let session = drag, let i = items.firstIndex(where: { $0.id == session.id }) else { return }
        if let front = try? store?.bringToFront(session.id) {
            items[i] = front
        }
        if let tabID = hoverTabID, tabID != items[i].tabID {
            do {
                items[i] = try store?.assignTab(session.id, tabID: tabID) ?? items[i]
                selectedTabID = tabID
            } catch {
                errorText = "\(error)"
            }
            return
        }
        guard CalendarLens.canPersistLayout(viewMode) else { return }
        let next = DragMath.clamp(
            session.current,
            board: CGSize(width: BoardMetrics.width, height: BoardMetrics.height),
            sticky: CGSize(width: items[i].width, height: items[i].height)
        )
        items[i].x = next.x
        items[i].y = next.y
        try? store?.updateFrame(
            session.id,
            x: next.x,
            y: next.y,
            width: items[i].width,
            height: items[i].height
        )
    }

    func createTab() {
        let title = newTabTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty, let store else { return }
        do {
            let tab = try store.addTab(title: title, colorHex: newTabColor.hex)
            tabs.append(tab)
            selectedTabID = tab.id
            newTabTitle = ""
            showNewTab = false
            poke()
        } catch {
            errorText = "\(error)"
        }
    }

    func saveChatSettings() {
        if chat.rejectedBecauseOnline {
            errorText = "local models only — endpoint must be localhost"
            return
        }
        try? store?.saveChat(chat)
        showSettings = false
        poke()
    }

    func askWhatItWas(_ id: String) async {
        guard let said = await voice.captureCaption(for: id) else { return }
        saveCaption(id, said)
    }

    func convert(_ id: String, to target: ConvertTarget) {
        poke()
        guard let store else { return }
        let caption = items.first(where: { $0.id == id })?.caption ?? ""
        Task {
            do {
                let conv = try ConvertLive.shared.convert(
                    target: target,
                    stickyID: id,
                    caption: caption
                )
                let meta = try store.convert(id, conversion: conv)
                await MainActor.run {
                    if let i = self.items.firstIndex(where: { $0.id == id }) {
                        self.items[i] = meta
                    }
                }
            } catch {
                await MainActor.run { self.errorText = "\(error)" }
            }
        }
    }

    func saveCaption(_ id: String, _ caption: String) {
        guard let store else { return }
        do {
            let meta = try store.updateCaption(id, caption: caption)
            if let i = items.firstIndex(where: { $0.id == id }) {
                items[i] = meta
            }
        } catch {
            errorText = "\(error)"
        }
    }

    func saveNote(_ id: String, text: String) {
        poke()
        noteTasks[id]?.cancel()
        noteTasks[id] = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 350_000_000)
            guard !Task.isCancelled else { return }
            self?.writeNote(id, text: text)
        }
    }

    private func writeNote(_ id: String, text: String) {
        guard let store else { return }
        let data = Data(text.utf8)
        guard !data.isEmpty else { return }
        do {
            let meta = try store.updatePayload(id, plaintext: data)
            cache.set(id, data)
            if let i = items.firstIndex(where: { $0.id == id }) {
                items[i] = meta
            }
        } catch NotebookError.emptyPayload {
            return
        } catch {
            errorText = "\(error)"
        }
    }

    func saveAudio(_ id: String, data: Data) {
        guard let store else { return }
        do {
            let meta = try store.updatePayload(id, plaintext: data)
            cache.set(id, data)
            if let i = items.firstIndex(where: { $0.id == id }) {
                items[i] = meta
            }
        } catch {
            errorText = "\(error)"
        }
    }

    func deleteSelected() {
        guard let id = selectedID else { return }
        delete(id)
    }

    func delete(_ id: String) {
        do {
            try store?.remove(id)
            cache.remove(id)
            items.removeAll { $0.id == id }
            if selectedID == id { selectedID = nil }
        } catch {
            errorText = "\(error)"
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
