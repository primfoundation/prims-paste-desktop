import PrimsPasteCore
import SwiftUI

struct CalendarDrawer: View {
    @ObservedObject var board: Board

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Calendar")
                    .font(Ink.serif)
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
                    .font(Ink.serif)
                    .buttonStyle(.plain)
                Spacer()
                Text(board.calendarLabel)
                    .font(Ink.mono)
                Spacer()
                Button("›") { board.shiftCalendar(1) }
                    .font(Ink.serif)
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
        .background(Ink.bar)
        .overlay(Rectangle().strokeBorder(Color.black.opacity(0.08), lineWidth: 1))
    }

    private func spanBtn(_ label: String, _ span: DateSpan) -> some View {
        let on = board.calendarSpan == span
        return Button(label) {
            board.calendarSpan = span
            board.poke()
        }
        .font(.system(size: 16, weight: .semibold, design: .monospaced))
        .frame(maxWidth: .infinity, minHeight: 40)
        .background(on ? Ink.tabOn : Color.black.opacity(0.06))
        .foregroundStyle(on ? Color.white : Ink.ink)
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
                Text(hint).font(Ink.small).foregroundStyle(on ? Color.white.opacity(0.8) : Ink.mute)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(8)
            .background(on ? Ink.tabOn : Color.black.opacity(0.04))
            .foregroundStyle(on ? Color.white : Ink.ink)
        }
        .buttonStyle(.plain)
    }
}
