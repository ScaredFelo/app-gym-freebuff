import Foundation

/// Compara el trabajo muscular de dos sesiones. Un grupo cuenta como
/// solapamiento cuando es principal en una de ellas y aparece (principal o
/// secundario) en la otra.
enum MuscleOverlapAnalyzer {
    static func sharedMuscles(between first: GeneratedSession, and second: GeneratedSession) -> [String] {
        let firstPrimary: Set<String> = Set(first.primaryMuscleNames)
        let firstAll: Set<String> = Set(first.muscleNames)
        let secondPrimary: Set<String> = Set(second.primaryMuscleNames)
        let secondAll: Set<String> = Set(second.muscleNames)

        let shared: Set<String> = firstPrimary
            .intersection(secondAll)
            .union(secondPrimary.intersection(firstAll))

        return shared.sorted()
    }

    static func displayNames(for rawValues: [String]) -> [String] {
        return rawValues.compactMap { (raw: String) -> String? in
            return MuscleGroup.mappedValue(for: raw)?.shortName
        }
    }
}

/// Detecta solapamientos musculares entre sesiones consecutivas.
///
/// Limitación explícita: la semana generada no asigna días del calendario, por
/// lo que el análisis compara el orden de las sesiones del split. No se usan
/// tiempos fisiológicos de recuperación ni umbrales numéricos inventados.
enum RecoveryAnalysisService {
    static func analyze(sessions: [GeneratedSession]) -> [RoutineNotice] {
        guard sessions.count > 1 else { return [] }

        var notices: [RoutineNotice] = []

        for index in 0..<(sessions.count - 1) {
            let first: GeneratedSession = sessions[index]
            let second: GeneratedSession = sessions[index + 1]

            let shared: [String] = MuscleOverlapAnalyzer.sharedMuscles(between: first, and: second)
            guard !shared.isEmpty else { continue }

            let muscles: [String] = MuscleOverlapAnalyzer.displayNames(for: shared)
            let muscleText: String = muscles.isEmpty
                ? shared.joined(separator: ", ")
                : muscles.joined(separator: ", ")

            notices.append(
                RoutineNotice.muscleRecovery(
                    involvedDays: ["SESIÓN \(index + 1)", "SESIÓN \(index + 2)"],
                    affectedRoutines: [first.name, second.name],
                    muscleGroups: muscles,
                    reason: "«\(first.name)» y «\(second.name)» son sesiones consecutivas y comparten \(muscleText). La estructura no asigna días de descanso entre ellas; la app no evalúa tiempos de recuperación."
                )
            )
        }

        return notices
    }

    /// Variante para el constructor asistido: compara sesiones que ocupan días
    /// consecutivos del calendario. No se inventan periodos de recuperación ni
    /// se afirma que un músculo no se haya recuperado.
    static func analyze(sessions: [GeneratedSession], weekdays: [Int]) -> [RoutineNotice] {
        guard sessions.count == weekdays.count, sessions.count > 1 else { return [] }

        var notices: [RoutineNotice] = []

        for firstIndex in 0..<(sessions.count - 1) {
            let secondIndex: Int = firstIndex + 1
            guard abs(weekdays[secondIndex] - weekdays[firstIndex]) == 1 else { continue }

            let first: GeneratedSession = sessions[firstIndex]
            let second: GeneratedSession = sessions[secondIndex]
            let shared: [String] = MuscleOverlapAnalyzer.sharedMuscles(between: first, and: second)
            guard !shared.isEmpty else { continue }

            let muscles: [String] = MuscleOverlapAnalyzer.displayNames(for: shared)
            let muscleText: String = muscles.isEmpty
                ? shared.joined(separator: ", ")
                : muscles.joined(separator: ", ")
            let firstDay: String = AssistedWeekday.from(index: weekdays[firstIndex])?.displayName ?? "DÍA \(weekdays[firstIndex] + 1)"
            let secondDay: String = AssistedWeekday.from(index: weekdays[secondIndex])?.displayName ?? "DÍA \(weekdays[secondIndex] + 1)"

            notices.append(
                RoutineNotice.muscleRecovery(
                    involvedDays: [firstDay, secondDay],
                    affectedRoutines: [first.name, second.name],
                    muscleGroups: muscles,
                    reason: "«\(first.name)» (\(firstDay)) y «\(second.name)» (\(secondDay)) son días consecutivos y comparten \(muscleText). Se describe la coincidencia de grupos; la app no evalúa tiempos fisiológicos de recuperación."
                )
            )
        }

        return notices
    }
}
