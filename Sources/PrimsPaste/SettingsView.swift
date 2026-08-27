import PrimsPasteCore
import SwiftUI

struct SettingsView: View {
    @ObservedObject var board: Board

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Local chat")
                .font(Ink.title)
            Text("Notes stay on this Mac. No cloud models.")
                .font(Ink.small)
                .foregroundStyle(Ink.mute)

            Picker("Engine", selection: $board.chat.engine) {
                Text("off").tag("none")
                Text("Ollama (localhost)").tag("ollama")
                Text("llama.cpp server").tag("llamacpp")
                Text("MLX").tag("mlx")
            }

            TextField("http://127.0.0.1:11434", text: $board.chat.endpoint)
                .textFieldStyle(.roundedBorder)
            TextField("model name", text: $board.chat.model)
                .textFieldStyle(.roundedBorder)
            TextField("optional GGUF path", text: $board.chat.modelPath)
                .textFieldStyle(.roundedBorder)

            if board.chat.rejectedBecauseOnline {
                Text("That endpoint is not local. Use 127.0.0.1 or localhost.")
                    .font(Ink.small)
                    .foregroundStyle(Ink.keyTape)
            }

            HStack {
                Button("Close") { board.showSettings = false }
                Spacer()
                Button("Save") { board.saveChatSettings() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(board.chat.rejectedBecauseOnline)
            }
        }
        .padding(20)
        .frame(minWidth: 420)
    }
}

struct NewTabSheet: View {
    @ObservedObject var board: Board

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("New tab")
                .font(Ink.title)
            TextField("name", text: $board.newTabTitle)
                .textFieldStyle(.roundedBorder)
            ColorPicker("color", selection: $board.newTabColor, supportsOpacity: false)
            HStack {
                Button("Cancel") { board.showNewTab = false }
                Spacer()
                Button("Add") { board.createTab() }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(minWidth: 360)
    }
}
