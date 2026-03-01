import SwiftUI

struct CalendarView: View {
    @Environment(DigestViewModel.self) private var viewModel

    @State private var displayedMonth: Date = .now

    private let calendar = Calendar.current
    private let daySymbols = Calendar.current.shortWeekdaySymbols

    var body: some View {
        VStack(spacing: 8) {
            // Month navigation
            HStack {
                Button {
                    moveMonth(by: -1)
                } label: {
                    Image(systemName: "chevron.left")
                }
                .buttonStyle(.plain)

                Spacer()

                Text(monthYearString)
                    .font(.headline)

                Spacer()

                Button {
                    moveMonth(by: 1)
                } label: {
                    Image(systemName: "chevron.right")
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal)

            // Day headers
            LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 7), spacing: 4) {
                ForEach(daySymbols, id: \.self) { symbol in
                    Text(symbol)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                }

                // Day cells
                ForEach(Array(daysInMonth.enumerated()), id: \.offset) { _, day in
                    if let day {
                        DayCell(
                            date: day,
                            isSelected: calendar.isDate(day, inSameDayAs: viewModel.selectedDate),
                            isToday: calendar.isDateInToday(day),
                            hasContent: viewModel.dateHasContent(day)
                        )
                        .onTapGesture {
                            viewModel.selectDate(day)
                        }
                    } else {
                        Color.clear
                            .frame(height: 28)
                    }
                }
            }
            .padding(.horizontal, 8)
        }
        .padding(.vertical, 8)
    }

    private static let monthYearFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "MMMM yyyy"
        return f
    }()

    private var monthYearString: String {
        Self.monthYearFormatter.string(from: displayedMonth)
    }

    private var daysInMonth: [Date?] {
        let comps = calendar.dateComponents([.year, .month], from: displayedMonth)
        guard let firstOfMonth = calendar.date(from: comps),
              let range = calendar.range(of: .day, in: .month, for: firstOfMonth) else {
            return []
        }

        let firstWeekday = calendar.component(.weekday, from: firstOfMonth)
        let leadingEmpty = (firstWeekday - calendar.firstWeekday + 7) % 7

        var days: [Date?] = Array(repeating: nil, count: leadingEmpty)
        for day in range {
            var dc = comps
            dc.day = day
            days.append(calendar.date(from: dc))
        }
        return days
    }

    private func moveMonth(by value: Int) {
        if let newDate = calendar.date(byAdding: .month, value: value, to: displayedMonth) {
            displayedMonth = newDate
        }
    }
}

private struct DayCell: View {
    let date: Date
    let isSelected: Bool
    let isToday: Bool
    let hasContent: Bool

    var body: some View {
        VStack(spacing: 2) {
            Text("\(Calendar.current.component(.day, from: date))")
                .font(.system(size: 12, weight: isToday ? .bold : .regular))
                .foregroundStyle(isSelected ? .white : isToday ? .accentColor : .primary)
                .frame(width: 28, height: 22)
                .background {
                    if isSelected {
                        RoundedRectangle(cornerRadius: 6)
                            .fill(Color.accentColor)
                    }
                }

            Circle()
                .fill(hasContent ? Color.accentColor : Color.clear)
                .frame(width: 4, height: 4)
        }
        .frame(height: 28)
    }
}
