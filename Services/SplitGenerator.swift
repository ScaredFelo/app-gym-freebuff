import Foundation

/// Consulta la matriz W/L/U y decide qué propuestas de split corresponden a la
/// selección del usuario. No construye sesiones: eso es responsabilidad de
/// `RoutineGenerator`.
enum SplitGenerator {
    static let weeklyRestMessage = "No se recomienda entrenar los 7 días de la semana sin descanso. El descanso es fundamental para la recuperación muscular, la prevención del sobreentrenamiento y el progreso. Ajusta los días de entrenamiento para incluir tiempo de recuperación."

    /// Devuelve todas las propuestas interpretables de la combinación exacta.
    static func generate(
        w: Int,
        l: Int,
        u: Int,
        store: SplitMatrixStore? = SplitMatrixStore.shared
    ) -> SplitGenerationResult {
        if let message: String = inputValidationMessage(w: w, l: l, u: u) {
            return .invalidInput(message)
        }

        // Regla absoluta: prevalece sobre cualquier split de la matriz.
        if w == 7 {
            return .warning(
                SplitValidationWarning(
                    kind: .weeklyRest,
                    message: weeklyRestMessage,
                    w: w,
                    l: l,
                    u: u
                )
            )
        }

        guard let store: SplitMatrixStore = store else {
            return .failure("No se puede consultar la matriz W/L/U porque el recurso no está disponible en la aplicación.")
        }

        guard let entry: SplitMatrixEntry = store.entry(w: w, l: l, u: u) else {
            return .failure("La combinación W=\(w), L=\(l), U=\(u) no existe en la matriz. No se generará ninguna rutina aproximada.")
        }

        if entry.isWarningRow {
            return .warning(
                SplitValidationWarning(
                    kind: .insufficientRest,
                    message: entry.warning ?? "No hi ha temps de descans suficient.",
                    w: w,
                    l: l,
                    u: u
                )
            )
        }

        var proposals: [SplitProposal] = []
        var incidences: [String] = []
        var seenExpressions: Set<String> = []

        for expression in entry.splits {
            if seenExpressions.contains(expression) {
                continue
            }
            seenExpressions.insert(expression)

            do {
                let sessions: [CatalogRoutine] = try SplitExpressionParser.parse(expression)

                guard sessions.count == w else {
                    incidences.append("La propuesta «\(expression)» genera \(sessions.count) sesiones y se esperaban \(w).")
                    continue
                }

                let legs: Int = sessions.filter { (routine: CatalogRoutine) -> Bool in
                    return routine.trainsLegs
                }.count

                let upper: Int = sessions.filter { (routine: CatalogRoutine) -> Bool in
                    return routine.trainsUpper
                }.count

                guard legs == l, upper == u else {
                    incidences.append("La propuesta «\(expression)» produce \(legs) sesiones de piernas y \(upper) de tren superior; la matriz declara \(l) y \(u).")
                    continue
                }

                proposals.append(
                    SplitProposal(w: w, l: l, u: u, expression: expression, sessions: sessions)
                )
            } catch {
                incidences.append("La propuesta «\(expression)» no pudo interpretarse: \(error.localizedDescription)")
            }
        }

        guard !proposals.isEmpty else {
            let detail: String = incidences.isEmpty
                ? "La combinación no tiene ninguna propuesta interpretable."
                : incidences.joined(separator: " ")
            return .failure("No se puede generar una rutina fiable para W=\(w), L=\(l), U=\(u). \(detail)")
        }

        return .proposals(proposals, incidences: incidences)
    }

    // MARK: - Validación de entrada

    static func inputValidationMessage(w: Int, l: Int, u: Int) -> String? {
        guard (1...7).contains(w) else {
            return "Los días de entrenamiento semanales deben estar entre 1 y 7."
        }
        guard (0...w).contains(l) else {
            return "La frecuencia de piernas debe estar entre 0 y \(w) sesiones."
        }
        guard (0...w).contains(u) else {
            return "La frecuencia del tren superior debe estar entre 0 y \(w) sesiones."
        }
        guard l + u > 0 else {
            return "La semana debe incluir al menos una sesión de piernas o de tren superior."
        }
        return nil
    }
}
