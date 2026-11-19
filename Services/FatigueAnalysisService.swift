import Foundation

/// Describe la distribución semanal de trabajo muscular.
///
/// **No calcula fatiga fisiológica ni aplica umbrales.** Las fuentes no definen
/// tiempos de recuperación, porcentajes de fatiga ni límites de volumen, así que
/// este servicio solo expone datos verificables:
/// - apariciones de cada grupo como músculo principal,
/// - grupos presentes en más de una sesión (repetición),
/// - pares de sesiones consecutivas que comparten trabajo muscular.
///
/// Los avisos son informativos y nunca bloquean la confirmación.
enum FatigueAnalysisService {
    static func analyze(sessions: [GeneratedSession]) -> [RoutineNotice] {
        guard sessions.count > 1 else { return [] }

        var notices: [RoutineNotice] = []
        let sessionNames: [String] = sessions.map { (session: GeneratedSession) -> String in
            return session.name
        }

        // 1. Recuento descriptivo de apariciones como músculo principal.
        var occurrences: [String: [Int]] = [:]
        for session in sessions {
            for muscle in session.primaryMuscleNames {
                occurrences[muscle, default: []].append(session.index)
            }
        }

        let orderedKeys: [String] = occurrences.keys.sorted { (first: String, second: String) -> Bool in
            let firstCount: Int = occurrences[first]?.count ?? 0
            let secondCount: Int = occurrences[second]?.count ?? 0
            if firstCount != secondCount {
                return firstCount > secondCount
            }
            return first < second
        }

        let frequencies: [String] = orderedKeys.map { (key: String) -> String in
            let name: String = MuscleGroup.mappedValue(for: key)?.shortName ?? key
            let count: Int = occurrences[key]?.count ?? 0
            return "\(name) \(count)"
        }

        let repeatedNames: [String] = orderedKeys.compactMap { (key: String) -> String? in
            guard let count: Int = occurrences[key]?.count, count > 1 else { return nil }
            return MuscleGroup.mappedValue(for: key)?.shortName ?? key
        }

        let repeatedText: String = repeatedNames.isEmpty
            ? "ninguno"
            : repeatedNames.joined(separator: ", ")

        notices.append(
            RoutineNotice.fatigue(
                involvedDays: sessions.map { (session: GeneratedSession) -> String in
                    return "SESIÓN \(session.index + 1)"
                },
                affectedRoutines: sessionNames,
                reason: "Recuento de apariciones como músculo principal: \(frequencies.joined(separator: ", ")). Grupos presentes en más de una sesión: \(repeatedText). Son recuentos de la estructura semanal; no estiman fatiga fisiológica ni tiempos de recuperación.",
                recommendation: "Indicador descriptivo: úsalo para comparar distribuciones. La decisión sobre la semana sigue siendo tuya."
            )
        )

        // 2. Solapamiento entre cada par de sesiones consecutivas, sin umbral.
        var overlapDetails: [String] = []
        var overlapDays: [String] = []
        var overlapRoutines: [String] = []

        if sessions.count > 1 {
            for index in 0..<(sessions.count - 1) {
                let shared: [String] = MuscleOverlapAnalyzer.sharedMuscles(
                    between: sessions[index],
                    and: sessions[index + 1]
                )
                guard !shared.isEmpty else { continue }

                let display: [String] = MuscleOverlapAnalyzer.displayNames(for: shared)
                let muscleText: String = display.isEmpty
                    ? shared.joined(separator: ", ")
                    : display.joined(separator: ", ")

                overlapDetails.append("SESIÓN \(index + 1) (\(sessions[index].name)) con SESIÓN \(index + 2) (\(sessions[index + 1].name)): \(muscleText)")
                overlapDays.append("SESIÓN \(index + 1) → \(index + 2)")

                for name in [sessions[index].name, sessions[index + 1].name] where !overlapRoutines.contains(name) {
                    overlapRoutines.append(name)
                }
            }
        }

        if !overlapDetails.isEmpty {
            notices.append(
                RoutineNotice.fatigue(
                    involvedDays: overlapDays,
                    affectedRoutines: overlapRoutines,
                    reason: "Solapamiento de grupos entre sesiones consecutivas: \(overlapDetails.joined(separator: "; ")). Se describe la coincidencia de grupos, no un tiempo de recuperación.",
                    recommendation: "Indicador descriptivo: la estructura no asigna días de descanso concretos entre sesiones."
                )
            )
        }

        return notices
    }

    /// Variante semanal con días reales. Describe frecuencias de músculos
    /// principales y secundarios y todos los solapamientos entre pares de
    /// sesiones, incluidos los no consecutivos. No calcula fatiga fisiológica.
    static func analyze(sessions: [GeneratedSession], weekdays: [Int]) -> [RoutineNotice] {
        guard sessions.count == weekdays.count, !sessions.isEmpty else { return [] }

        var notices: [RoutineNotice] = []
        var primaryCounts: [String: Int] = [:]
        var secondaryCounts: [String: Int] = [:]

        for session in sessions {
            for muscle in session.primaryMuscleNames {
                primaryCounts[muscle, default: 0] += 1
            }
            for muscle in secondaryMuscleNames(session) {
                secondaryCounts[muscle, default: 0] += 1
            }
        }

        let primaryText: String = frequencyText(primaryCounts)
        let secondaryText: String = frequencyText(secondaryCounts)
        let repeated: [String] = primaryCounts.keys
            .filter { (raw: String) -> Bool in (primaryCounts[raw] ?? 0) > 1 }
            .sorted()
            .map { (raw: String) -> String in MuscleGroup.mappedValue(for: raw)?.shortName ?? raw }

        let dayLabels: [String] = weekdays.map { (index: Int) -> String in
            return AssistedWeekday.from(index: index)?.displayName ?? "DÍA \(index + 1)"
        }

        notices.append(
            RoutineNotice.fatigue(
                involvedDays: dayLabels,
                affectedRoutines: sessions.map { (session: GeneratedSession) -> String in session.name },
                reason: "Frecuencia como músculo principal: \(primaryText). Frecuencia como músculo secundario: \(secondaryText). Grupos principales repetidos: \(repeated.isEmpty ? "ninguno" : repeated.joined(separator: ", ")). Son recuentos descriptivos de la semana; no estiman fatiga fisiológica.",
                recommendation: "Indicador descriptivo: úsalo para comparar distribuciones. La decisión sobre la semana sigue siendo tuya."
            )
        )

        var overlapDetails: [String] = []
        var overlapDays: [String] = []
        var overlapRoutines: [String] = []

        if sessions.count > 1 {
            for firstIndex in 0..<(sessions.count - 1) {
                for secondIndex in (firstIndex + 1)..<sessions.count {
                    let shared: [String] = MuscleOverlapAnalyzer.sharedMuscles(
                        between: sessions[firstIndex],
                        and: sessions[secondIndex]
                    )
                    guard !shared.isEmpty else { continue }

                    let display: [String] = MuscleOverlapAnalyzer.displayNames(for: shared)
                    let muscleText: String = display.isEmpty
                        ? shared.joined(separator: ", ")
                        : display.joined(separator: ", ")
                    let firstDay: String = dayLabels[firstIndex]
                    let secondDay: String = dayLabels[secondIndex]
                    let gap: Int = abs(weekdays[secondIndex] - weekdays[firstIndex])
                    let gapText: String = gap == 1 ? "días consecutivos" : "separados por \(gap - 1) día(s) entre medias"

                    overlapDetails.append("\(firstDay) (\(sessions[firstIndex].name)) con \(secondDay) (\(sessions[secondIndex].name)): \(muscleText), \(gapText)")
                    overlapDays.append("\(firstDay) → \(secondDay)")

                    for name in [sessions[firstIndex].name, sessions[secondIndex].name] where !overlapRoutines.contains(name) {
                        overlapRoutines.append(name)
                    }
                }
            }
        }

        if !overlapDetails.isEmpty {
            notices.append(
                RoutineNotice.fatigue(
                    involvedDays: overlapDays,
                    affectedRoutines: overlapRoutines,
                    reason: "Solapamiento de grupos entre sesiones: \(overlapDetails.joined(separator: "; ")). Se describe la coincidencia de grupos y la separación en días; no se calcula un tiempo de recuperación.",
                    recommendation: "Indicador descriptivo: revisa si la distribución se adapta a tu semana. No bloquea la confirmación."
                )
            )
        }

        return notices
    }

    private static func secondaryMuscleNames(_ session: GeneratedSession) -> [String] {
        var seen: [String] = []
        for exercise in session.exercises {
            for muscle in exercise.secondaryMuscles where !seen.contains(muscle.rawValue) {
                seen.append(muscle.rawValue)
            }
        }
        return seen
    }

    private static func frequencyText(_ counts: [String: Int]) -> String {
        guard !counts.isEmpty else { return "ninguna" }
        return counts.keys.sorted { (first: String, second: String) -> Bool in
            let firstCount: Int = counts[first] ?? 0
            let secondCount: Int = counts[second] ?? 0
            if firstCount != secondCount { return firstCount > secondCount }
            return first < second
        }.map { (raw: String) -> String in
            let name: String = MuscleGroup.mappedValue(for: raw)?.shortName ?? raw
            return "\(name) \(counts[raw] ?? 0)"
        }.joined(separator: ", ")
    }
}
