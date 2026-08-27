import AppKit
import PrimsPasteCore
import SwiftUI

struct StickyCard<Content: View>: View {
    let item: ItemMeta
    let selected: Bool
    let listening: Bool
    let dragging: Bool
    let lift: CGSize
    let onSelect: () -> Void
    let onDelete: () -> Void
    let onDragBegin: () -> Void
    let onDragChanged: (CGSize, CGPoint) -> Void
    let onDragEnded: () -> Void
    let onConvert: (ConvertTarget) -> Void
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Rectangle()
                    .fill(item.looksLikeKey ? Ink.keyTape : Color.black.opacity(0.18))
                    .frame(width: 36, height: 12)
                Text(stamp(item.createdAt))
                    .font(Ink.small)
                    .foregroundStyle(Ink.mute)
                Spacer()
                Menu {
                    ForEach(ConvertTarget.allCases) { t in
                        Button(t.menuLabel) { onConvert(t) }
                    }
                } label: {
                    Text(item.conversion?.target.badge ?? "convert")
                        .font(Ink.small)
                        .foregroundStyle(item.conversion == nil ? Ink.mute : Ink.tabOn)
                }
                .menuStyle(.borderlessButton)
                Button(action: onDelete) {
                    Text("×")
                        .font(Ink.mono)
                        .foregroundStyle(Ink.mute)
                }
                .buttonStyle(.plain)
            }

            if let conv = item.conversion {
                Text("\(conv.target.badge)  \(conv.title)")
                    .font(Ink.small)
                    .foregroundStyle(Ink.tabOn)
            }
            if item.looksLikeKey {
                Text(item.keyKind?.uppercased() ?? "KEY")
                    .font(Ink.small)
                    .foregroundStyle(Ink.keyTape)
            }

            if listening {
                Text("listening…")
                    .font(Ink.mono)
                    .foregroundStyle(Ink.listen)
            } else if !item.caption.isEmpty {
                Text(item.caption)
                    .font(Ink.body)
                    .foregroundStyle(Ink.ink)
                    .fixedSize(horizontal: false, vertical: true)
            }

            content()
            Spacer(minLength: 0)
        }
        .padding(12)
        .frame(width: item.width, height: item.height, alignment: .topLeading)
        .background(Ink.paper(for: item))
        .overlay(
            Rectangle()
                .strokeBorder(
                    dragging ? Ink.accent : selected ? Ink.ink : Ink.line,
                    lineWidth: dragging || selected ? 1.5 : 1
                )
        )
        .rotationEffect(.degrees(dragging ? 0 : item.tilt * 0.35))
        .scaleEffect(dragging ? 1.05 : 1)
        .offset(x: item.x + lift.width, y: item.y + lift.height)
        .zIndex(dragging ? 10_000 : Double(item.z))
        .onTapGesture { onSelect() }
        .highPriorityGesture(drag)
    }

    private var drag: some Gesture {
        DragGesture(minimumDistance: DragMath.activation, coordinateSpace: .named("chrome"))
            .onChanged { value in
                if !dragging { onDragBegin() }
                onDragChanged(value.translation, value.location)
            }
            .onEnded { _ in onDragEnded() }
    }
}

struct PasteSticky: View {
    let item: ItemMeta
    let selected: Bool
    let listening: Bool
    let shuttered: Bool
    let dragging: Bool
    let lift: CGSize
    let bodyText: () -> String
    let onSelect: () -> Void
    let onDelete: () -> Void
    let onDragBegin: () -> Void
    let onDragChanged: (CGSize, CGPoint) -> Void
    let onDragEnded: () -> Void
    let onConvert: (ConvertTarget) -> Void
    @State private var revealed = false
    @State private var copied = false

    var body: some View {
        StickyCard(
            item: item, selected: selected, listening: listening, dragging: dragging, lift: lift,
            onSelect: onSelect, onDelete: onDelete, onDragBegin: onDragBegin, onDragChanged: onDragChanged, onDragEnded: onDragEnded, onConvert: onConvert
        ) {
            if shuttered {
                Text("covered").font(Ink.small).foregroundStyle(Ink.mute)
            } else if SecretFace.hidesPayload(
                looksLikeKey: item.looksLikeKey, revealed: revealed, shuttered: false
            ) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("••••••••")
                        .font(Ink.mono)
                        .foregroundStyle(Ink.mute)
                    copyRevealRow
                }
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    ScrollView {
                        Text(bodyText())
                            .font(Ink.mono)
                            .foregroundStyle(Ink.ink)
                            .textSelection(.enabled)
                    }
                    if SecretFace.showsCopyReveal(looksLikeKey: item.looksLikeKey, shuttered: false) {
                        copyRevealRow
                    }
                }
            }
        }
    }

    private var copyRevealRow: some View {
        HStack(spacing: 8) {
            faceBtn(copied ? "copied" : "copy", action: copySecret)
            faceBtn(revealed ? "hide" : "reveal") { revealed.toggle() }
            Spacer(minLength: 0)
        }
    }

    private func faceBtn(_ label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(Ink.mono)
                .foregroundStyle(Ink.ink)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Ink.surface)
                .overlay(Rectangle().strokeBorder(Ink.line, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    private func copySecret() {
        let value = bodyText()
        guard !value.isEmpty else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(value, forType: .string)
        copied = true
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_400_000_000)
            copied = false
        }
    }
}

struct NoteSticky: View {
    let item: ItemMeta
    let selected: Bool
    let dragging: Bool
    let lift: CGSize
    @Binding var text: String
    let onSelect: () -> Void
    let onDelete: () -> Void
    let onDragBegin: () -> Void
    let onDragChanged: (CGSize, CGPoint) -> Void
    let onDragEnded: () -> Void
    let onConvert: (ConvertTarget) -> Void
    let onSave: (String) -> Void

    var body: some View {
        StickyCard(
            item: item, selected: selected, listening: false, dragging: dragging, lift: lift,
            onSelect: onSelect, onDelete: onDelete, onDragBegin: onDragBegin, onDragChanged: onDragChanged, onDragEnded: onDragEnded, onConvert: onConvert
        ) {
            TextEditor(text: $text)
                .font(Ink.body)
                .foregroundStyle(Ink.ink)
                .scrollContentBackground(.hidden)
                .onChange(of: text) { _, new in onSave(new) }
        }
    }
}

struct AudioSticky: View {
    let item: ItemMeta
    let selected: Bool
    let recording: Bool
    let playing: Bool
    let seconds: Int
    let dragging: Bool
    let lift: CGSize
    let onSelect: () -> Void
    let onDelete: () -> Void
    let onDragBegin: () -> Void
    let onDragChanged: (CGSize, CGPoint) -> Void
    let onDragEnded: () -> Void
    let onConvert: (ConvertTarget) -> Void
    let onRecord: () -> Void
    let onStopRecord: () -> Void
    let onPlay: () -> Void
    let onStopPlay: () -> Void

    var body: some View {
        StickyCard(
            item: item, selected: selected, listening: recording, dragging: dragging, lift: lift,
            onSelect: onSelect, onDelete: onDelete, onDragBegin: onDragBegin, onDragChanged: onDragChanged, onDragEnded: onDragEnded, onConvert: onConvert
        ) {
            HStack(spacing: 8) {
                Button(recording ? "stop" : "rec", action: recording ? onStopRecord : onRecord)
                    .font(Ink.mono).buttonStyle(.plain)
                Button(playing ? "stop" : "play", action: playing ? onStopPlay : onPlay)
                    .font(Ink.mono).buttonStyle(.plain)
                    .disabled(item.bytes <= 1 && !recording)
                Spacer()
            }
        }
    }
}

struct ImageSticky: View {
    let item: ItemMeta
    let selected: Bool
    let dragging: Bool
    let lift: CGSize
    let imageData: () -> Data?
    let onSelect: () -> Void
    let onDelete: () -> Void
    let onDragBegin: () -> Void
    let onDragChanged: (CGSize, CGPoint) -> Void
    let onDragEnded: () -> Void
    let onConvert: (ConvertTarget) -> Void

    var body: some View {
        StickyCard(
            item: item, selected: selected, listening: false, dragging: dragging, lift: lift,
            onSelect: onSelect, onDelete: onDelete, onDragBegin: onDragBegin, onDragChanged: onDragChanged, onDragEnded: onDragEnded, onConvert: onConvert
        ) {
            if let data = imageData(), let ns = NSImage(data: data) {
                Image(nsImage: ns)
                    .resizable()
                    .scaledToFill()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .clipped()
            } else {
                Text("image").font(Ink.small).foregroundStyle(Ink.mute)
            }
        }
    }
}
