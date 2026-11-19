import Foundation

// MARK: - Snapshot compartido

/// Estado que la app escribe y que la extensión de widgets lee para pintar la
/// racha semanal y el objetivo configurado.
public struct WorkoutStreakSnapshot: Codable, Equatable, Sendable {
    /// Semanas consecutivas alcanzando `weeklyGoal`. La semana en curso no
    /// rompe la racha mientras siga en marcha.
    public var weekStreak: Int
    /// Días distintos entrenados en la semana actual (lunes a domingo).
    public var currentWeekWorkouts: Int
    /// Objetivo de días por semana vigente.
    public var weeklyGoal: Int
    /// 7 posiciones para `["L", "M", "X", "J", "V", "S", "D"]`.
    public var trainedWeekdays: [Bool]
    public var lastUpdated: Date

    public static let weekdaySymbols: [String] = ["L", "M", "X", "J", "V", "S", "D"]

    public init(
        weekStreak: Int = 0,
        currentWeekWorkouts: Int = 0,
        weeklyGoal: Int = WidgetStreakStore.defaultWeeklyGoal,
        trainedWeekdays: [Bool] = Array(repeating: false, count: 7),
        lastUpdated: Date = Date()
    ) {
        self.weekStreak = max(0, weekStreak)
        self.currentWeekWorkouts = max(0, currentWeekWorkouts)
        self.weeklyGoal = WidgetStreakStore.clampedWeeklyGoal(weeklyGoal)
        self.trainedWeekdays = WorkoutStreakSnapshot.normalizedWeekdays(trainedWeekdays)
        self.lastUpdated = lastUpdated
    }

    /// Garantiza siempre 7 posiciones, aunque el JSON guardado venga incompleto.
    private static func normalizedWeekdays(_ weekdays: [Bool]) -> [Bool] {
        var normalized: [Bool] = Array(repeating: false, count: 7)
        var index: Int = 0
        while index < 7 && index < weekdays.count {
            normalized[index] = weekdays[index]
            index += 1
        }
        return normalized
    }

    /// Días de esta semana, siempre con 7 posiciones.
    public var weekdays: [Bool] {
        return WorkoutStreakSnapshot.normalizedWeekdays(trainedWeekdays)
    }

    /// Progreso del objetivo semanal en el rango `0...1`.
    public var goalProgress: Double {
        guard weeklyGoal > 0 else { return 0.0 }
        let value: Double = Double(currentWeekWorkouts) / Double(weeklyGoal)
        return min(max(value, 0.0), 1.0)
    }

    /// Datos de muestra mientras el widget no tiene nada guardado.
    public static var placeholder: WorkoutStreakSnapshot {
        return WorkoutStreakSnapshot(
            weekStreak: 3,
            currentWeekWorkouts: 2,
            weeklyGoal: WidgetStreakStore.storedWeeklyGoal(),
            trainedWeekdays: [true, false, true, false, false, false, false],
            lastUpdated: Date()
        )
    }
}

// MARK: - Almacén compartido

/// Persistencia del snapshot de racha entre la app y la extensión de widgets.
///
/// Se usa el App Group `group.appgym.shared` y, como respaldo automático, el
/// `UserDefaults.standard` de cada proceso. Así funciona tanto con firma y
/// entitlement de App Group completos como en instalaciones con Sideloadly,
/// donde el grupo no llega a registrarse.
public enum WidgetStreakStore {
    private static let appGroupIdentifier: String = "group.appgym.shared"
    private static let snapshotKey: String = "workoutStreakSnapshot"
    private static let weeklyGoalDefaultsKey: String = "weeklyWorkoutGoal"
    public static let defaultWeeklyGoal: Int = 4
    private static let weeklyGoalRange: ClosedRange<Int> = 1...7

    /// Limita el objetivo al rango configurable de 1 a 7 días por semana.
    static func clampedWeeklyGoal(_ value: Int) -> Int {
        return min(max(value, weeklyGoalRange.lowerBound), weeklyGoalRange.upperBound)
    }

    /// `UserDefaults` del App Group, o `nil` si el grupo no está disponible.
    private static var sharedDefaults: UserDefaults? {
        return UserDefaults(suiteName: appGroupIdentifier)
    }

    /// Objetivo vigente según los ajustes persistidos por la app.
    static func storedWeeklyGoal() -> Int {
        if let shared: UserDefaults = sharedDefaults,
           shared.object(forKey: weeklyGoalDefaultsKey) != nil {
            return clampedWeeklyGoal(shared.integer(forKey: weeklyGoalDefaultsKey))
        }
        guard UserDefaults.standard.object(forKey: weeklyGoalDefaultsKey) != nil else {
            return defaultWeeklyGoal
        }
        return clampedWeeklyGoal(UserDefaults.standard.integer(forKey: weeklyGoalDefaultsKey))
    }

    /// Guarda el snapshot en el App Group y, además, en `standard` como respaldo.
    public static func save(_ snapshot: WorkoutStreakSnapshot) {
        guard let data: Data = try? JSONEncoder().encode(snapshot) else { return }

        if let shared: UserDefaults = sharedDefaults {
            shared.set(data, forKey: snapshotKey)
        }
        UserDefaults.standard.set(data, forKey: snapshotKey)
    }

    /// Lee el snapshot desde el App Group con respaldo a `standard`.
    public static func load() -> WorkoutStreakSnapshot {
        if let shared: UserDefaults = sharedDefaults,
           let data: Data = shared.data(forKey: snapshotKey),
           let decoded: WorkoutStreakSnapshot = try? JSONDecoder().decode(WorkoutStreakSnapshot.self, from: data) {
            return renormalized(decoded)
        }

        if let data: Data = UserDefaults.standard.data(forKey: snapshotKey),
           let decoded: WorkoutStreakSnapshot = try? JSONDecoder().decode(WorkoutStreakSnapshot.self, from: data) {
            return renormalized(decoded)
        }

        return WorkoutStreakSnapshot(weeklyGoal: storedWeeklyGoal())
    }

    /// Snapshot listo para pintar ahora mismo. Si la app no se ha abierto
    /// desde una semana anterior, la semana en curso aparece vacía; tras dos
    /// o más semanas sin uso la racha ya está rota, porque la semana completa
    /// intermedia no llegó al objetivo.
    public static func currentSnapshot(now: Date = Date()) -> WorkoutStreakSnapshot {
        let stored: WorkoutStreakSnapshot = load()
        let calendar: Calendar = mondayCalendar()
        let storedWeekStart: Date = startOfWeek(for: stored.lastUpdated, calendar: calendar)
        let currentWeekStart: Date = startOfWeek(for: now, calendar: calendar)
        guard currentWeekStart > storedWeekStart else { return stored }

        var weeksAhead: Int = 0
        var cursor: Date = storedWeekStart
        while cursor < currentWeekStart && weeksAhead < 3 {
            guard let next: Date = calendar.date(byAdding: .day, value: 7, to: cursor) else { break }
            cursor = next
            weeksAhead += 1
        }

        return WorkoutStreakSnapshot(
            weekStreak: weeksAhead >= 2 ? 0 : stored.weekStreak,
            currentWeekWorkouts: 0,
            weeklyGoal: stored.weeklyGoal,
            trainedWeekdays: Array(repeating: false, count: 7),
            lastUpdated: stored.lastUpdated
        )
    }

    // MARK: - Cálculo

    /// Calcula la racha, el objetivo y los días entrenados de la semana actual
    /// a partir de las fechas de entrenamiento (una por sesión finalizada).
    ///
    /// - La semana actual no rompe la racha hasta que termina: si todavía no
    ///   llega al objetivo, se conserva la racha acumulada hasta la semana
    ///   pasada.
    public static func makeSnapshot(
        workoutDates: [Date],
        weeklyGoal: Int,
        now: Date = Date()
    ) -> WorkoutStreakSnapshot {
        let goal: Int = clampedWeeklyGoal(weeklyGoal)
        let calendar: Calendar = mondayCalendar()
        let currentWeekStart: Date = startOfWeek(for: now, calendar: calendar)

        let days: [Date] = workoutDates.map { (date: Date) -> Date in
            return calendar.startOfDay(for: date)
        }

        let currentWeekDays: Set<Date> = distinctDays(
            inWeekStarting: currentWeekStart,
            among: days,
            calendar: calendar
        )

        var trainedWeekdays: [Bool] = Array(repeating: false, count: 7)
        for day in currentWeekDays {
            let index: Int = weekdayIndex(for: day, calendar: calendar)
            if index >= 0 && index < 7 {
                trainedWeekdays[index] = true
            }
        }

        // La semana en curso suma a la racha solo cuando ya cumple el objetivo.
        var streak: Int = currentWeekDays.count >= goal ? 1 : 0
        var cursor: Date = calendar.date(byAdding: .day, value: -7, to: currentWeekStart) ?? currentWeekStart
        var inspectedWeeks: Int = 0

        while inspectedWeeks < 520 {
            inspectedWeeks += 1

            let pastWeekDays: Set<Date> = distinctDays(
                inWeekStarting: cursor,
                among: days,
                calendar: calendar
            )

            if pastWeekDays.count < goal {
                break
            }

            streak += 1

            guard let previousWeek: Date = calendar.date(byAdding: .day, value: -7, to: cursor) else {
                break
            }
            cursor = previousWeek
        }

        return WorkoutStreakSnapshot(
            weekStreak: streak,
            currentWeekWorkouts: currentWeekDays.count,
            weeklyGoal: goal,
            trainedWeekdays: trainedWeekdays,
            lastUpdated: now
        )
    }

    /// Calendario con la semana empezando en lunes.
    private static func mondayCalendar() -> Calendar {
        var calendar: Calendar = Calendar.current
        calendar.firstWeekday = 2
        calendar.minimumDaysInFirstWeek = 4
        return calendar
    }

    /// Lunes a las 00:00 de la semana a la que pertenece `date`.
    private static func startOfWeek(for date: Date, calendar: Calendar) -> Date {
        let startOfDay: Date = calendar.startOfDay(for: date)
        let index: Int = weekdayIndex(for: startOfDay, calendar: calendar)
        return calendar.date(byAdding: .day, value: -index, to: startOfDay) ?? startOfDay
    }

    /// Índice `0...6` con lunes = 0 y domingo = 6.
    private static func weekdayIndex(for day: Date, calendar: Calendar) -> Int {
        let weekday: Int = calendar.component(.weekday, from: day)
        return (weekday + 5) % 7
    }

    /// Días distintos (a medianoche) dentro de la semana que empieza en `weekStart`.
    private static func distinctDays(
        inWeekStarting weekStart: Date,
        among days: [Date],
        calendar: Calendar
    ) -> Set<Date> {
        guard let weekEnd: Date = calendar.date(byAdding: .day, value: 7, to: weekStart) else {
            return []
        }

        var result: Set<Date> = Set<Date>()
        for day in days {
            if day >= weekStart && day < weekEnd {
                result.insert(day)
            }
        }
        return result
    }

    private static func renormalized(_ snapshot: WorkoutStreakSnapshot) -> WorkoutStreakSnapshot {
        return WorkoutStreakSnapshot(
            weekStreak: snapshot.weekStreak,
            currentWeekWorkouts: snapshot.currentWeekWorkouts,
            weeklyGoal: snapshot.weeklyGoal,
            trainedWeekdays: snapshot.trainedWeekdays,
            lastUpdated: snapshot.lastUpdated
        )
    }
}
