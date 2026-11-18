import Foundation
import SwiftUI
import SwiftData

// MARK: - Shared calendar configuration

private enum MonthlyCalendarMetrics {
    static let locale: Locale = Locale(identifier: "es_ES")
    static let weekdaySymbols: [String] = ["L", "M", "X", "J", "V", "S", "D"]
    static let totalCells: Int = 42
    static let rowCount: Int = 6
    static let cellHeight: CGFloat = 36.0
    static let gridSpacing: CGFloat = 3.0

    static var gridHeight: CGFloat {
        let rows: CGFloat = CGFloat(rowCount)
        let spacings: CGFloat = CGFloat(rowCount - 1)
        return (rows * cellHeight) + (spacings * gridSpacing)
    }

    static var indicatorSize: CGFloat {
        return cellHeight - 4.0
    }

    static var calendar: Calendar {
        var calendar: Calendar = Calendar(identifier: .gregorian)
        calendar.locale = locale
        calendar.firstWeekday = 2
        calendar.timeZone = .current
        return calendar
    }

    static func monthStart(offset: Int, from date: Date = Date()) -> Date {
        let calendar: Calendar = self.calendar
        let components: DateComponents = calendar.dateComponents([.year, .month], from: date)
        let currentStart: Date = calendar.date(from: components) ?? date
        return calendar.date(byAdding: .month, value: offset, to: currentStart) ?? currentStart
    }
}

// MARK: - Paginated monthly calendar

/// Calendario mensual paginado horizontalmente. El mes actual es siempre la
/// página inicial (`monthOffset == 0`).
struct MonthlyCalendarPagerView: View {
    let sessions: [WorkoutSession]
    let onSelectDate: (Date) -> Void

    @State private var monthOffset: Int = 0

    private static let monthOffsetRange: ClosedRange<Int> = -120...120

    /// Días con entrenamiento, normalizados al inicio del día para comparar
    /// fechas de forma segura e independiente de la hora.
    private var workoutDays: Set<Date> {
        let calendar: Calendar = MonthlyCalendarMetrics.calendar
        var days: Set<Date> = Set<Date>()

        for session in sessions {
            let day: Date = calendar.startOfDay(for: session.startDate)
            days.insert(day)
        }

        return days
    }

    var body: some View {
        let days: Set<Date> = workoutDays
        let offsets: [Int] = Array(Self.monthOffsetRange)
        let columns: [GridItem] = Array(
            repeating: GridItem(.flexible(), spacing: MonthlyCalendarMetrics.gridSpacing),
            count: 7
        )

        return VStack(alignment: .leading, spacing: 10.0) {
            monthHeader
            weekdayHeader(columns: columns)

            TabView(selection: $monthOffset) {
                ForEach(offsets, id: \.self) { (offset: Int) in
                    MonthGridPageView(
                        monthOffset: offset,
                        workoutDays: days,
                        onSelectDate: onSelectDate
                    )
                    .tag(offset)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .frame(height: MonthlyCalendarMetrics.gridHeight)
        }
    }

    // MARK: Month header

    private var monthHeader: some View {
        HStack(spacing: 6.0) {
            arrowButton(systemName: "chevron.left") {
                shiftMonth(-1)
            }
            .accessibilityLabel("Mes anterior")

            Text(monthTitle)
                .font(EndfieldFont.mono(12.0, weight: .heavy))
                .tracking(1.0)
                .foregroundStyle(EndfieldPalette.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .fixedSize(horizontal: false, vertical: true)

            arrowButton(systemName: "chevron.right") {
                shiftMonth(1)
            }
            .accessibilityLabel("Mes siguiente")

            Spacer(minLength: 4.0)

            todayButton
        }
    }

    private func arrowButton(systemName: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(EndfieldFont.mono(9.0, weight: .bold))
        }
        .buttonStyle(EndfieldSquareButtonStyle(tint: EndfieldPalette.textSecondary, size: 24.0))
    }

    private var todayButton: some View {
        Button {
            guard monthOffset != 0 else { return }
            withAnimation(.easeInOut(duration: 0.25)) {
                monthOffset = 0
            }
        } label: {
            Text("HOY")
                .font(EndfieldFont.mono(9.0, weight: .bold))
                .tracking(1.2)
        }
        .buttonStyle(EndfieldSecondaryButtonStyle(fullWidth: false, compact: true, tint: EndfieldPalette.accentYellow))
        .opacity(monthOffset == 0 ? 0.4 : 1.0)
        .accessibilityLabel("Volver al mes actual")
    }

    private func shiftMonth(_ delta: Int) {
        let next: Int = monthOffset + delta
        guard next >= Self.monthOffsetRange.lowerBound, next <= Self.monthOffsetRange.upperBound else { return }

        withAnimation(.easeInOut(duration: 0.2)) {
            monthOffset = next
        }
    }

    private var monthTitle: String {
        let date: Date = MonthlyCalendarMetrics.monthStart(offset: monthOffset)
        let formatter: DateFormatter = DateFormatter()
        formatter.calendar = MonthlyCalendarMetrics.calendar
        formatter.locale = MonthlyCalendarMetrics.locale
        formatter.timeZone = .current

        formatter.dateFormat = "LLLL"
        let month: String = formatter.string(from: date).uppercased(with: MonthlyCalendarMetrics.locale)

        formatter.dateFormat = "yyyy"
        let year: String = formatter.string(from: date)

        return "\(month) // \(year)"
    }

    // MARK: Weekday header

    private func weekdayHeader(columns: [GridItem]) -> some View {
        return LazyVGrid(columns: columns, spacing: MonthlyCalendarMetrics.gridSpacing) {
            ForEach(MonthlyCalendarMetrics.weekdaySymbols.indices, id: \.self) { (index: Int) in
                Text(MonthlyCalendarMetrics.weekdaySymbols[index])
                    .font(EndfieldFont.label(8.0))
                    .tracking(0.6)
                    .foregroundStyle(EndfieldPalette.textSecondary)
                    .frame(maxWidth: .infinity)
            }
        }
    }
}

// MARK: - One month page

/// Página de un mes concreto dentro del paginador. Siempre renderiza 42 celdas
/// para que la altura sea idéntica en todos los meses.
struct MonthGridPageView: View {
    let monthOffset: Int
    let workoutDays: Set<Date>
    let onSelectDate: (Date) -> Void

    var body: some View {
        let calendar: Calendar = MonthlyCalendarMetrics.calendar
        let dates: [Date?] = cellDates(using: calendar)
        let columns: [GridItem] = Array(
            repeating: GridItem(.flexible(), spacing: MonthlyCalendarMetrics.gridSpacing),
            count: 7
        )

        return LazyVGrid(columns: columns, spacing: MonthlyCalendarMetrics.gridSpacing) {
            ForEach(dates.indices, id: \.self) { (index: Int) in
                if let date: Date = dates[index] {
                    Button {
                        onSelectDate(date)
                    } label: {
                        CalendarDayCellView(
                            dayNumber: calendar.component(.day, from: date),
                            isToday: calendar.isDateInToday(date),
                            hasWorkout: workoutDays.contains(calendar.startOfDay(for: date))
                        )
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Día \(calendar.component(.day, from: date))")
                } else {
                    Color.clear
                        .frame(maxWidth: .infinity)
                        .frame(height: MonthlyCalendarMetrics.cellHeight)
                }
            }
        }
        .frame(height: MonthlyCalendarMetrics.gridHeight)
    }

    private func cellDates(using calendar: Calendar) -> [Date?] {
        let startOfMonth: Date = MonthlyCalendarMetrics.monthStart(offset: monthOffset)
        let dayCount: Int = calendar.range(of: .day, in: .month, for: startOfMonth)?.count ?? 30
        let firstWeekday: Int = calendar.component(.weekday, from: startOfMonth)
        let leadingEmptyDays: Int = (firstWeekday + 5) % 7

        var cells: [Date?] = Array(repeating: nil, count: MonthlyCalendarMetrics.totalCells)

        for dayIndex in 0..<dayCount {
            let cellIndex: Int = leadingEmptyDays + dayIndex
            guard cellIndex >= 0, cellIndex < cells.count else { continue }

            let date: Date = calendar.date(byAdding: .day, value: dayIndex, to: startOfMonth) ?? startOfMonth
            cells[cellIndex] = date
        }

        return cells
    }
}

// MARK: - Day cell

struct CalendarDayCellView: View {
    let dayNumber: Int
    let isToday: Bool
    let hasWorkout: Bool

    var body: some View {
        ZStack {
            Rectangle()
                .fill(cellFill)

            Rectangle()
                .stroke(borderColor, lineWidth: isToday ? 1.5 : 1.0)

            if hasWorkout {
                workoutCornerMark
            }

            Text(String(format: "%02d", dayNumber))
                .font(EndfieldFont.mono(11.0, weight: isToday ? .heavy : .medium))
                .monospacedDigit()
                .foregroundStyle(dayTextColor)
        }
        .frame(maxWidth: .infinity)
        .frame(height: MonthlyCalendarMetrics.cellHeight)
        .contentShape(Rectangle())
    }

    private var cellFill: Color {
        if hasWorkout {
            return EndfieldPalette.accentYellow.opacity(0.22)
        }
        return EndfieldPalette.bgElevated.opacity(0.30)
    }

    private var borderColor: Color {
        if isToday {
            return EndfieldPalette.accentYellow
        }
        return EndfieldPalette.borderSubtle
    }

    private var dayTextColor: Color {
        if isToday {
            return EndfieldPalette.accentYellow
        }
        if hasWorkout {
            return EndfieldPalette.textPrimary
        }
        return EndfieldPalette.textSecondary
    }

    private var workoutCornerMark: some View {
        VStack(spacing: 0.0) {
            HStack(spacing: 0.0) {
                Spacer(minLength: 0.0)
                Rectangle()
                    .fill(EndfieldPalette.accentYellow)
                    .frame(width: 5.0, height: 5.0)
            }
            Spacer(minLength: 0.0)
        }
        .padding(2.0)
        .allowsHitTesting(false)
    }
}
