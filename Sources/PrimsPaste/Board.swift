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
        guard let store, !data.isEmpty else { return }
        do {
            try store.writeImage(id, png: data)
            if let i = items.firstIndex(where: { $0.id == id }) {
                items[i].hasImage = true
            }
            cache.set("\(id)-img", data)
        } catch {
            errorText = "\(error)"
        }
    }

    func imageAttachment(_ id: String) -> Data? {
        if let hit = cache.get("\(id)-img") { return hit }
        guard let store else { return nil }
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
        guard let store else { return }
        do {
            try store.saveChat(chat)
            poke()
        } catch {
            errorText = "\(error)"
        }
    }

    func delete(_ id: String) {
        guard let store else { return }
        do {
            try store.remove(id)
            items.removeAll { $0.id == id }
            cache.remove(id)
            cache.remove("\(id)-img")
            if selectedID == id { selectedID = nil }
        } catch {
            errorText = "\(error)"
        }
    }

    func addNewTabFromSheet() {
        createTab()
    }

    func selectTab(_ id: String) {
        selectedTabID = id
        selectedID = nil
        poke()
    }

    func loadTaskSession(_ stickyID: String, conversion: Conversion) {
        guard conversion.target == .docketTask, let id = Convert.docketID(from: conversion.ref) else { return }
        do {
            let card = try ConvertLive.shared.viewTask(id: id)
            taskSession = TaskSession(stickyID: stickyID, card: card)
        } catch {
            errorText = "\(error)"
        }
    }

    func saveTaskSession() {
        guard let taskSession else { return }
        do {
            try ConvertLive.shared.saveTask(taskSession.card)
            self.taskSession = nil
        } catch {
            errorText = "\(error)"
        }
    }

    func cancelTaskSession() {
        taskSession = nil
    }

    func convert(_ id: String, target: ConvertTarget) {
        guard let store, let i = items.firstIndex(where: { $0.id == id }) else { return }
        do {
            if target == .note {
                if let existing = items[i].conversion {
                    try ConvertLive.shared.revert(existing)
                    items[i] = try store.clearConversion(id)
                }
                return
            }
            let conv = try ConvertLive.shared.convert(
                target: target,
                stickyID: id,
                caption: items[i].caption
            )
            items[i] = try store.convert(id, conversion: conv)
        } catch {
            errorText = "\(error)"
        }
    }

    private func imageFromPasteboard() -> Data? {
        let pb = NSPasteboard.general
        guard let data = pb.data(forType: .png) ?? pb.data(forType: .tiff) else { return nil }
        if pb.availableType(from: [.png]) != nil { return data }
        guard let image = NSImage(data: data),
              let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff) else { return nil }
        return rep.representation(using: .png, properties: [:])
    }

    private func askWhatItWas(_ id: String) async {
        guard let store, let item = items.first(where: { $0.id == id }) else { return }
        guard !item.looksLikeKey else { return }
        guard voice.enabled else { return }
        guard let text = await voice.askWhatItWas() else { return }
        do {
            let meta = try store.updateCaption(id, caption: text)
            if let i = items.firstIndex(where: { $0.id == id }) { items[i] = meta }
        } catch {
            errorText = "\(error)"
        }
    }
}
