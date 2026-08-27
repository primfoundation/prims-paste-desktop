import PrimsPasteCore
import SwiftUI
import UniformTypeIdentifiers

struct BoardView: View {
    @ObservedObject var board: Board
    @ObservedObject var audio: AudioIO
    @State private var noteDrafts: [String: String] = [:]

    var body: some View {
        ZStack {
            Ink.board.ignoresSafeArea()
            VStack(spacing: 0) {
                toolbar
                bigTabs
                HStack(spacing: 0) {
                    ZStack {
                        canvas
                        if board.visibleItems.isEmpty, !board.shuttered {
                            emptyHint
                        }
                        if board.shuttered { shutter }
                        listenBanner
                    }
                    if board.showCalendar {
                        CalendarDrawer(board: board)
                    }
                }
            }
        }
        .coordinateSpace(name: "chrome")
        .focusable()
        .onDeleteCommand(perform: board.deleteSelected)
        .sheet(isPresented: $board.pasteSheet) { pasteSheet }
        .sheet(isPresented: $board.showSettings) { SettingsView(board: board) }
        .sheet(isPresented: $board.showNewTab) { NewTabSheet(board: board) }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didResignActiveNotification)) { _ in
            board.refreshCover(windowActive: false)
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            board.poke()
        }
        .onReceive(Timer.publish(every: 5, on: .main, in: .common).autoconnect()) { _ in
            board.refreshCover()
        }
        .alert(
            "Prims Paste",
            isPresented: Binding(
                get: { board.errorText != nil },
                set: { if !$0 { board.errorText = nil } }
            )
        ) {
            Button("OK", role: .cancel) { board.errorText = nil }
        } message: {
            Text(board.errorText ?? "")
        }
    }

    private var toolbar: some View {
        HStack(spacing: 12) {
            Text("Prims Paste")
                .font(Ink.serif)
                .foregroundStyle(Ink.ink)
            Spacer()
            tool("paste ⌘V") { board.dropClipboard() }
            tool("note") { board.dropNote() }
            tool("audio") { startAudio() }
            viewBtn("layout", .layout)
            viewBtn("time", .timeline)
            viewBtn("week", .week)
            viewBtn("month", .month)
            viewBtn("year", .year)
            tool("calendar") { board.showCalendar.toggle(); board.poke() }
            tool(board.shuttered ? "uncover" : "cover") {
                Task { await board.toggleShutter() }
            }
            tool("settings") { board.showSettings = true; board.poke() }
            tool("lock") { board.lockNotebook() }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Ink.bar)
    }

    private var bigTabs: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(board.tabs) { tab in
                    tabChip(tab)
                }
                Button {
                    board.newTabTitle = ""
                    board.showNewTab = true
                    board.poke()
                } label: {
                    Text("+")
                        .font(.system(size: 28, weight: .medium, design: .serif))
                        .frame(minWidth: 64, minHeight: 56)
                        .background(Color.black.opacity(0.06))
                        .foregroundStyle(Ink.ink)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
        }
        .background(Ink.bar)
    }

    private func tabChip(_ tab: BoardTab) -> some View {
        let on = tab.id == board.selectedTabID
        let hot = tab.id == board.hoverTabID
        return Button {
            board.selectedTabID = tab.id
            board.selectedID = nil
            board.poke()
        } label: {
            Text(tab.title)
                .font(.system(size: 18, weight: on ? .semibold : .regular, design: .serif))
                .padding(.horizontal, 22)
                .frame(minWidth: 140, minHeight: 56)
                .background(Color(hex: tab.colorHex).opacity(on || hot ? 1 : 0.55))
                .foregroundStyle(on || hot ? Color.white : Ink.ink)
                .overlay(
                    Rectangle()
                        .strokeBorder(hot ? Ink.listen : Color.clear, lineWidth: 3)
                )
        }
        .buttonStyle(.plain)
        .background(
            GeometryReader { g in
                Color.clear.preference(
                    key: TabFramePref.self,
                    value: [tab.id: g.frame(in: .named("chrome"))]
                )
            }
        )
        .onPreferenceChange(TabFramePref.self) { board.tabFrames.merge($0, uniquingKeysWith: { $1 }) }
    }

    private func viewBtn(_ label: String, _ mode: BoardViewMode) -> some View {
        let on = board.viewMode == mode
        return Button {
            board.viewMode = mode
            board.poke()
        } label: {
            Text(label)
                .font(Ink.mono)
                .foregroundStyle(on ? Color.white : Ink.ink)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(on ? Ink.tabOn : Color.black.opacity(0.06))
        }
        .buttonStyle(.plain)
    }

    private func tool(_ label: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(Ink.mono)
                .foregroundStyle(Ink.ink)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.black.opacity(0.06))
        }
        .buttonStyle(.plain)
    }

    private var canvas: some View {
        ScrollView([.horizontal, .vertical], showsIndicators: true) {
            ZStack(alignment: .topLeading) {
                boardBackground
                ForEach(board.visibleItems) { item in
                    card(item)
                }
            }
            .frame(width: BoardMetrics.width, height: BoardMetrics.height, alignment: .topLeading)
            .coordinateSpace(name: "board")
        }
        .scrollDisabled(board.drag != nil)
    }

    private var emptyHint: some View {
        VStack(spacing: 8) {
            Text(board.selectedTab?.title ?? "this tab")
                .font(Ink.serif)
                .foregroundStyle(Ink.ink)
            Text("drop anywhere  ·  drag a sticky onto a tab to tag it")
                .font(Ink.mono)
                .foregroundStyle(Ink.mute)
        }
        .allowsHitTesting(false)
    }

    private var shutter: some View {
        ZStack {
            Color(red: 0.12, green: 0.11, blue: 0.09).opacity(0.88)
            VStack(spacing: 12) {
                Text("covered")
                    .font(Ink.serif)
                    .foregroundStyle(Color.white)
                Text("idle")
                    .font(Ink.mono)
                    .foregroundStyle(Color.white.opacity(0.7))
                Button("uncover") { Task { await board.toggleShutter() } }
                    .font(Ink.mono)
                    .foregroundStyle(Color.white)
            }
        }
    }

    @ViewBuilder
    private var listenBanner: some View {
        if board.voice.phase != .idle {
            VStack {
                Spacer()
                HStack {
                    Circle().fill(Ink.listen).frame(width: 8, height: 8)
                    Text(bannerText).font(Ink.mono).foregroundStyle(Ink.ink)
                }
                .padding(10)
                .background(Ink.bar)
                .padding(16)
            }
            .allowsHitTesting(false)
        }
    }

    private var bannerText: String {
        switch board.voice.phase {
        case .speaking: return "asking what you pasted"
        case .listening: return "listening"
        case .transcribing: return "whisper…"
        case .idle: return ""
        }
    }

    private var boardBackground: some View {
        Canvas { ctx, size in
            let step: CGFloat = 56
            var x: CGFloat = 0
            while x < size.width {
                var y: CGFloat = 0
                while y < size.height {
                    ctx.fill(
                        Path(ellipseIn: CGRect(x: x + 0.5, y: y + 0.5, width: 1.1, height: 1.1)),
                        with: .color(Ink.grid)
                    )
                    y += step
                }
                x += step
            }
        }
        .frame(width: BoardMetrics.width, height: BoardMetrics.height)
        .contentShape(Rectangle())
        .onTapGesture(count: 1, coordinateSpace: .named("board")) { loc in
            board.pin = loc
            board.selectedID = nil
            board.poke()
        }
        .onTapGesture(count: 2, coordinateSpace: .named("board")) { loc in
            board.pin = loc
            board.dropNote(at: loc)
        }
        .onDrop(of: [.plainText, .image, .png, .tiff], isTargeted: nil) { providers, loc in
            board.pin = loc
            for p in providers {
                if p.canLoadObject(ofClass: NSImage.self) {
                    _ = p.loadObject(ofClass: NSImage.self) { obj, _ in
                        if let img = obj as? NSImage,
                           let tiff = img.tiffRepresentation,
                           let rep = NSBitmapImageRep(data: tiff),
                           let png = rep.representation(using: .png, properties: [:]) {
                            Task { @MainActor in board.dropImage(png, at: loc) }
                        }
                    }
                    return true
                }
                if p.hasItemConformingToTypeIdentifier("public.utf8-plain-text") {
                    _ = p.loadObject(ofClass: String.self) { str, _ in
                        if let str { Task { @MainActor in board.dropPaste(str, at: loc) } }
                    }
                    return true
                }
            }
            return false
        }
    }

    @ViewBuilder
    private func card(_ item: ItemMeta) -> some View {
        let session = board.drag
        let dragging = session?.id == item.id
        let origin = board.displayOrigin(item)
        let lift = CGSize(width: origin.x - item.x, height: origin.y - item.y)
        let begin = { board.beginDrag(id: item.id) }
        let changed: (CGSize, CGPoint) -> Void = { board.updateDrag(translation: $0, location: $1) }
        let ended = { board.endDrag() }
        let convert: (ConvertTarget) -> Void = { board.convert(item.id, to: $0) }
        switch item.kind {
        case .paste:
            PasteSticky(
                item: item,
                selected: board.selectedID == item.id,
                listening: board.voice.itemID == item.id,
                shuttered: board.shuttered,
                dragging: dragging,
                lift: lift,
                bodyText: { board.payloadString(item.id) },
                onSelect: { board.selectedID = item.id; board.poke() },
                onDelete: { board.delete(item.id) },
                onDragBegin: begin,
                onDragChanged: changed,
                onDragEnded: ended,
                onConvert: convert
            )
        case .note:
            NoteSticky(
                item: item,
                selected: board.selectedID == item.id,
                dragging: dragging,
                lift: lift,
                text: draftBinding(item),
                onSelect: { board.selectedID = item.id; board.poke() },
                onDelete: { board.delete(item.id) },
                onDragBegin: begin,
                onDragChanged: changed,
                onDragEnded: ended,
                onConvert: convert,
                onSave: { board.saveNote(item.id, text: $0) }
            )
        case .audio:
            AudioSticky(
                item: item,
                selected: board.selectedID == item.id,
                recording: audio.recordingID == item.id,
                playing: audio.playingID == item.id,
                seconds: audio.seconds,
                dragging: dragging,
                lift: lift,
                onSelect: { board.selectedID = item.id; board.poke() },
                onDelete: {
                    if audio.recordingID == item.id { _ = audio.stopRecording() }
                    board.delete(item.id)
                },
                onDragBegin: begin,
                onDragChanged: changed,
                onDragEnded: ended,
                onConvert: convert,
                onRecord: { record(item) },
                onStopRecord: { stopRecord(item) },
                onPlay: { play(item) },
                onStopPlay: { audio.stopPlay() }
            )
        case .image:
            ImageSticky(
                item: item,
                selected: board.selectedID == item.id,
                dragging: dragging,
                lift: lift,
                imageData: { board.payload(item.id) },
                onSelect: { board.selectedID = item.id; board.poke() },
                onDelete: { board.delete(item.id) },
                onDragBegin: begin,
                onDragChanged: changed,
                onDragEnded: ended,
                onConvert: convert
            )
        }
    }

    private func draftBinding(_ item: ItemMeta) -> Binding<String> {
        Binding(
            get: {
                if let d = noteDrafts[item.id] { return d }
                let s = board.payloadString(item.id)
                return s == " " ? "" : s
            },
            set: { noteDrafts[item.id] = $0 }
        )
    }

    private func startAudio() {
        guard let meta = board.dropAudioPlaceholder() else { return }
        record(meta)
    }

    private func record(_ item: ItemMeta) {
        do {
            try audio.startRecording(id: item.id)
            board.poke()
        } catch {
            board.errorText = "microphone: \(error.localizedDescription)"
            board.delete(item.id)
        }
    }

    private func stopRecord(_ item: ItemMeta) {
        if let data = audio.stopRecording(), data.count > 1 {
            board.saveAudio(item.id, data: data)
        } else {
            board.delete(item.id)
        }
    }

    private func play(_ item: ItemMeta) {
        guard let data = board.payload(item.id), data.count > 1 else { return }
        do { try audio.play(id: item.id, data: data) }
        catch { board.errorText = "play: \(error.localizedDescription)" }
    }

    private var pasteSheet: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Drop a paste").font(Ink.serif)
            SecureField("secret", text: $board.typedPaste)
                .textFieldStyle(.roundedBorder)
                .frame(width: 360)
            HStack {
                Button("Cancel") { board.pasteSheet = false }
                Spacer()
                Button("Drop") { board.commitTypedPaste() }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(minWidth: 400)
    }
}

private struct TabFramePref: PreferenceKey {
    static var defaultValue: [String: CGRect] = [:]
    static func reduce(value: inout [String: CGRect], nextValue: () -> [String: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { $1 })
    }
}
