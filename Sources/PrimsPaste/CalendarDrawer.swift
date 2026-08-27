import PrimsPasteCore
import SwiftUI

struct CalendarDrawer: View {
    @ObservedObject var board: Board

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Calendar")
                    .font(Ink.title)
                Spacer()
                Button("close") {
                    board.showCalendar = false
                    board.poke()
                }
                .font(Ink.mono)
                .buttonStyle(.plain)
            }

            Text("filter cards")
                .font(Ink.small)
                .foregroundStyle(Ink.mute)

            HStack(spacing: 6) {
                spanBtn("D", .day)
                spanBtn("W", .week)
                spanBtn("M", .month)
                spanBtn("Y", .year)
            }

            HStack {
                Button("‹") { board.shiftCalendar(-1) }
                    .font(Ink.title)
                    .buttonStyle(.plain)
                Spacer()
                Text(board.calendarLabel)
                    .font(Ink.mono)
                Spacer()
                Button("›") { board.shiftCalendar(1) }
                    .font(Ink.title)
                    .buttonStyle(.plain)
            }

            Button(board.calendarSpan == nil ? "showing all dates" : "clear filter") {
                board.calendarSpan = board.calendarSpan == nil ? .day : nil
                board.poke()
            }
            .font(Ink.small)
            .buttonStyle(.plain)

            Divider()

            Text("view")
                .font(Ink.small)
                .foregroundStyle(Ink.mute)

            VStack(alignment: .leading, spacing: 6) {
                modeBtn("layout", .layout, "where you dragged them")
                modeBtn("time", .timeline, "timeline by day")
                modeBtn("week", .week, "this week's cards")
                modeBtn("month", .month, "this month's cards")
                modeBtn("year", .year, "this year's cards")
            }

            Spacer()
        }
        .padding(16)
        .frame(width: 280)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(Ink.raised)
        .overlay(alignment: .leading) {
            Rectangle().fill(Ink.line).frame(width: 1)
        }
    }

    private func spanBtn(_ label: String, _ span: DateSpan) -> some View {
        let on = board.calendarSpan == span
        return Button(label) {
            board.calendarSpan = span
            board.poke()
        }
        .font(Ink.mono)
        .frame(maxWidth: .infinity, minHeight: 40)
        .background(on ? Ink.accent : Ink.surface)
        .foregroundStyle(on ? Ink.accentInk : Ink.ink)
        .overlay(Rectangle().strokeBorder(on ? Ink.accent : Ink.line, lineWidth: 1))
        .buttonStyle(.plain)
    }

    private func modeBtn(_ title: String, _ mode: BoardViewMode, _ hint: String) -> some View {
        let on = board.viewMode == mode
        return Button {
            board.viewMode = mode
            board.poke()
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(Ink.body)
                Text(hint).font(Ink.small).foregroundStyle(on ? Ink.accentInk.opacity(0.7) : Ink.mute)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(8)
            .background(on ? Ink.accent : Ink.surface)
            .foregroundStyle(on ? Ink.accentInk : Ink.ink)
            .overlay(Rectangle().strokeBorder(on ? Ink.accent : Ink.line, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }
}
