import Foundation
import SwiftData

/// Estado de configuración de la organización del entrenamiento: modalidad,
/// número de rutinas propias, generación automática, resumen y guardado.
///
/// La lógica vive en `SplitGenerator`, `RoutineGenerator`, `ExerciseRules`,
/// `RecoveryAnalysisService` y `FatigueAnalysisService`; este ViewModel solo
/// coordina la entrada del usuario y el guardado.
@MainActor
final class RoutineConfigurationViewModel: ObservableObject {

    let context: RoutineFlowContext
    let assisted: AssistedSplitViewModel

    @Published var plan: RoutinePlanDraft
    @Published var automatic = AutomaticSplitState()
    @Published private(set) var isSaving: Bool = false
    @Published private(set) var didSave: Bool = false
    @Published private(set) var lastResult: RoutineApplicationResult?
    @Published var errorMessage: String?

    init(context: RoutineFlowContext) {
        self.context = context
        self.assisted = AssistedSplitViewModel()

        var draft: RoutinePlanDraft = RoutinePlanDraft()
        draft.ownRoutineCount = UserSettingsManager.configuredOwnRoutineCount
        self.plan = draft
    }

    // MARK: - Selección de modalidad

    var canContinueFromOrganization: Bool {
        return plan.mode != nil
    }

    /// Modalidades de la pantalla de organización. «Crear mis rutinas más
    /// tarde» solo se ofrece en la configuración inicial: Ajustes → Cambiar
    /// rutina existe para sustituir la organización actual por una nueva.
    var availableModes: [RoutineOrganizationMode] {
        guard context == .initialSetup else {
            return RoutineOrganizationMode.allCases.filter { (mode: RoutineOrganizationMode) -> Bool in
                return mode != .later
            }
        }
        return RoutineOrganizationMode.allCases
    }

    /// La modalidad «más tarde» no abre constructor, generador ni resumen: el
    /// flujo termina directamente y la lista de rutinas queda vacía.
    var completesWithoutRoutines: Bool {
        return plan.mode == .later
    }

    func selectMode(_ mode: RoutineOrganizationMode) {
        guard availableModes.contains(mode) else { return }
        plan.mode = mode
    }

    // MARK: - Generación automática

    var canContinueFromAutomatic: Bool {
        return automatic.week != nil
    }

    /// Avisos informativos de la semana generada, reutilizados en el resumen.
    var activeNotices: [RoutineNotice] {
        if plan.mode == .templates {
            return assisted.generatedWeek?.notices ?? []
        }
        return automatic.week?.notices ?? []
    }

    func setAutomaticDays(_ value: Int) {
        let clamped: Int = min(max(value, 1), 7)
        guard clamped != automatic.days else { return }
        automatic.days = clamped
        automatic.legs = min(automatic.legs, clamped)
        automatic.upper = min(automatic.upper, clamped)
        resetAutomaticResults()
    }

    func setAutomaticLegs(_ value: Int) {
        let clamped: Int = min(max(value, 0), automatic.days)
        guard clamped != automatic.legs else { return }
        automatic.legs = clamped
        resetAutomaticResults()
    }

    func setAutomaticUpper(_ value: Int) {
        let clamped: Int = min(max(value, 0), automatic.days)
        guard clamped != automatic.upper else { return }
        automatic.upper = clamped
        resetAutomaticResults()
    }

    /// Consulta la matriz W/L/U y deja todas las propuestas disponibles.
    func consultSplitMatrix() {
        resetAutomaticResults()
        automatic.hasConsulted = true

        let result: SplitGenerationResult = SplitGenerator.generate(
            w: automatic.days,
            l: automatic.legs,
            u: automatic.upper
        )

        switch result {
        case .invalidInput(let message):
            automatic.inputError = message

        case .warning(let warning):
            automatic.warning = warning

        case .proposals(let proposals, let incidences):
            automatic.proposals = proposals
            automatic.incidences = incidences

        case .failure(let message):
            automatic.generationError = message
        }
    }

    /// Genera la semana de la propuesta elegida y ejecuta los análisis.
    func selectProposal(_ proposal: SplitProposal) {
        automatic.selectedProposalID = proposal.id
        automatic.generationError = nil

        do {
            automatic.week = try RoutineGenerator.generate(proposal: proposal)
        } catch {
            automatic.week = nil
            automatic.generationError = error.localizedDescription
        }
    }

    private func resetAutomaticResults() {
        automatic.proposals = []
        automatic.incidences = []
        automatic.warning = nil
        automatic.inputError = nil
        automatic.selectedProposalID = nil
        automatic.week = nil
        automatic.generationError = nil
        automatic.hasConsulted = false
    }

    // MARK: - Guardado

    /// Guarda el plan completo (rutinas + preferencias + modalidad).
    /// Devuelve `true` solo si todo se ha escrito correctamente.
    func save(preferences: OnboardingPreferences, modelContext: ModelContext) async -> Bool {
        guard !isSaving else { return false }

        isSaving = true
        errorMessage = nil
        didSave = false

        // Un ciclo de runloop para que la interfaz pinte el estado de carga.
        await Task.yield()

        let generatedWeek: GeneratedWeek? = plan.mode == .automatic ? automatic.week : nil
        let assistedWeek: AssistedWeekDraft? = plan.mode == .templates ? assisted.savingDraft : nil

        guard plan.mode != .automatic || generatedWeek != nil else {
            errorMessage = RoutineConfigurationError.missingGeneratedPlan.errorDescription
            isSaving = false
            return false
        }

        guard plan.mode != .templates || assistedWeek != nil else {
            errorMessage = RoutineConfigurationError.missingAssistedWeek.errorDescription
            isSaving = false
            return false
        }

        do {
            let result: RoutineApplicationResult = try RoutineService.apply(
                plan: plan,
                preferences: preferences,
                context: modelContext,
                generatedWeek: generatedWeek,
                assistedWeek: assistedWeek,
                replacesOrganization: context == .changeRoutine
            )
            lastResult = result
            didSave = true
            isSaving = false
            return true
        } catch {
            errorMessage = error.localizedDescription
            isSaving = false
            return false
        }
    }

    // MARK: - Resumen

    /// Construye las secciones del resumen según la modalidad elegida.
    func summarySections(preferences: OnboardingPreferences) -> [RoutineSummarySection] {
        guard let mode: RoutineOrganizationMode = plan.mode else { return [] }

        switch mode {
        case .later:
            return [
                RoutineSummarySection(
                    code: "ORG.04",
                    title: "Rutinas",
                    items: [
                        RoutineSummaryItem(
                            code: "count",
                            label: "Rutinas a crear",
                            value: "0"
                        ),
                        RoutineSummaryItem(
                            code: "status",
                            label: "Organización",
                            value: "Sin definir"
                        )
                    ],
                    note: "Terminarás la configuración sin rutinas. Podrás crear la primera desde la pestaña Rutinas o con Cambiar rutina en Ajustes."
                ),
                preferencesSection(preferences)
            ]

        case .createOwn:
            return [
                RoutineSummarySection(
                    code: "ORG.01",
                    title: "Rutinas a crear",
                    items: [
                        RoutineSummaryItem(
                            code: "count",
                            label: "Rutinas vacías",
                            value: "\(plan.clampedRoutineCount)"
                        ),
                        RoutineSummaryItem(
                            code: "content",
                            label: "Contenido",
                            value: "Sin ejercicios"
                        ),
                        RoutineSummaryItem(
                            code: "previous",
                            label: "Rutinas anteriores",
                            value: context == .changeRoutine ? "Sustituidas" : "—"
                        )
                    ],
                    note: "Las rutinas se crean vacías. Añadirás los ejercicios manualmente desde la pestaña Rutinas."
                ),
                preferencesSection(preferences)
            ]

        case .templates:
            let week: GeneratedWeek? = assisted.generatedWeek
            return [
                RoutineSummarySection(
                    code: "TPL.01",
                    title: "Distribución semanal",
                    items: [
                        RoutineSummaryItem(
                            code: "week",
                            label: "Distribución",
                            value: week == nil ? "Sin generar" : "7 días configurados"
                        ),
                        RoutineSummaryItem(
                            code: "assigned",
                            label: "Sesiones",
                            value: "\(week?.sessions.count ?? 0)"
                        ),
                        RoutineSummaryItem(
                            code: "names",
                            label: "Rutinas",
                            value: week?.sessionNames.joined(separator: " / ") ?? "—"
                        )
                    ],
                    note: context == .changeRoutine
                        ? "Los días de descanso se guardan sin generar sesión. Al confirmar se sustituye la organización actual, sin borrar su historial."
                        : "Los días de descanso se guardan sin generar sesión. Las rutinas personales no se archivan."
                ),
                preferencesSection(preferences)
            ]

        case .automatic:
            return [automaticSection(), preferencesSection(preferences)]
        }
    }

    private func automaticSection() -> RoutineSummarySection {
        guard let week: GeneratedWeek = automatic.week else {
            return RoutineSummarySection(
                code: "AUT.01",
                title: "Generación automática",
                items: [
                    RoutineSummaryItem(
                        code: "parameters",
                        label: "Parámetros",
                        value: "W \(automatic.days) · L \(automatic.legs) · U \(automatic.upper)"
                    ),
                    RoutineSummaryItem(
                        code: "split",
                        label: "Distribución propuesta",
                        value: "Sin seleccionar"
                    )
                ],
                note: "Vuelve a la pantalla anterior, consulta la matriz y selecciona una propuesta para poder confirmar."
            )
        }

        return RoutineSummarySection(
            code: "AUT.01",
            title: "Generación automática",
            items: [
                RoutineSummaryItem(
                    code: "week",
                    label: "Días / piernas / superior",
                    value: "W \(week.w) · L \(week.l) · U \(week.u)"
                ),
                RoutineSummaryItem(
                    code: "split",
                    label: "Split seleccionado",
                    value: week.splitExpression
                ),
                RoutineSummaryItem(
                    code: "sessions",
                    label: "Sesiones",
                    value: "\(week.sessions.count) · \(week.restDays) días sin sesión"
                ),
                RoutineSummaryItem(
                    code: "routines",
                    label: "Rutinas",
                    value: week.sessionNames.joined(separator: " / ")
                ),
                RoutineSummaryItem(
                    code: "exercises",
                    label: "Ejercicios",
                    value: "\(week.totalExercises)"
                ),
                RoutineSummaryItem(
                    code: "notices",
                    label: "Avisos",
                    value: "\(week.recoveryNotices.count) recuperación · \(week.fatigueNotices.count) frecuencia/solapamiento"
                )
            ],
            note: "El orden mostrado es el del split. Los avisos de recuperación y fatiga son informativos y no impiden confirmar."
        )
    }

    private func preferencesSection(_ preferences: OnboardingPreferences) -> RoutineSummarySection {
        return RoutineSummarySection(
            code: "EQP.02",
            title: "Configuración general",
            items: [
                RoutineSummaryItem(
                    code: "multipower",
                    label: "Barra Multipower",
                    value: "\(UserSettingsManager.formatted(preferences.clampedMultipowerBarWeight)) KG"
                ),
                RoutineSummaryItem(
                    code: "ez",
                    label: "Barra EZ",
                    value: "\(UserSettingsManager.formatted(preferences.clampedEZBarWeight)) KG"
                ),
                RoutineSummaryItem(
                    code: "plates",
                    label: "Discos activos",
                    value: "\(preferences.availablePlates.count)"
                ),
                RoutineSummaryItem(
                    code: "bpm",
                    label: "Pulsaciones",
                    value: preferences.isHeartRateTrackingEnabled
                        ? preferences.heartRateDeviceType.title.uppercased()
                        : "DESACTIVADAS"
                )
            ]
        )
    }
}

// MARK: - Estado de la generación automática

/// Entrada W/L/U, propuestas de la matriz y semana seleccionada. Vive en el
/// ViewModel para no perder el estado al volver atrás en el flujo.
struct AutomaticSplitState {
    var days: Int = 3
    var legs: Int = 1
    var upper: Int = 2

    var proposals: [SplitProposal] = []
    var incidences: [String] = []
    var warning: SplitValidationWarning?
    var inputError: String?
    var selectedProposalID: String?
    var week: GeneratedWeek?
    var generationError: String?
    var hasConsulted: Bool = false
}

// MARK: - Constructor asistido

struct AssistedSessionEntry: Identifiable {
    let weekday: AssistedWeekday
    let session: GeneratedSession

    var id: String { "\(weekday.rawValue)-\(session.id)" }
}

/// Estado del constructor de siete días. No guarda nada: construye la
/// propuesta en memoria, asigna variantes con el catálogo real y deja que
/// `RoutineService` persista la semana de forma atómica.
@MainActor
final class AssistedSplitViewModel: ObservableObject {
    @Published private(set) var days: [AssistedDaySlot]
    @Published private(set) var validationErrors: [String] = []
    @Published private(set) var generationError: String?
    @Published private(set) var generatedWeek: GeneratedWeek?
    @Published private(set) var sessionsByWeekday: [AssistedWeekday: GeneratedSession] = [:]

    private let catalog: ExerciseCatalogStore?

    init(catalog: ExerciseCatalogStore? = ExerciseCatalogStore.shared) {
        self.catalog = catalog
        self.days = AssistedWeekday.allCases.map { (weekday: AssistedWeekday) -> AssistedDaySlot in
            return AssistedDaySlot(weekday: weekday)
        }

        if catalog == nil {
            validationErrors = ["No se ha podido cargar el catálogo de ejercicios de la aplicación."]
        }
    }

    var configuredCount: Int {
        return days.filter { (day: AssistedDaySlot) -> Bool in
            return day.selection.isConfigured
        }.count
    }

    var missingWeekdays: [AssistedWeekday] {
        return days.compactMap { (day: AssistedDaySlot) -> AssistedWeekday? in
            return day.selection.isConfigured ? nil : day.weekday
        }
    }

    var restDayCount: Int {
        return days.filter { (day: AssistedDaySlot) -> Bool in
            return day.selection.isRest
        }.count
    }

    var canContinue: Bool {
        return catalog != nil && missingWeekdays.isEmpty && validationErrors.isEmpty
    }

    var sessionEntries: [AssistedSessionEntry] {
        return AssistedWeekday.allCases.compactMap { (weekday: AssistedWeekday) -> AssistedSessionEntry? in
            guard let session: GeneratedSession = sessionsByWeekday[weekday] else { return nil }
            return AssistedSessionEntry(weekday: weekday, session: session)
        }
    }

    func selection(for weekday: AssistedWeekday) -> AssistedDaySelection {
        return days.first { (day: AssistedDaySlot) -> Bool in
            return day.weekday == weekday
        }?.selection ?? .unassigned
    }

    func assignedSuffix(for weekday: AssistedWeekday) -> String? {
        return days.first { (day: AssistedDaySlot) -> Bool in
            return day.weekday == weekday
        }?.assignedSuffix
    }

    func selectRoutine(_ routine: CatalogRoutine, for weekday: AssistedWeekday) {
        update(weekday) { (day: inout AssistedDaySlot) in
            day.selection = .routine(routine)
        }
    }

    func selectRest(for weekday: AssistedWeekday) {
        update(weekday) { (day: inout AssistedDaySlot) in
            day.selection = .rest
        }
    }

    func clear(_ weekday: AssistedWeekday) {
        update(weekday) { (day: inout AssistedDaySlot) in
            day.selection = .unassigned
        }
    }

    private func update(_ weekday: AssistedWeekday, change: (inout AssistedDaySlot) -> Void) {
        guard let index: Int = days.firstIndex(where: { (day: AssistedDaySlot) -> Bool in
            return day.weekday == weekday
        }) else { return }

        var updated: [AssistedDaySlot] = days
        change(&updated[index])
        days = updated
        resetGeneratedWeek()
        recalculateVariants()
    }

    private func resetGeneratedWeek() {
        generatedWeek = nil
        sessionsByWeekday = [:]
        generationError = nil
    }

    /// Cuenta las apariciones y asigna base/A/B/C en orden cronológico. Una
    /// variante ausente se notifica y bloquea la confirmación; nunca se duplica
    /// ni se inventa.
    private func recalculateVariants() {
        var updated: [AssistedDaySlot] = days
        var totals: [String: Int] = [:]

        for day in days {
            if case .routine(let routine) = day.selection {
                totals[routine.rawValue, default: 0] += 1
            }
        }

        var occurrences: [String: Int] = [:]
        var errors: [String] = []
        var reported: Set<String> = []

        guard let catalog else {
            validationErrors = ["No se ha podido cargar el catálogo de ejercicios de la aplicación."]
            days = updated
            return
        }

        for index in updated.indices {
            updated[index].assignedSuffix = nil
            updated[index].variantProblem = nil

            guard case .routine(let routine) = updated[index].selection else { continue }

            let total: Int = totals[routine.rawValue] ?? 0
            let occurrence: Int = (occurrences[routine.rawValue] ?? 0) + 1
            occurrences[routine.rawValue] = occurrence

            let suffixes: [String] = ExerciseCatalogStore.suffixes(for: total)
            let key: String = "\(routine.rawValue)-\(total)"

            if total > 3 {
                let availableCount: Int = (1...3).reduce(0) { (partial: Int, level: Int) -> Int in
                    let levelSuffixes: [String] = ExerciseCatalogStore.suffixes(for: level)
                    return partial + levelSuffixes.filter { (candidate: String) -> Bool in
                        catalog.variant(for: routine, occurrences: level, suffix: candidate) != nil
                    }.count
                }
                let problem: String = "«\(routine.displayName)» aparece \(total) veces y solo hay \(availableCount) variantes disponibles en el catálogo (máximo 3 apariciones)."
                updated[index].variantProblem = problem
                if reported.insert(key).inserted { errors.append(problem) }
                continue
            }

            guard occurrence <= suffixes.count else {
                let problem: String = "«\(routine.displayName)» aparece \(total) veces y no hay una variante para la aparición \(occurrence)."
                updated[index].variantProblem = problem
                if reported.insert(key).inserted { errors.append(problem) }
                continue
            }

            let suffix: String = suffixes[occurrence - 1]
            guard catalog.variant(for: routine, occurrences: total, suffix: suffix) != nil else {
                let available: [String] = suffixes.compactMap { (candidate: String) -> String? in
                    guard catalog.variant(for: routine, occurrences: total, suffix: candidate) != nil else { return nil }
                    return candidate.isEmpty ? "base" : candidate
                }
                let availableText: String = available.isEmpty ? "ninguna" : available.joined(separator: ", ")
                let label: String = suffix.isEmpty ? "base" : "variante \(suffix)"
                let problem: String = "«\(routine.displayName)» aparece \(total) veces y no dispone de la \(label). Variantes disponibles: \(availableText)."
                updated[index].variantProblem = problem
                if reported.insert(key).inserted { errors.append(problem) }
                continue
            }

            updated[index].assignedSuffix = suffix
        }

        days = updated
        validationErrors = errors
    }

    /// Genera las sesiones con el catálogo y ejecuta los análisis usando los
    /// días reales de la semana, no el índice de una lista de sesiones.
    @discardableResult
    func buildWeek() -> Bool {
        resetGeneratedWeek()
        recalculateVariants()

        guard missingWeekdays.isEmpty else {
            generationError = "Faltan días por configurar: \(missingWeekdays.map(\.displayName).joined(separator: ", "))."
            return false
        }

        guard validationErrors.isEmpty else {
            generationError = validationErrors.first
            return false
        }

        guard let catalog else {
            generationError = "No se ha podido cargar el catálogo de ejercicios de la aplicación."
            return false
        }

        let trainingDays: [(weekday: AssistedWeekday, routine: CatalogRoutine)] = days.compactMap { (day: AssistedDaySlot) -> (weekday: AssistedWeekday, routine: CatalogRoutine)? in
            guard case .routine(let routine) = day.selection else { return nil }
            return (day.weekday, routine)
        }

        let routines: [CatalogRoutine] = trainingDays.map { (entry: (weekday: AssistedWeekday, routine: CatalogRoutine)) -> CatalogRoutine in
            return entry.routine
        }

        let proposal: SplitProposal = SplitProposal(
            w: routines.count,
            l: routines.filter { (routine: CatalogRoutine) -> Bool in routine.trainsLegs }.count,
            u: routines.filter { (routine: CatalogRoutine) -> Bool in routine.trainsUpper }.count,
            expression: "ASISTIDO · \(routines.count) DÍAS",
            sessions: routines
        )

        do {
            let generated: GeneratedWeek = try RoutineGenerator.generate(proposal: proposal, catalog: catalog)
            var mapping: [AssistedWeekday: GeneratedSession] = [:]
            let weekdayIndices: [Int] = trainingDays.map { (entry: (weekday: AssistedWeekday, routine: CatalogRoutine)) -> Int in
                return entry.weekday.rawValue
            }

            for (offset, entry) in trainingDays.enumerated() where offset < generated.sessions.count {
                mapping[entry.weekday] = generated.sessions[offset]
            }

            let notices: [RoutineNotice] = RecoveryAnalysisService.analyze(
                sessions: generated.sessions,
                weekdays: weekdayIndices
            ) + FatigueAnalysisService.analyze(
                sessions: generated.sessions,
                weekdays: weekdayIndices
            )

            var limitations: [String] = [
                "La semana asistida asigna cada sesión a su día real. Los días de descanso no generan sesión."
            ]

            if trainingDays.isEmpty {
                limitations.append("Todos los días están marcados como descanso: la semana no contiene sesiones.")
            }

            if !generated.unmappedMuscleTokens.isEmpty {
                let detail: String = generated.unmappedMuscleTokens.map { (token: String) -> String in
                    return "«\(token)»"
                }.joined(separator: ", ")
                limitations.append("Análisis muscular parcial: el catálogo usa \(detail), sin equivalencia exacta en la app. La recuperación de esos músculos no se evalúa; el dato original se conserva en la ficha del ejercicio.")
            }

            generatedWeek = GeneratedWeek(
                w: generated.w,
                l: generated.l,
                u: generated.u,
                splitExpression: proposal.expression,
                sessions: generated.sessions,
                notices: notices,
                limitations: limitations
            )
            sessionsByWeekday = mapping
            generationError = nil
            return true
        } catch {
            generationError = error.localizedDescription
            return false
        }
    }

    var savingDraft: AssistedWeekDraft? {
        guard let week: GeneratedWeek = generatedWeek else { return nil }
        var drafts: [AssistedDayDraft] = []

        for day in days {
            switch day.selection {
            case .unassigned:
                return nil

            case .rest:
                drafts.append(
                    AssistedDayDraft(
                        weekday: day.weekday,
                        isRest: true,
                        routineRaw: nil,
                        variantSuffix: "",
                        sessionIndex: nil
                    )
                )

            case .routine(let routine):
                guard let session: GeneratedSession = sessionsByWeekday[day.weekday],
                      let index: Int = week.sessions.firstIndex(where: { (candidate: GeneratedSession) -> Bool in
                          return candidate.id == session.id
                      }) else {
                    return nil
                }

                drafts.append(
                    AssistedDayDraft(
                        weekday: day.weekday,
                        isRest: false,
                        routineRaw: routine.rawValue,
                        variantSuffix: session.variantSuffix,
                        sessionIndex: index
                    )
                )
            }
        }

        return AssistedWeekDraft(days: drafts, week: week)
    }
}
