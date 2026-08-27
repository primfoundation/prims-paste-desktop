import PrimsPasteCore
import SwiftUI

struct TaskEditor: View {
    @ObservedObject var board: Board
    let stickyID: String
    @State var card: DocketCard
    @State private var reqText: String
    @State private var caseText: String
    @State private var acceptText: String
    @State private var saving = false

    init(board: Board, stickyID: String, card: DocketCard) {
        self.board = board
        self.stickyID = stickyID
        _card = State(initialValue: card)
        _reqText = State(initialValue: card.requirements.joined(separator: "\n"))
        _caseText = State(initialValue: card.testCases.joined(separator: "\n"))
        _acceptText = State(initialValue: card.acceptance.joined(separator: "\n"))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                FolioMark(fill: Ink.ink).frame(width: 18, height: 18)
                Text(card.id)
                    .font(Ink.mono)
                    .foregroundStyle(Ink.mute)
                Spacer()
                Button("Note") { board.convert(stickyID, to: .note); board.closeTaskEditor() }
                    .font(Ink.mono)
                    .buttonStyle(.plain)
                Button("Close") { board.closeTaskEditor() }
                    .font(Ink.mono)
                    .buttonStyle(.plain)
                Button("Save") { save() }
                    .font(Ink.mono)
                    .buttonStyle(.plain)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Ink.accent)
                    .foregroundStyle(Ink.accentInk)
                    .disabled(saving)
            }

            TextField("title", text: $card.title)
                .font(Ink.title)
                .textFieldStyle(.plain)

            HStack(spacing: 12) {
                Picker("status", selection: $card.status) {
                    Text("To Do").tag("To Do")
                    Text("In Progress").tag("In Progress")
                    Text("Done").tag("Done")
                    Text("Draft").tag("Draft")
                }
                Picker("priority", selection: $card.priority.orEmpty) {
                    Text("—").tag("")
                    Text("high").tag("high")
                    Text("medium").tag("medium")
                    Text("low").tag("low")
                }
                TextField("due YYYY-MM-DD", text: $card.due.orEmpty)
                    .font(Ink.mono)
                    .frame(width: 140)
            }
            .font(Ink.mono)

            TextField("blocked reason", text: $card.blockedReason.orEmpty)
                .font(Ink.mono)

            labeled("notes") {
                TextEditor(text: $card.notes)
                    .font(Ink.body)
                    .frame(minHeight: 120)
                    .scrollContentBackground(.hidden)
                    .overlay(Rectangle().strokeBorder(Ink.line, lineWidth: 1))
            }
            labeled("requirements") {
                TextEditor(text: $reqText)
                    .font(Ink.mono)
                    .frame(minHeight: 72)
                    .scrollContentBackground(.hidden)
                    .overlay(Rectangle().strokeBorder(Ink.line, lineWidth: 1))
            }
            labeled("test-cases") {
                TextEditor(text: $caseText)
                    .font(Ink.mono)
                    .frame(minHeight: 56)
                    .scrollContentBackground(.hidden)
                    .overlay(Rectangle().strokeBorder(Ink.line, lineWidth: 1))
            }
            labeled("acceptance") {
                TextEditor(text: $acceptText)
                    .font(Ink.mono)
                    .frame(minHeight: 56)
                    .scrollContentBackground(.hidden)
                    .overlay(Rectangle().strokeBorder(Ink.line, lineWidth: 1))
            }
        }
        .padding(20)
        .frame(minWidth: 640, minHeight: 560)
        .background(Ink.board)
    }

    private func labeled(_ title: String, @ViewBuilder _ content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(Ink.small).foregroundStyle(Ink.mute)
            content()
        }
    }

    private func save() {
        saving = true
        card.requirements = DocketCard.lines(reqText)
        card.testCases = DocketCard.lines(caseText)
        card.acceptance = DocketCard.lines(acceptText)
        board.saveTask(stickyID: stickyID, card: card)
        saving = false
    }
}

private extension Binding where Value == String? {
    var orEmpty: Binding<String> {
        Binding<String>(
            get: { wrappedValue ?? "" },
            set: { new in wrappedValue = new.isEmpty ? nil : new }
        )
    }
}
