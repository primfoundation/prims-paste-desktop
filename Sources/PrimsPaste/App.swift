import AppKit
import PrimsPasteCore
import SwiftUI

@main
struct PrimsPasteMain {
    static func main() {
        if CommandLine.arguments.contains("--selftest") {
            Selftest.run()
            return
        }
        PrimsPasteApp.main()
    }
}

struct PrimsPasteApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate
    @StateObject private var board = Board()
    @StateObject private var audio = AudioIO()

    var body: some Scene {
        WindowGroup("Prims Paste") {
            Group {
                if board.locked {
                    UnlockView(board: board)
                } else {
                    BoardView(board: board, audio: audio)
                }
            }
            .frame(minWidth: 820, minHeight: 560)
            .background(WindowGuard())
            .onAppear { NSApp.setActivationPolicy(.regular) }
        }
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("Paste from clipboard") { board.dropClipboard() }
                    .keyboardShortcut("v", modifiers: [.command])
                    .disabled(board.locked)
                Button("New sticky") { board.dropNote() }
                    .keyboardShortcut("n", modifiers: [.command])
                    .disabled(board.locked)
                Button("New audio note") {
                    if let meta = board.dropAudioPlaceholder() {
                        try? audio.startRecording(id: meta.id)
                    }
                }
                .keyboardShortcut("r", modifiers: [.command])
                .disabled(board.locked)
            }
            CommandGroup(after: .newItem) {
                Button(board.shuttered ? "Uncover board" : "Cover board") {
                    Task { await board.toggleShutter() }
                }
                .keyboardShortcut("l", modifiers: [.command])
                .disabled(board.locked)
                Button("Lock notebook") { board.lockNotebook() }
                    .keyboardShortcut("l", modifiers: [.command, .shift])
                    .disabled(board.locked)
                Button("Settings") { board.showSettings = true }
                    .keyboardShortcut(",", modifiers: [.command])
                    .disabled(board.locked)
            }
        }
    }
}

struct UnlockView: View {
    @ObservedObject var board: Board

    var body: some View {
        ZStack {
            Ink.board
            VStack(spacing: 18) {
                FolioMark(fill: Ink.ink)
                    .frame(width: 72, height: 72)
                    .padding(.bottom, 6)
                Text("Prims Paste")
                    .font(Ink.display)
                    .foregroundStyle(Ink.ink)
                Button("Touch ID") {
                    Task { await board.unlock() }
                }
                .keyboardShortcut(.defaultAction)
                .font(Ink.mono)
                .buttonStyle(.plain)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Ink.accent)
                .foregroundStyle(Ink.accentInk)
                if let err = board.errorText {
                    Text(err).font(Ink.small).foregroundStyle(Ink.keyTape)
                }
            }
        }
        .task {
            if !board.unlockedOnce {
                await board.unlock()
            }
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        hardenWindows()
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        hardenWindows()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    private func hardenWindows() {
        for w in NSApp.windows {
            w.sharingType = .none
        }
    }
}

/// Keeps screen-sharing from capturing the notebook window.
struct WindowGuard: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let v = NSView()
        DispatchQueue.main.async {
            v.window?.sharingType = .none
        }
        return v
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        nsView.window?.sharingType = .none
    }
}
