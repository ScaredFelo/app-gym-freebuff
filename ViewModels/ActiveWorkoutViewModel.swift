import Foundation
import SwiftData
import SwiftUI
import Combine

@MainActor
public final class ActiveWorkoutViewModel: ObservableObject {
    @Published public var session: WorkoutSession
    @Published public var routine: Routine
    @Published public var activeSets: [UUID: [SetInputState]] = [:]
    @Published public var structureVersion = 0

    // Rest Timer State
    @Published public var isResting = false
    @Published public var isRestPaused = false
    @Published public var restTimeRemaining = 0
    @Published public var totalRestSeconds = 0
    @Published public var restTimerEndDate: Date? = nil
    @Published public var isRestTimerActive: Bool = false
    @Published public var restTargetBpm: Int?
    @Published public var currentRestModeTitle = ""
    @Published public var currentExerciseName = ""
    @Published public var timerStartDate: Date?
    @Published public var timerTargetDuration = 0
    @Published public var isTimerMinimized: Bool = false
    @Published public var isRestFinishing: Bool = false

    // MARK: - Cronómetro por serie (ejercicios medidos en tiempo)

    /// Ejercicio y serie cuyo cronómetro está en marcha (solo uno a la vez).
    @Published public var stopwatchRoutineExerciseID: UUID?
    @Published public var stopwatchSetIndex: Int?
    @Published public var stopwatchStartDate: Date?

    /// Callback opcional invocado cuando el entrenamiento finaliza
    /// automáticamente desde el modo Big Picture (última serie del último ejercicio).
    public var onWorkoutFinished: (() -> Void)? = nil

    // MARK: - Datos de resumen de sesión

    /// Controla la presentación a pantalla completa del resumen final.
    /// Lo gestiona el ViewModel para que normal y Big Picture compartan el
    /// mismo estado de presentación.
    @Published public var isShowingSummary = false

    /// Último error de guardado pendiente de mostrar. Las vistas lo enlazan a
    /// una alerta y lo limpian al cerrarla.
    @Published public var saveErrorMessage: String? = nil

    /// Tiempo total transcurrido desde el inicio del entrenamiento hasta ahora
    /// (o hasta session.endDate si ya finalizó).
    public var totalWorkoutDuration: TimeInterval {
        let end = session.endDate ?? Date()
        return end.timeIntervalSince(session.startDate)
    }

    /// Tiempo total formateado como HH:mm:ss, o "X min" si es menor a una hora.
    public var totalWorkoutDurationFormatted: String {
        let totalSeconds = Int(totalWorkoutDuration)
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let seconds = totalSeconds % 60
        if hours > 0 {
            return String(format: "%02d:%02d:%02d", hours, minutes, seconds)
        }
        return String(format: "%d min", minutes)
    }

    /// Promedio de pulsaciones (BPM) de toda la sesión. Se alimenta de forma
    /// acumulativa para no depender del historial de 3 minutos de la gráfica,
    /// que se poda continuamente.
    public var averageBPM: Int {
        guard sessionBPMCount > 0 else { return 0 }
        return sessionBPMTotal / sessionBPMCount
    }

    private var sessionBPMTotal: Int = 0
    private var sessionBPMCount: Int = 0
    /// Historial completo de la sesión (no se poda). Se vuelca en
    /// `session.bpmSamples` al pasar a segundo plano o finalizar.
    private var sessionBPMSamples: [BPMSample] = []

    public var hasActiveRestTimer: Bool {
        guard let endDate = restTimerEndDate else { return false }
        return endDate > Date()
    }

    private var timerTask: Task<Void, Never>?
    private var bpmObserverTask: Task<Void, Never>?
    private var restDismissalTask: Task<Void, Never>?
    private var didStartWorkoutActivity = false
    private var restingSetNumber = 0
    private var restingTotalSets = 0
    /// Ejercicio al que pertenece el descanso en curso, para poder enviar a la
    /// Live Activity sus series completadas aunque el descanso sea en modo Big
    /// Picture o tras restaurar la sesión.
    private var restingRoutineExerciseID: UUID?
    private var currentRestCondition: RestCondition?

    private var originalRoutineExercises: [RoutineExercise] = []
    private var originalSnapshots: [RoutineSnapshot] = []
    private var addedRoutineExerciseIDs: Set<UUID> = []
    private var removedRoutineExercises: [RoutineExercise] = []

    private struct RoutineSnapshot {
        let id: UUID
        let exercise: Exercise?
        let defaultSets: Int
        let targetRepsMin: Int
        let targetRepsMax: Int
        let sortOrder: Int
        let defaultWeight: Double
        let restSeconds: Int
        let notes: String
    }

    public struct SetInputState: Identifiable {
        public let id = UUID()
        public let setNumber: Int
        public var weight: Double
        public var reps: Int
        public var isCompleted: Bool
        public var ghostWeight: Double?
        public var ghostReps: Int?
        public var existingLog: WorkoutSetLog?
    }

    public init(session: WorkoutSession, routine: Routine, modelContext: ModelContext) {
        self.session = session
        self.routine = routine
        if session.routineName.isEmpty {
            session.routineName = routine.name
        }
        self.isShowingSummary = session.endDate != nil
        setupInitialSets(modelContext: modelContext)
        captureOriginalStructure()
        if UserSettingsManager.isHeartRateTrackingEnabled,
           UserSettingsManager.heartRateDeviceType == .airPods {
            HealthKitManager.shared.requestAuthorization()
        }
        let hasStoredStateForSession = ActiveWorkoutStateStore.load()?.activeWorkoutID == session.id
        restorePersistedStateIfNeeded(modelContext: modelContext)
        if !hasStoredStateForSession {
            persistState()
        }
    }

    // MARK: - Exercise Structure

    private func setupInitialSets(modelContext: ModelContext) {
        for routineExercise in routine.exercises {
            activeSets[routineExercise.id] = buildSetStates(for: routineExercise, modelContext: modelContext)
        }
    }

    private func buildSetStates(for routineExercise: RoutineExercise, modelContext: ModelContext) -> [SetInputState] {
        guard let exercise = routineExercise.exercise else { return [] }

        let exerciseID = exercise.id
        let descriptor = FetchDescriptor<WorkoutSetLog>(
            sortBy: [SortDescriptor(\.date, order: .reverse)]
        )

        let fetchedLogs = (try? modelContext.fetch(descriptor)) ?? []
        let allLogs = fetchedLogs.filter { (log: WorkoutSetLog) -> Bool in
            return log.exercise?.id == exerciseID
        }

        // Historial de referencia: solo entrenamientos anteriores (nunca la
        // sesión en curso) y, preferentemente, de esta misma variante de rutina.
        let sessionID: UUID = session.id
        let previousLogs = allLogs.filter { (log: WorkoutSetLog) -> Bool in
            guard log.isCompleted else { return false }
            guard log.session?.id != sessionID else { return false }
            guard log.date < session.startDate else { return false }
            guard let logRoutineExerciseID: UUID = log.routineExerciseID else { return true }
            return logRoutineExerciseID == routineExercise.id
        }

        // Para la parrilla de Big Picture solo cuenta la última sesión previa.
        let lastSessionLogs: [WorkoutSetLog]
        if let latestSessionID: UUID = previousLogs.first?.session?.id {
            lastSessionLogs = previousLogs.filter { (log: WorkoutSetLog) -> Bool in
                return log.session?.id == latestSessionID
            }
        } else {
            lastSessionLogs = previousLogs
        }

        let currentLogs = session.setsCompleted.filter { (log: WorkoutSetLog) -> Bool in
            return log.exercise?.id == exerciseID && log.isCompleted
        }
        var legacyLogs = currentLogs
            .filter { (log: WorkoutSetLog) -> Bool in
                return log.routineExerciseID == nil
            }
            .sorted { (lhs: WorkoutSetLog, rhs: WorkoutSetLog) -> Bool in
                return lhs.date < rhs.date
            }
        var sets: [SetInputState] = []

        // El cardio se registra como un único bloque cronometrado: las series
        // no aportan nada cuando el objetivo son minutos continuos.
        let setCount: Int = exercise.trackingMode == .minutes ? 1 : max(1, routineExercise.defaultSets)

        for i in 1...setCount {
            let stableLog = currentLogs.first { (log: WorkoutSetLog) -> Bool in
                return log.routineExerciseID == routineExercise.id && log.setNumber == i
            }
            let legacyLog: WorkoutSetLog?
            if stableLog == nil, !legacyLogs.isEmpty {
                legacyLog = legacyLogs.removeFirst()
            } else {
                legacyLog = nil
            }
            let currentLog = stableLog ?? legacyLog

            let matchingLog = lastSessionLogs.first { (log: WorkoutSetLog) -> Bool in
                return log.setNumber == i
            }
                ?? (lastSessionLogs.indices.contains(i - 1) ? lastSessionLogs[i - 1] : nil)
            let ghostW = matchingLog?.weight
            let ghostR = matchingLog?.reps
            let initialWeight = routineExercise.defaultWeight > 0 ? routineExercise.defaultWeight : (ghostW ?? 0.0)
            let initialReps = routineExercise.targetRepsMax

            sets.append(SetInputState(
                setNumber: i,
                weight: currentLog?.weight ?? initialWeight,
                reps: currentLog?.reps ?? initialReps,
                isCompleted: currentLog != nil,
                ghostWeight: ghostW,
                ghostReps: ghostR,
                existingLog: currentLog
            ))
        }

        return sets
    }

    @discardableResult
    public func addExercise(_ exercise: Exercise, modelContext: ModelContext) -> RoutineExercise {
        let nextOrder = (routine.exercises.map(\.sortOrder).max() ?? -1) + 1
        let routineExercise = RoutineExercise(
            exercise: exercise,
            defaultSets: exercise.trackingMode == .minutes ? 1 : 3,
            targetRepsMin: exercise.targetRepsMin,
            targetRepsMax: exercise.targetRepsMax,
            sortOrder: nextOrder
        )

        modelContext.insert(routineExercise)
        routine.exercises.append(routineExercise)
        activeSets[routineExercise.id] = buildSetStates(for: routineExercise, modelContext: modelContext)
        addedRoutineExerciseIDs.insert(routineExercise.id)
        structureVersion += 1
        persist(modelContext, operation: "añadir el ejercicio")
        persistState()
        refreshLiveActivity()

        return routineExercise
    }

    /// Añade una serie extra al final del ejercicio durante el entrenamiento.
    /// Se apoya en la estructura de la rutina para que el cambio se pueda
    /// guardar al finalizar (o descartar, como el resto de modificaciones).
    @discardableResult
    public func addSet(for routineExerciseID: UUID, modelContext: ModelContext) -> Bool {
        guard var sets = activeSets[routineExerciseID],
              let routineExercise: RoutineExercise = routine.exercises.first(where: { (re: RoutineExercise) -> Bool in
                  return re.id == routineExerciseID
              }) else {
            return false
        }

        let reference: SetInputState? = sets.last
        sets.append(SetInputState(
            setNumber: (sets.map { $0.setNumber }.max() ?? 0) + 1,
            weight: reference?.weight ?? routineExercise.defaultWeight,
            reps: reference?.reps ?? routineExercise.targetRepsMax,
            isCompleted: false,
            ghostWeight: reference?.ghostWeight,
            ghostReps: reference?.ghostReps,
            existingLog: nil
        ))

        activeSets[routineExerciseID] = sets
        routineExercise.defaultSets = sets.count
        structureVersion += 1
        persist(modelContext, operation: "añadir la serie")
        persistState()
        refreshLiveActivity()

        return true
    }

    public func removeExercise(_ routineExercise: RoutineExercise, modelContext: ModelContext) {
        guard routine.exercises.contains(where: { $0.id == routineExercise.id }) else { return }

        routine.exercises.removeAll { $0.id == routineExercise.id }
        activeSets.removeValue(forKey: routineExercise.id)

        if addedRoutineExerciseIDs.contains(routineExercise.id) {
            addedRoutineExerciseIDs.remove(routineExercise.id)
            modelContext.delete(routineExercise)
        } else if !removedRoutineExercises.contains(where: { $0.id == routineExercise.id }) {
            removedRoutineExercises.append(routineExercise)
        }

        normalizeSortOrder()
        structureVersion += 1
        persist(modelContext, operation: "quitar el ejercicio")
        persistState()
        refreshLiveActivity()
    }

    private func normalizeSortOrder() {
        for (index, routineExercise) in routine.exercises.sorted(by: { (lhs: RoutineExercise, rhs: RoutineExercise) -> Bool in
            return lhs.sortOrder < rhs.sortOrder
        }).enumerated() {
            routineExercise.sortOrder = index
        }
    }

    private func captureOriginalStructure() {
        originalRoutineExercises = routine.exercises.sorted { (lhs: RoutineExercise, rhs: RoutineExercise) -> Bool in
            return lhs.sortOrder < rhs.sortOrder
        }
        originalSnapshots = originalRoutineExercises.map {
            RoutineSnapshot(
                id: $0.id,
                exercise: $0.exercise,
                defaultSets: $0.defaultSets,
                targetRepsMin: $0.targetRepsMin,
                targetRepsMax: $0.targetRepsMax,
                sortOrder: $0.sortOrder,
                defaultWeight: $0.defaultWeight,
                restSeconds: $0.restSeconds,
                notes: $0.notes
            )
        }
    }

    public var hasRoutineChanged: Bool {
        let current = routine.exercises.sorted { (lhs: RoutineExercise, rhs: RoutineExercise) -> Bool in
            return lhs.sortOrder < rhs.sortOrder
        }
        guard current.count == originalSnapshots.count else { return true }

        let snapshotsByID = Dictionary(uniqueKeysWithValues: originalSnapshots.map { ($0.id, $0) })

        for routineExercise in current {
            guard let snapshot = snapshotsByID[routineExercise.id] else { return true }
            if routineExercise.exercise?.id != snapshot.exercise?.id ||
                routineExercise.defaultSets != snapshot.defaultSets ||
                routineExercise.targetRepsMin != snapshot.targetRepsMin ||
                routineExercise.targetRepsMax != snapshot.targetRepsMax ||
                routineExercise.sortOrder != snapshot.sortOrder ||
                routineExercise.defaultWeight != snapshot.defaultWeight ||
                routineExercise.restSeconds != snapshot.restSeconds ||
                routineExercise.notes != snapshot.notes {
                return true
            }
        }

        return false
    }

    public var hasWorkoutChanges: Bool {
        hasRoutineChanged
    }

    /// Entrenamiento iniciado sin rutina con el botón "Entreno libre". La
    /// rutina es un contenedor temporal que no se lista y se reutiliza (vacío)
    /// en la siguiente sesión libre, así que no tiene sentido ofrecer guardar
    /// los cambios sobre ella al finalizar.
    public var isFreeWorkout: Bool {
        FreeWorkoutRoutineStore.isFree(routine)
    }

    private func restoreOriginalStructure(modelContext: ModelContext) {
        let currentExercises = routine.exercises
        for routineExercise in currentExercises where addedRoutineExerciseIDs.contains(routineExercise.id) {
            modelContext.delete(routineExercise)
            activeSets.removeValue(forKey: routineExercise.id)
        }

        for snapshot in originalSnapshots {
            guard let routineExercise: RoutineExercise = originalRoutineExercises.first(where: { (re: RoutineExercise) -> Bool in
                return re.id == snapshot.id
            }) else { continue }
            routineExercise.exercise = snapshot.exercise
            routineExercise.defaultSets = snapshot.defaultSets
            routineExercise.targetRepsMin = snapshot.targetRepsMin
            routineExercise.targetRepsMax = snapshot.targetRepsMax
            routineExercise.sortOrder = snapshot.sortOrder
            routineExercise.defaultWeight = snapshot.defaultWeight
            routineExercise.restSeconds = snapshot.restSeconds
            routineExercise.notes = snapshot.notes
        }

        routine.exercises = originalRoutineExercises.sorted { (lhs: RoutineExercise, rhs: RoutineExercise) -> Bool in
            return lhs.sortOrder < rhs.sortOrder
        }
        addedRoutineExerciseIDs.removeAll()
        removedRoutineExercises.removeAll()
        structureVersion += 1
    }

    private func commitRoutineChanges(modelContext: ModelContext) {
        let currentIDs = Set(routine.exercises.map(\.id))
        for routineExercise in removedRoutineExercises where !currentIDs.contains(routineExercise.id) {
            modelContext.delete(routineExercise)
        }
        removedRoutineExercises.removeAll()
        addedRoutineExerciseIDs.removeAll()
    }

    // MARK: - Sets

    public func toggleSetCompletion(for routineExerciseID: UUID, setIndex: Int, modelContext: ModelContext) {
        guard var sets = activeSets[routineExerciseID], sets.indices.contains(setIndex) else { return }

        let isNowCompleted = !sets[setIndex].isCompleted
        sets[setIndex].isCompleted = isNowCompleted

        // Completar la serie a mano cierra su cronómetro si seguía en marcha.
        if isNowCompleted, isStopwatchRunning(for: routineExerciseID, setIndex: setIndex) {
            stopStopwatch()
        }

        if isNowCompleted {
            let targetSet = sets[setIndex]
            let routineExercise: RoutineExercise? = routine.exercises.first(where: { (re: RoutineExercise) -> Bool in
                return re.id == routineExerciseID
            })
            let exercise = routineExercise?.exercise

            let log = WorkoutSetLog(
                date: Date(),
                workoutStartDate: session.startDate,
                weight: targetSet.weight,
                reps: targetSet.reps,
                targetRepsMin: routineExercise?.targetRepsMin ?? 8,
                targetRepsMax: routineExercise?.targetRepsMax ?? 12,
                isCompleted: true,
                routineExerciseID: routineExerciseID,
                setNumber: setIndex + 1,
                exercise: exercise,
                session: session
            )
            modelContext.insert(log)
            session.setsCompleted.append(log)
            sets[setIndex].existingLog = log
            activeSets[routineExerciseID] = sets
            session.totalVolumeKg += (targetSet.weight * Double(targetSet.reps))
            persist(modelContext, operation: "registrar la serie")

            if let exercise, let routineExercise {
                let condition: RestCondition
                if case .timer = exercise.defaultRestCondition {
                    condition = .timer(seconds: max(0, routineExercise.restSeconds))
                } else if case .bpmDrop = exercise.defaultRestCondition,
                          !UserSettingsManager.isHeartRateTrackingEnabled {
                    // Sin pulsómetro no hay forma de cerrar un descanso por
                    // recuperación: usamos el tiempo configurado del ejercicio.
                    condition = .timer(seconds: max(0, routineExercise.restSeconds))
                } else {
                    condition = exercise.defaultRestCondition
                }
                currentExerciseName = exercise.name
                restingSetNumber = setIndex + 1
                restingTotalSets = sets.count
                startRest(
                    with: condition,
                    exerciseName: exercise.name,
                    routineExerciseID: routineExercise.id
                )
            }
        } else {
            let targetSet = sets[setIndex]
            let volumeToSubtract: Double

            if let log = targetSet.existingLog {
                volumeToSubtract = log.weight * Double(log.reps)
                session.setsCompleted.removeAll { (l: WorkoutSetLog) -> Bool in
                    return l.id == log.id
                }
                modelContext.delete(log)
            } else {
                volumeToSubtract = targetSet.weight * Double(targetSet.reps)
            }

            sets[setIndex].existingLog = nil
            activeSets[routineExerciseID] = sets
            session.totalVolumeKg = max(0, session.totalVolumeKg - volumeToSubtract)
            persist(modelContext, operation: "actualizar la serie")
        }

        refreshLiveActivity()
        persistState()
    }

    public func updateSetValues(
        for routineExerciseID: UUID,
        setIndex: Int,
        weight: Double,
        reps: Int,
        modelContext: ModelContext
    ) {
        guard var sets = activeSets[routineExerciseID], sets.indices.contains(setIndex) else { return }

        let sanitizedWeight = max(0, weight)
        let sanitizedReps = max(0, reps)

        guard sets[setIndex].weight != sanitizedWeight || sets[setIndex].reps != sanitizedReps else {
            return
        }

        sets[setIndex].weight = sanitizedWeight
        sets[setIndex].reps = sanitizedReps

        if sets[setIndex].isCompleted, let log = sets[setIndex].existingLog {
            let previousVolume = log.weight * Double(log.reps)
            let newVolume = sanitizedWeight * Double(sanitizedReps)

            log.weight = sanitizedWeight
            log.reps = sanitizedReps
            session.totalVolumeKg = max(0, session.totalVolumeKg - previousVolume + newVolume)
            persist(modelContext, operation: "actualizar kg y repeticiones")
        }

        activeSets[routineExerciseID] = sets
        persistState()

        // Si la serie ya estaba completada, el cambio de kg/reps también debe
        // reflejarse al instante en la Live Activity.
        if sets[setIndex].isCompleted {
            refreshLiveActivity()
        }
    }

    // MARK: - Cronómetro por serie

    /// `true` si el cronómetro en marcha pertenece a esta serie concreta.
    public func isStopwatchRunning(for routineExerciseID: UUID, setIndex: Int) -> Bool {
        return stopwatchRoutineExerciseID == routineExerciseID
            && stopwatchSetIndex == setIndex
            && stopwatchStartDate != nil
    }

    /// El cronómetro de esta serie está en marcha (aunque sea de otro ejercicio).
    public func hasRunningStopwatch(for routineExerciseID: UUID) -> Bool {
        return stopwatchRoutineExerciseID == routineExerciseID && stopwatchStartDate != nil
    }

    /// Arranca o detiene el cronómetro de la serie. Al detenerlo se registra el
    /// tiempo real medido en segundos (isométricos) o minutos (cardio) y la
    /// serie queda completada, con su descanso como cualquier otra.
    public func toggleSetStopwatch(
        for routineExerciseID: UUID,
        setIndex: Int,
        modelContext: ModelContext
    ) {
        guard let sets = activeSets[routineExerciseID], sets.indices.contains(setIndex) else { return }
        guard let routineExercise: RoutineExercise = routine.exercises.first(where: { (re: RoutineExercise) -> Bool in
            return re.id == routineExerciseID
        }) else { return }
        guard let exercise: Exercise = routineExercise.exercise,
              exercise.trackingMode.isTimeBased else { return }

        if isStopwatchRunning(for: routineExerciseID, setIndex: setIndex) {
            let elapsed: TimeInterval = stopwatchElapsed()
            stopStopwatch()

            // Parada accidental (menos de medio segundo): no se registra nada.
            let value: Int = recordedValue(elapsed: elapsed, mode: exercise.trackingMode)
            guard value > 0 else { return }

            updateSetValues(
                for: routineExerciseID,
                setIndex: setIndex,
                weight: sets[setIndex].weight,
                reps: value,
                modelContext: modelContext
            )

            if !sets[setIndex].isCompleted {
                toggleSetCompletion(for: routineExerciseID, setIndex: setIndex, modelContext: modelContext)
            }
            return
        }

        // Un único cronómetro a la vez: lo medido en el anterior se conserva.
        finalizeRunningStopwatch(modelContext: modelContext)

        guard !sets[setIndex].isCompleted else { return }

        stopwatchRoutineExerciseID = routineExerciseID
        stopwatchSetIndex = setIndex
        stopwatchStartDate = Date()

        // El cronómetro tiene que sobrevivir a un cierre de la app.
        persistState()
    }

    /// Segundos transcurridos del cronómetro activo.
    public func stopwatchElapsed(at date: Date = Date()) -> TimeInterval {
        guard let start: Date = stopwatchStartDate else { return 0 }
        return max(0, date.timeIntervalSince(start))
    }

    public func stopStopwatch() {
        stopwatchRoutineExerciseID = nil
        stopwatchSetIndex = nil
        stopwatchStartDate = nil
    }

    /// Guarda el tiempo medido por el cronómetro activo sin completar la serie,
    /// para no perderlo al saltar a otro ejercicio.
    private func finalizeRunningStopwatch(modelContext: ModelContext) {
        guard let id: UUID = stopwatchRoutineExerciseID,
              let index: Int = stopwatchSetIndex,
              let start: Date = stopwatchStartDate else { return }

        let elapsed: TimeInterval = max(0, Date().timeIntervalSince(start))
        stopStopwatch()

        guard let mode: ExerciseTrackingMode = routine.exercises
            .first(where: { (re: RoutineExercise) -> Bool in
                return re.id == id
            })?.exercise?.trackingMode,
            let sets = activeSets[id],
            sets.indices.contains(index),
            !sets[index].isCompleted else { return }

        let value: Int = recordedValue(elapsed: elapsed, mode: mode)
        guard value > 0 else { return }

        updateSetValues(
            for: id,
            setIndex: index,
            weight: sets[index].weight,
            reps: value,
            modelContext: modelContext
        )
    }

    /// Convierte el tiempo medido a la unidad del ejercicio. En cardio se
    /// redondea al minuto más cercano y nunca se registra 0 si hubo trabajo.
    private func recordedValue(elapsed: TimeInterval, mode: ExerciseTrackingMode) -> Int {
        let capped: TimeInterval = min(max(0, elapsed), Self.maxStopwatchElapsed)
        guard capped > 0 else { return 0 }

        switch mode {
        case .reps:
            return 0
        case .seconds:
            return max(1, Int(capped.rounded()))
        case .minutes:
            return max(1, Int((capped / 60.0).rounded()))
        }
    }

    // MARK: - Scene Phase

    public func handleScenePhaseBackground(modelContext: ModelContext) {
        if session.endDate == nil {
            persistSessionDetails()
        }
        persist(modelContext, operation: "guardar al pasar a segundo plano")
        LiveActivityManager.shared.handleScenePhaseBackground()

        // Actualizamos el tiempo restante antes de persistir para que el estado
        // guardado refleje el instante exacto en el que la app se va a segundo plano.
        if isResting, !isRestPaused {
            updateRestRemainingFromClock()
        }

        persistState()
    }

    public func handleScenePhaseActive() {
        LiveActivityManager.shared.handleScenePhaseActive()

        guard isResting, !isRestPaused, !isRestFinishing else {
            refreshLiveActivity()
            return
        }

        if isRestTimerActive, let endDate = restTimerEndDate {
            let remaining = endDate.timeIntervalSinceNow
            if remaining > 0 {
                resumeRestRendering(remaining: remaining)
            } else {
                restTimeRemaining = 0
                finishRestOnForeground()
            }
            return
        }

        if let condition = currentRestCondition, case .bpmDrop(let targetBpm) = condition {
            startBpmRecoveryObserver(targetBpm: targetBpm)
        }

        refreshLiveActivity()
    }

    // MARK: - Rest Timer & BPM Drop Logic

    private func startRest(
        with condition: RestCondition,
        exerciseName: String,
        routineExerciseID: UUID?
    ) {
        stopRest()
        isResting = true
        isRestPaused = false
        isTimerMinimized = false
        currentRestCondition = condition
        currentExerciseName = exerciseName
        restingRoutineExerciseID = routineExerciseID

        switch condition {
        case .timer(let seconds):
            let startDate = Date()
            totalRestSeconds = seconds
            restTimeRemaining = seconds
            timerStartDate = startDate
            timerTargetDuration = seconds
            restTimerEndDate = startDate.addingTimeInterval(Double(seconds))
            isRestTimerActive = true
            currentRestModeTitle = "Descanso (\(seconds)s)"
            if let endDate = restTimerEndDate {
                NotificationManager.shared.scheduleRestFinishedNotification(endingAt: endDate)
            }
            AudioAlertService.shared.startBackgroundAudio()
            startTimerCountdown()

        case .bpmDrop(let targetBpm):
            restTargetBpm = targetBpm
            currentRestModeTitle = "Esperando recuperación (< \(targetBpm) BPM)"
            timerStartDate = nil
            timerTargetDuration = 0
            restTimerEndDate = nil
            isRestTimerActive = false
            startBpmRecoveryObserver(targetBpm: targetBpm)
        }

        refreshLiveActivity()
        persistState()
    }

    private func startTimerCountdown() {
        timerTask?.cancel()
        timerTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self, !self.isRestPaused else { return }

                let remaining: TimeInterval
                if let endDate = self.restTimerEndDate {
                    remaining = endDate.timeIntervalSinceNow
                } else if let startDate = self.timerStartDate {
                    remaining = Double(self.timerTargetDuration) - Date().timeIntervalSince(startDate)
                } else {
                    return
                }

                if remaining <= 0 {
                    // Solo mutamos el estado al terminar: la UI descuenta el
                    // tiempo con TimelineView y así evitamos re-renderizar la
                    // vista completa cada segundo.
                    self.restTimeRemaining = 0
                    self.finishRest()
                    return
                }

                // Dormimos en fragmentos cortos para reaccionar a +10/-10 s,
                // pero sin publicar cambios de estado en cada iteración.
                let sleepSeconds = min(remaining, 1.0)
                try? await Task.sleep(nanoseconds: UInt64(sleepSeconds * 1_000_000_000))
            }
        }
    }

    private func startBpmRecoveryObserver(targetBpm: Int) {
        bpmObserverTask?.cancel()
        bpmObserverTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self, self.isResting, !self.isRestPaused else { return }

                // Si el usuario desactiva la medición, el descanso por BPM no
                // puede completarse nunca: se cierra para no bloquear la serie.
                guard UserSettingsManager.isHeartRateTrackingEnabled else {
                    self.finishRest()
                    return
                }

                let currentBPM = BPMManager.shared.currentBPM
                if currentBPM > 0, currentBPM <= targetBpm {
                    self.finishRest()
                    return
                }

                try? await Task.sleep(nanoseconds: 1_000_000_000)
            }
        }
    }

    public func add10Seconds() {
        guard isResting, let condition = currentRestCondition, case .timer = condition else { return }

        if isRestPaused {
            restTimeRemaining += 10
            totalRestSeconds += 10
            timerTargetDuration = restTimeRemaining
        } else if let startDate = timerStartDate {
            timerTargetDuration += 10
            totalRestSeconds += 10
            restTimerEndDate = startDate.addingTimeInterval(Double(timerTargetDuration))
            isRestTimerActive = true
            updateRestRemainingFromClock()
            if let endDate = restTimerEndDate {
                NotificationManager.shared.scheduleRestFinishedNotification(endingAt: endDate)
            }
        }

        refreshLiveActivity()
        persistState()
    }

    public func sub10Seconds() {
        guard isResting, let condition = currentRestCondition, case .timer = condition else { return }

        if isRestPaused {
            restTimeRemaining -= 10
            totalRestSeconds = max(10, totalRestSeconds - 10)
            if restTimeRemaining <= 0 {
                finishRest()
            } else {
                timerTargetDuration = restTimeRemaining
            }
        } else if let startDate = timerStartDate {
            let newTarget = timerTargetDuration - 10
            let remaining = Int(ceil(Double(newTarget) - Date().timeIntervalSince(startDate)))

            if remaining <= 0 {
                timerTargetDuration = max(0, newTarget)
                restTimeRemaining = 0
                finishRest()
            } else {
                timerTargetDuration = newTarget
                totalRestSeconds = max(10, totalRestSeconds - 10)
                restTimeRemaining = remaining
                restTimerEndDate = startDate.addingTimeInterval(Double(newTarget))
                isRestTimerActive = true
                if let endDate = restTimerEndDate {
                    NotificationManager.shared.scheduleRestFinishedNotification(endingAt: endDate)
                }
            }
        }

        if !isRestFinishing {
            refreshLiveActivity()
        }
        persistState()
    }

    public func pauseRest() {
        guard isResting, !isRestPaused else { return }

        isRestPaused = true
        timerTask?.cancel()
        timerTask = nil
        bpmObserverTask?.cancel()
        bpmObserverTask = nil
        NotificationManager.shared.cancelRestFinishedNotification()

        if let condition = currentRestCondition, case .timer = condition, timerStartDate != nil {
            updateRestRemainingFromClock()
            timerStartDate = nil
            timerTargetDuration = restTimeRemaining
        }

        restTimerEndDate = nil
        isRestTimerActive = false
        refreshLiveActivity()
        persistState()
    }

    public func resumeRest() {
        guard isResting, isRestPaused, let condition = currentRestCondition else { return }

        isRestPaused = false

        switch condition {
        case .timer:
            guard restTimeRemaining > 0 else {
                finishRest()
                return
            }
            let startDate = Date()
            timerStartDate = startDate
            timerTargetDuration = restTimeRemaining
            restTimerEndDate = startDate.addingTimeInterval(Double(timerTargetDuration))
            isRestTimerActive = true
            if let endDate = restTimerEndDate {
                NotificationManager.shared.scheduleRestFinishedNotification(endingAt: endDate)
            }
            AudioAlertService.shared.startBackgroundAudio()
            startTimerCountdown()

        case .bpmDrop(let targetBpm):
            startBpmRecoveryObserver(targetBpm: targetBpm)
        }

        refreshLiveActivity()
        persistState()
    }

    private func updateRestRemainingFromClock() {
        if let endDate = restTimerEndDate {
            restTimeRemaining = max(0, Int(ceil(endDate.timeIntervalSinceNow)))
            return
        }

        guard let startDate = timerStartDate else { return }
        let elapsed = Date().timeIntervalSince(startDate)
        restTimeRemaining = max(0, Int(ceil(Double(timerTargetDuration) - elapsed)))
    }

    public func resumeRestRendering(remaining: TimeInterval) {
        guard isResting, !isRestPaused, restTimerEndDate != nil else { return }
        restTimeRemaining = max(0, Int(ceil(remaining)))
        startTimerCountdown()
        refreshLiveActivity()
    }

    public func finishRestOnForeground() {
        guard isResting, !isRestFinishing else { return }
        restTimeRemaining = 0
        finishRest()
    }

    public func skipRest() {
        guard isResting, !isRestFinishing else { return }
        beginRestDismissal()
    }

    private func finishRest() {
        guard isResting, !isRestFinishing else { return }
        AudioAlertService.shared.playRestFinishedAlert()
        beginRestDismissal()
    }

    private func beginRestDismissal() {
        restDismissalTask?.cancel()
        isRestFinishing = true
        restTimerEndDate = nil
        isRestTimerActive = false
        NotificationManager.shared.cancelRestFinishedNotification()
        refreshLiveActivity()
        persistState()

        restDismissalTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 260_000_000)
            guard let self, !Task.isCancelled, self.isRestFinishing else { return }

            self.clearRestState()
            self.refreshLiveActivity()
        }
    }

    public func stopRest() {
        clearRestState()
    }

    private func clearRestState() {
        NotificationManager.shared.cancelRestFinishedNotification()
        restDismissalTask?.cancel()
        restDismissalTask = nil
        timerTask?.cancel()
        timerTask = nil
        bpmObserverTask?.cancel()
        bpmObserverTask = nil
        isResting = false
        isRestFinishing = false
        isRestPaused = false
        restTargetBpm = nil
        timerStartDate = nil
        timerTargetDuration = 0
        restTimerEndDate = nil
        isRestTimerActive = false
        currentRestCondition = nil
        restingRoutineExerciseID = nil
        persistState()
    }

    // MARK: - Persistencia de la sesión

    /// Guarda en `UserDefaults` el estado completo de la rutina activa para
    /// poder restaurarla tal cual si el usuario cierra la app por completo.
    public func persistState() {
        guard session.endDate == nil else {
            ActiveWorkoutStateStore.clear()
            return
        }

        let completedSets: [PersistedWorkoutSet] = activeSets.flatMap { entry in
            entry.value.compactMap { set in
                guard set.isCompleted else { return nil }
                return PersistedWorkoutSet(
                    routineExerciseID: entry.key,
                    setNumber: set.setNumber,
                    weight: set.weight,
                    reps: set.reps,
                    date: set.existingLog?.date ?? Date()
                )
            }
        }

        let state = PersistedWorkoutState(
            activeWorkoutID: session.id,
            routineID: routine.id,
            workoutStartDate: session.startDate,
            completedSets: completedSets,
            restTimerEndDate: restTimerEndDate,
            bpmHistory: bpmHistory.map { (sample: BPMDataPoint) -> PersistedBPMPoint in
                return PersistedBPMPoint(timestamp: sample.timestamp, bpm: sample.bpm)
            },
            bpmTotal: sessionBPMTotal,
            bpmCount: sessionBPMCount,
            timerStartDate: timerStartDate,
            totalRestSeconds: totalRestSeconds,
            restTimeRemaining: restTimeRemaining,
            isResting: isResting,
            isRestPaused: isRestPaused,
            isRestTimerActive: isRestTimerActive,
            isTimerMinimized: isTimerMinimized,
            restCondition: currentRestCondition,
            restTargetBpm: restTargetBpm,
            currentExerciseName: currentExerciseName,
            currentRestModeTitle: currentRestModeTitle,
            restingSetNumber: restingSetNumber,
            restingTotalSets: restingTotalSets,
            stopwatchRoutineExerciseID: stopwatchRoutineExerciseID,
            stopwatchSetIndex: stopwatchSetIndex,
            stopwatchStartDate: stopwatchStartDate,
            updatedAt: Date()
        )

        ActiveWorkoutStateStore.save(state)
    }

    private func restorePersistedStateIfNeeded(modelContext: ModelContext) {
        guard session.endDate == nil,
              let state = ActiveWorkoutStateStore.load(),
              state.activeWorkoutID == session.id,
              state.routineID == routine.id else { return }

        // Recuperamos siempre el historial de BPM y las series completadas,
        // independientemente de que hubiera un descanso en curso.
        restoreBPMHistory(from: state)
        restoreCompletedSets(from: state.completedSets, modelContext: modelContext)
        restoreStopwatch(from: state)

        restoreRestState(from: state)
    }

    /// Reanuda el descanso guardado sin dejar estado fantasma.
    ///
    /// Solo se restaura lo que sigue vigente: un descanso por pulso, uno
    /// pausado o un temporizador con fecha futura. Si el temporizador venció
    /// mientras la app estaba cerrada, se limpia el estado (sin sonido) y se
    /// reescribe el snapshot para que la próxima apertura parta de cero.
    private func restoreRestState(from state: PersistedWorkoutState) {
        guard state.isResting else { return }

        func applyRestHeaders() {
            currentExerciseName = state.currentExerciseName
            currentRestModeTitle = state.currentRestModeTitle
            restingSetNumber = state.restingSetNumber
            restingTotalSets = state.restingTotalSets
            totalRestSeconds = state.totalRestSeconds
            isTimerMinimized = state.isTimerMinimized
            restTargetBpm = state.restTargetBpm
            currentRestCondition = state.restCondition ?? .timer(seconds: max(1, state.totalRestSeconds))
            restingRoutineExerciseID = routine.exercises.first { (re: RoutineExercise) -> Bool in
                return re.exercise?.name == state.currentExerciseName
            }?.id
        }

        if let condition = state.restCondition, case .bpmDrop(let targetBpm) = condition {
            applyRestHeaders()
            isResting = true
            isRestPaused = false
            restTargetBpm = targetBpm
            timerStartDate = nil
            timerTargetDuration = 0
            restTimerEndDate = nil
            isRestTimerActive = false
            startBpmRecoveryObserver(targetBpm: targetBpm)
            persistState()
            return
        }

        if state.isRestPaused {
            applyRestHeaders()
            isResting = true
            isRestPaused = true
            restTimeRemaining = max(0, state.restTimeRemaining)
            timerTargetDuration = restTimeRemaining
            timerStartDate = nil
            restTimerEndDate = nil
            isRestTimerActive = false
            persistState()
            return
        }

        if let endDate = state.restTimerEndDate, endDate > Date() {
            applyRestHeaders()
            isResting = true
            isRestPaused = false
            restTimerEndDate = endDate
            timerStartDate = state.timerStartDate ?? Date()
            isRestTimerActive = true
            restTimeRemaining = max(0, Int(ceil(endDate.timeIntervalSinceNow)))
            timerTargetDuration = max(state.totalRestSeconds, restTimeRemaining)
            NotificationManager.shared.scheduleRestFinishedNotification(endingAt: endDate)
            AudioAlertService.shared.startBackgroundAudio()
            startTimerCountdown()
            persistState()
            return
        }

        // Descanso vencido con la app cerrada: se descarta sin avisar.
        clearRestState()
    }

    /// Tiempo máximo que se acepta de un cronómetro restaurado. Evita registrar
    /// un bloque enorme si la app estuvo cerrada con el cronómetro en marcha.
    private static let maxStopwatchElapsed: TimeInterval = 4 * 3600

    /// Reanuda el cronómetro que quedó en marcha al cerrar la app, manteniendo
    /// su hora de inicio para que el tiempo medido siga siendo real.
    private func restoreStopwatch(from state: PersistedWorkoutState) {
        guard let id: UUID = state.stopwatchRoutineExerciseID,
              let index: Int = state.stopwatchSetIndex,
              let start: Date = state.stopwatchStartDate else { return }

        guard let sets = activeSets[id],
              sets.indices.contains(index),
              !sets[index].isCompleted else { return }

        guard Date().timeIntervalSince(start) <= Self.maxStopwatchElapsed else { return }

        stopwatchRoutineExerciseID = id
        stopwatchSetIndex = index
        stopwatchStartDate = start
    }

    /// Restaura las lecturas de pulso guardadas para que la gráfica de Big
    /// Picture no se vacíe al volver a abrir la app. El filtro de 3 minutos se
    /// aplica al dibujar, no al restaurar.
    private func restoreBPMHistory(from state: PersistedWorkoutState) {
        let persistedPoints: [PersistedBPMPoint] = state.bpmHistory ?? []
        bpmHistory = persistedPoints.filter { (point: PersistedBPMPoint) -> Bool in
            return point.bpm > 0
        }.map { (point: PersistedBPMPoint) -> BPMDataPoint in
            return BPMDataPoint(timestamp: point.timestamp, bpm: point.bpm)
        }

        bpmFeed.replaceAll(bpmHistory)

        let storedCount: Int = state.bpmCount ?? 0
        if storedCount > 0 {
            sessionBPMTotal = state.bpmTotal ?? 0
            sessionBPMCount = storedCount
        } else {
            // Estados guardados por versiones anteriores: aproximamos el
            // promedio con las lecturas disponibles.
            let validPoints: [BPMDataPoint] = bpmHistory
            sessionBPMTotal = validPoints.reduce(0) { (total: Int, point: BPMDataPoint) -> Int in
                return total + point.bpm
            }
            sessionBPMCount = validPoints.count
        }

        // Recuperamos el histórico completo ya guardado en la sesión y lo
        // fusionamos con las lecturas recientes persistidas en UserDefaults.
        let storedSamples: [BPMSample] = session.bpmSamples
        var merged: [BPMSample] = storedSamples
        let storedTimestamps: Set<Date> = Set(storedSamples.map { (sample: BPMSample) -> Date in
            return sample.timestamp
        })

        for point in bpmHistory where !storedTimestamps.contains(point.timestamp) {
            merged.append(BPMSample(timestamp: point.timestamp, bpm: Double(point.bpm)))
        }

        sessionBPMSamples = merged.sorted { (lhs: BPMSample, rhs: BPMSample) -> Bool in
            return lhs.timestamp < rhs.timestamp
        }
    }

    /// Vuelve a crear en SwiftData las series completadas que falten. Así los
    /// pesos, repeticiones e índice actual están listos antes de renderizar
    /// `ActiveWorkoutView`, incluso si el guardado anterior falló a medias.
    private func restoreCompletedSets(
        from persistedSets: [PersistedWorkoutSet],
        modelContext: ModelContext
    ) {
        guard !persistedSets.isEmpty else { return }

        var didInsertMissingLog = false

        for persisted in persistedSets {
            guard var sets = activeSets[persisted.routineExerciseID],
                  sets.indices.contains(persisted.setNumber - 1) else { continue }

            let index = persisted.setNumber - 1
            let routineExercise: RoutineExercise? = routine.exercises.first { (re: RoutineExercise) -> Bool in
                return re.id == persisted.routineExerciseID
            }

            if sets[index].existingLog != nil {
                sets[index].isCompleted = true
                activeSets[persisted.routineExerciseID] = sets
                continue
            }

            let log = WorkoutSetLog(
                date: persisted.date,
                workoutStartDate: session.startDate,
                weight: persisted.weight,
                reps: persisted.reps,
                targetRepsMin: routineExercise?.targetRepsMin ?? 8,
                targetRepsMax: routineExercise?.targetRepsMax ?? 12,
                isCompleted: true,
                routineExerciseID: persisted.routineExerciseID,
                setNumber: persisted.setNumber,
                exercise: routineExercise?.exercise,
                session: session
            )

            modelContext.insert(log)
            session.setsCompleted.append(log)
            sets[index].existingLog = log
            sets[index].isCompleted = true
            sets[index].weight = persisted.weight
            sets[index].reps = persisted.reps
            activeSets[persisted.routineExerciseID] = sets
            didInsertMissingLog = true
        }

        if didInsertMissingLog {
            let completedLogs: [WorkoutSetLog] = session.setsCompleted.filter { (log: WorkoutSetLog) -> Bool in
                return log.isCompleted
            }
            session.totalVolumeKg = completedLogs.reduce(0) { (total: Double, log: WorkoutSetLog) -> Double in
                return total + log.weight * Double(log.reps)
            }
        }

        persist(modelContext, operation: "restaurar las series completadas")
    }

    // MARK: - Finish / Cancel

    /// Vuelca en la sesión el nombre de rutina, el histórico completo de BPM y
    /// los registros detallados de ejercicios/series. Se invoca al pasar a
    /// segundo plano y al finalizar, de forma que la información sobreviva a
    /// cualquier cierre inesperado de la app.
    private func persistSessionDetails() {
        if session.routineName.isEmpty {
            session.routineName = routine.name
        }

        session.bpmSamples = sessionBPMSamples
        session.exerciseRecords = WorkoutMetricsCalculator.buildExerciseRecords(for: session)
    }

    @discardableResult
    public func finishWorkout(modelContext: ModelContext) -> WorkoutSession {
        stopRest()
        stopStopwatch()
        stopBPMTracking()
        HealthKitManager.shared.stopWorkoutSession()
        // Conserva la fecha de fin fijada al abrir el resumen: repetir la
        // confirmación ("Terminar sesión") no debe alargar la duración.
        let didCloseSession: Bool = session.endDate == nil
        if didCloseSession {
            session.endDate = Date()
        }
        persistSessionDetails()

        // El estado recuperable, la Live Activity y el audio solo se limpian
        // cuando el entrenamiento está realmente guardado en disco.
        guard saveFinishedWorkout(modelContext: modelContext) else {
            return session
        }

        endWorkoutActivity()
        // La sesión acaba de cerrarse: recalcula racha y objetivo del widget.
        // Confirmar el resumen vuelve a llamar a `finishWorkout`, así que solo
        // la primera llamada pide la recarga: dos peticiones seguidas hacen que
        // WidgetKit las agrupe o descarte.
        if didCloseSession {
            WidgetStreakStore.refresh(modelContext: modelContext)
        }
        isShowingSummary = true
        return session
    }

    /// Guarda el entrenamiento finalizado. Si falla, deshace el cambio de
    /// `endDate` y mantiene la sesión viva para poder reintentarlo: nunca se
    /// borra el estado recuperable antes de saber que el guardado ha ido bien.
    private func saveFinishedWorkout(modelContext: ModelContext) -> Bool {
        do {
            try modelContext.save()
            return true
        } catch {
            print("[Persistence] No se pudo guardar el entrenamiento finalizado: \(error)")
            modelContext.rollback()
            isShowingSummary = false
            saveErrorMessage = "No se ha podido guardar el entrenamiento. Sigue activo: vuelve a intentarlo cuando haya espacio libre en el dispositivo."
            persistState()
            return false
        }
    }

    /// Guardado de las acciones intermedias (series, ejercicios, notas). Si
    /// falla se avisa al usuario; el entrenamiento no se pierde porque cada
    /// serie se guarda por separado.
    private func persist(_ context: ModelContext, operation: String) {
        guard !PersistenceService.save(context, operation: operation) else { return }
        saveErrorMessage = "No se han podido guardar los últimos cambios (\(operation)). Comprueba el espacio libre del dispositivo."
    }

    /// Confirma el resumen final a pantalla completa: guarda definitivamente la
    /// sesión (manteniendo `session.startDate` original), detiene temporizadores,
    /// Live Activity y audio, limpia `ActiveWorkoutStateStore` y cierra el resumen.
    @discardableResult
    public func confirmWorkoutSummary(modelContext: ModelContext) -> Bool {
        _ = finishWorkout(modelContext: modelContext)
        // Si el guardado ha fallado, `endDate` se ha revertido y el resumen no
        // debe cerrarse: la pantalla sigue mostrando el entrenamiento activo.
        guard session.endDate != nil else { return false }
        isShowingSummary = false
        return true
    }

    @discardableResult
    public func finishWorkoutReplacingRoutine(modelContext: ModelContext) -> WorkoutSession {
        commitRoutineChanges(modelContext: modelContext)
        return finishWorkout(modelContext: modelContext)
    }

    @discardableResult
    public func finishWorkoutHistoryOnly(modelContext: ModelContext) -> WorkoutSession {
        restoreOriginalStructure(modelContext: modelContext)
        return finishWorkout(modelContext: modelContext)
    }

    @discardableResult
    public func finishWorkoutSavingAsNewRoutine(named name: String, modelContext: ModelContext) -> WorkoutSession {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let routineName = trimmedName.isEmpty ? "\(routine.name) (modificada)" : trimmedName

        let copiedExercises = routine.exercises.sorted { (lhs: RoutineExercise, rhs: RoutineExercise) -> Bool in
            return lhs.sortOrder < rhs.sortOrder
        }
            .map { (routineExercise: RoutineExercise) -> RoutineExercise in
                return Self.copyOfRoutineExercise(routineExercise)
            }

        copiedExercises.forEach { modelContext.insert($0) }
        let newRoutine = Routine(
            name: routineName,
            isTemplate: true,
            exercises: copiedExercises,
            source: .manual
        )
        modelContext.insert(newRoutine)
        restoreOriginalStructure(modelContext: modelContext)
        session.routineName = newRoutine.name
        persist(modelContext, operation: "guardar la rutina nueva")
        return finishWorkout(modelContext: modelContext)
    }

    /// Copia de un vínculo para «guardar como rutina nueva». Conserva todos los
    /// ajustes personalizados, incluido `hasCustomRest`: si se perdiera, las
    /// migraciones del catálogo podrían sobrescribir el descanso elegido por el
    /// usuario en la rutina recién creada.
    static func copyOfRoutineExercise(_ routineExercise: RoutineExercise) -> RoutineExercise {
        return RoutineExercise(
            exercise: routineExercise.exercise,
            defaultSets: routineExercise.defaultSets,
            targetRepsMin: routineExercise.targetRepsMin,
            targetRepsMax: routineExercise.targetRepsMax,
            sortOrder: routineExercise.sortOrder,
            defaultWeight: routineExercise.defaultWeight,
            restSeconds: routineExercise.restSeconds,
            notes: routineExercise.notes,
            hasCustomRest: routineExercise.hasCustomRest
        )
    }

    /// Descarta la sesión. Devuelve `false` si el borrado no se pudo guardar,
    /// en cuyo caso la vista no debe cerrarse para no perder el entrenamiento.
    @discardableResult
    public func cancelWorkout(modelContext: ModelContext) -> Bool {
        stopRest()
        stopStopwatch()
        stopBPMTracking()
        HealthKitManager.shared.stopWorkoutSession()
        restoreOriginalStructure(modelContext: modelContext)
        modelContext.delete(session)

        guard PersistenceService.saveOrRollback(modelContext, operation: "descartar el entrenamiento") else {
            saveErrorMessage = "No se ha podido descartar el entrenamiento. Sigue activo: vuelve a intentarlo."
            return false
        }

        endWorkoutActivity()
        // La sesión cancelada desaparece: recalcula racha y objetivo.
        WidgetStreakStore.refresh(modelContext: modelContext)
        return true
    }

    // MARK: - Live Activity

    /// Ejercicio que la Live Activity muestra en este instante. Las vistas lo
    /// observan para empujar un refresco inmediato al cambiar de ejercicio,
    /// tanto en modo normal como en Big Picture.
    public var liveActivityExerciseName: String {
        currentExerciseIdentity().name
    }

    /// Refresco inmediato de la Live Activity tras un cambio de ejercicio.
    /// Es idempotente: el manager descarta estados idénticos.
    public func notifyLiveActivityExerciseChanged() {
        refreshLiveActivity()
    }

    private func makeLiveActivitySnapshot() -> LiveActivityManager.Snapshot {
        let identity = currentExerciseIdentity()
        let endDate: Date? = isRestTimerActive ? restTimerEndDate : nil
        let isActive: Bool = isRestTimerActive && endDate != nil

        return LiveActivityManager.Snapshot(
            exerciseName: identity.name,
            completedSets: completedSetsForLiveActivity(routineExerciseID: identity.routineExerciseID),
            restStartDate: isActive ? (timerStartDate ?? endDate) : nil,
            restEndDate: endDate,
            isResting: isActive
        )
    }

    /// Series ya completadas del ejercicio indicado, numeradas tal y como se
    /// muestran en la Live Activity ("Serie 1", "Serie 2"...).
    private func completedSetsForLiveActivity(
        routineExerciseID: UUID?
    ) -> [LiveActivityCompletedSet] {
        guard let routineExerciseID,
              let sets = activeSets[routineExerciseID] else { return [] }

        return sets
            .filter { (set: SetInputState) -> Bool in
                return set.isCompleted
            }
            .sorted { (lhs: SetInputState, rhs: SetInputState) -> Bool in
                return lhs.setNumber < rhs.setNumber
            }
            .map { (set: SetInputState) -> LiveActivityCompletedSet in
                return LiveActivityCompletedSet(
                    id: set.setNumber,
                    weight: set.weight,
                    reps: set.reps
                )
            }
    }

    public func startWorkoutActivityIfNeeded() {
        guard session.endDate == nil, !didStartWorkoutActivity else { return }
        didStartWorkoutActivity = true
        NotificationManager.shared.requestAuthorization()
        HealthKitManager.shared.startWorkoutSession()
        AudioAlertService.shared.startBackgroundAudio()

        // La recepción de BPM vive ligada al entrenamiento, no a la vista: se
        // inicia aquí y solo se detiene al terminar o cancelar la sesión.
        startBPMTracking()

        LiveActivityManager.shared.startActivity(
            workoutName: routine.name,
            snapshot: makeLiveActivitySnapshot(),
            bpm: BPMManager.shared.currentBPM
        )
    }

    private func refreshLiveActivity() {
        guard didStartWorkoutActivity, session.endDate == nil else { return }
        LiveActivityManager.shared.updateSnapshot(makeLiveActivitySnapshot())
    }

    private func endWorkoutActivity() {
        didStartWorkoutActivity = false
        NotificationManager.shared.cancelRestFinishedNotification()
        AudioAlertService.shared.stopBackgroundAudio()
        LiveActivityManager.shared.endActivity()
        ActiveWorkoutStateStore.clear()
    }

    /// Ejercicio activo y su identificador. Durante un descanso manda el
    /// ejercicio que lo inició; después, el primer ejercicio con series
    /// pendientes. Ese criterio es común a los modos normal y Big Picture.
    private func currentExerciseIdentity() -> (routineExerciseID: UUID?, name: String) {
        if isResting, !currentExerciseName.isEmpty {
            let restingID: UUID? = restingRoutineExerciseID
                ?? routine.exercises.first(where: { (re: RoutineExercise) -> Bool in
                    return re.exercise?.name == currentExerciseName
                })?.id

            if restingID != nil {
                return (restingID, currentExerciseName)
            }
        }

        let exercises = routine.exercises.sorted { (lhs: RoutineExercise, rhs: RoutineExercise) -> Bool in
            return lhs.sortOrder < rhs.sortOrder
        }

        for routineExercise in exercises {
            guard let sets = activeSets[routineExercise.id], !sets.isEmpty else { continue }

            if sets.contains(where: { (set: SetInputState) -> Bool in
                return !set.isCompleted
            }) {
                return (routineExercise.id, routineExercise.exercise?.name ?? "Ejercicio")
            }
        }

        if let lastExercise = exercises.last,
           let sets = activeSets[lastExercise.id],
           !sets.isEmpty {
            return (lastExercise.id, lastExercise.exercise?.name ?? "Ejercicio")
        }

        return (nil, routine.name)
    }

    // MARK: - Big Picture Mode

    private var bigPictureSortedExercises: [RoutineExercise] {
        routine.exercises.sorted { (lhs: RoutineExercise, rhs: RoutineExercise) -> Bool in
            return lhs.sortOrder < rhs.sortOrder
        }
    }

    public var bigPictureCurrentRoutineExercise: RoutineExercise? {
        bigPictureSortedExercises.first { (routineExercise: RoutineExercise) -> Bool in
            guard let sets = activeSets[routineExercise.id] else { return false }
            return sets.contains { (set: SetInputState) -> Bool in
                return !set.isCompleted
            }
        } ?? bigPictureSortedExercises.first
    }

    public var bigPictureCurrentExercise: String {
        guard let exercise = bigPictureCurrentRoutineExercise?.exercise else { return "—" }
        return exercise.name
    }

    public var bigPictureNextExercise: String {
        let sorted = bigPictureSortedExercises
        guard let current = bigPictureCurrentRoutineExercise,
              let currentIndex: Int = sorted.firstIndex(where: { (re: RoutineExercise) -> Bool in
                  return re.id == current.id
              }),
              currentIndex + 1 < sorted.count,
              let nextExercise = sorted[currentIndex + 1].exercise else { return "" }
        return "SIG: \(nextExercise.name)"
    }

    public var bigPictureCurrentExerciseID: UUID? {
        bigPictureCurrentRoutineExercise?.id
    }

    public var bigPictureCurrentWeight: Double {
        guard let id = bigPictureCurrentExerciseID,
              let sets = activeSets[id],
              let pending = sets.first(where: { (set: SetInputState) -> Bool in
                  return !set.isCompleted
              }) else { return 0 }
        return pending.weight
    }

    public var bigPictureCurrentReps: Int {
        guard let id = bigPictureCurrentExerciseID,
              let sets = activeSets[id],
              let pending = sets.first(where: { (set: SetInputState) -> Bool in
                  return !set.isCompleted
              }) else { return 0 }
        return pending.reps
    }

    public var bigPictureSetsForCurrentExercise: [WorkoutSetLog] {
        guard let exercise = bigPictureCurrentRoutineExercise?.exercise else { return [] }
        return session.setsCompleted.filter { (log: WorkoutSetLog) -> Bool in
            return log.exercise?.id == exercise.id && log.isCompleted
        }.sorted { (lhs: WorkoutSetLog, rhs: WorkoutSetLog) -> Bool in
            return lhs.date < rhs.date
        }
    }

    /// Filas de la parrilla de series del ejercicio actual en Big Picture.
    /// Columna 1: número de serie. Columna 2: marca de la última sesión previa ("kg · reps" o "-").
    /// Columna 3: marca de la sesión actual si ya se completó (verde), o vacía si aún no.
    public struct BigPictureSetRow: Identifiable {
        public let id = UUID()
        public let setNumber: Int
        public let previousText: String?
        public let currentText: String?
    }

    public func bigPictureSetRows(modelContext: ModelContext) -> [BigPictureSetRow] {
        guard let id = bigPictureCurrentExerciseID,
              let sets = activeSets[id],
              let exercise = bigPictureCurrentRoutineExercise?.exercise else { return [] }

        let currentSets = sets.sorted { (lhs: SetInputState, rhs: SetInputState) -> Bool in
            return lhs.setNumber < rhs.setNumber
        }

        // Última sesión previa para este ejercicio (excluyendo la sesión en curso).
        let sessionID: UUID = session.id
        let descriptor = FetchDescriptor<WorkoutSetLog>(
            sortBy: [SortDescriptor(\.date, order: .reverse)]
        )
        let fetchedPastLogs = (try? modelContext.fetch(descriptor)) ?? []
        let pastLogs = fetchedPastLogs.filter { (log: WorkoutSetLog) -> Bool in
            return log.exercise?.id == exercise.id && log.isCompleted && log.session?.id != sessionID
        }

        // Agrupar por sesión y quedarse con la más reciente.
        // `pastLogs` viene ordenado por fecha descendente, así que el primer
        // log pertenece a la última sesión previa.
        let latestSessionID: UUID? = pastLogs.first?.session?.id
        let latestSessionLogs: [WorkoutSetLog]
        if let latestSessionID {
            let groupedLogs: [UUID?: [WorkoutSetLog]] = Dictionary(grouping: pastLogs) { (log: WorkoutSetLog) -> UUID? in
                return log.session?.id
            }
            if let logs = groupedLogs[latestSessionID] {
                latestSessionLogs = logs.sorted { (lhs: WorkoutSetLog, rhs: WorkoutSetLog) -> Bool in
                    return (lhs.setNumber ?? 0) < (rhs.setNumber ?? 0)
                }
            } else {
                latestSessionLogs = []
            }
        } else {
            latestSessionLogs = []
        }

        var rows: [BigPictureSetRow] = []
        for set in currentSets {
            let previous: WorkoutSetLog? = latestSessionLogs.first { (log: WorkoutSetLog) -> Bool in
                return log.setNumber == set.setNumber
            }
            let mode: ExerciseTrackingMode = exercise.trackingMode

            let previousText: String? = previous.map { (log: WorkoutSetLog) -> String in
                return markText(weight: log.weight, reps: log.reps, mode: mode)
            }

            let currentText: String?
            if set.isCompleted, let log = set.existingLog {
                currentText = markText(weight: log.weight, reps: log.reps, mode: mode)
            } else {
                currentText = nil
            }

            rows.append(BigPictureSetRow(
                setNumber: set.setNumber,
                previousText: previousText,
                currentText: currentText
            ))
        }

        return rows
    }

    /// Marca de una serie ya registrada: `60 kg · 8` en fuerza y solo la
    /// duración (`45 s` o `25 min`) en ejercicios medidos en tiempo.
    private func markText(weight: Double, reps: Int, mode: ExerciseTrackingMode) -> String {
        switch mode {
        case .reps:
            return "\(Int(weight)) kg · \(reps)"
        case .seconds:
            return "\(reps) s"
        case .minutes:
            return "\(reps) min"
        }
    }

    // MARK: Cronómetro en Big Picture

    public var bigPictureIsStopwatchRunning: Bool {
        guard let id: UUID = bigPictureCurrentExerciseID else { return false }
        return hasRunningStopwatch(for: id)
    }

    public var bigPictureStopwatchStartDate: Date? {
        return bigPictureIsStopwatchRunning ? stopwatchStartDate : nil
    }

    /// Arranca o detiene el cronómetro de la primera serie pendiente del
    /// ejercicio actual en Big Picture.
    public func toggleBigPictureStopwatch(modelContext: ModelContext) {
        guard let id: UUID = bigPictureCurrentExerciseID,
              let sets = activeSets[id],
              let setIndex: Int = sets.firstIndex(where: { (set: SetInputState) -> Bool in
                  return !set.isCompleted
              }) else { return }

        toggleSetStopwatch(for: id, setIndex: setIndex, modelContext: modelContext)
    }

    public var bigPictureIsTimerShowing: Bool {
        isResting && hasActiveRestTimer
    }

    public var bigPictureRemainingTime: Int {
        guard let endDate = restTimerEndDate else { return 0 }
        return max(0, Int(ceil(endDate.timeIntervalSinceNow)))
    }

    public var bigPictureRemainingTimeFormatted: String {
        let seconds = bigPictureRemainingTime
        return String(format: "%02d:%02d", seconds / 60, seconds % 60)
    }

    public var bigPictureRestProgress: Double {
        guard totalRestSeconds > 0 else { return 0 }
        return max(0, min(1, Double(bigPictureRemainingTime) / Double(totalRestSeconds)))
    }

    public func bigPictureUpdateWeight(_ weight: Double, modelContext: ModelContext) {
        guard let id = bigPictureCurrentExerciseID,
              let sets = activeSets[id],
              let index = sets.firstIndex(where: { !$0.isCompleted }) else { return }

        updateSetValues(
            for: id,
            setIndex: index,
            weight: weight,
            reps: sets[index].reps,
            modelContext: modelContext
        )
    }

    public func bigPictureAdjustReps(_ delta: Int) {
        guard let id = bigPictureCurrentExerciseID,
              var sets = activeSets[id],
              let index = sets.firstIndex(where: { (set: SetInputState) -> Bool in
                  return !set.isCompleted
              }) else { return }
        sets[index].reps = max(0, sets[index].reps + delta)
        activeSets[id] = sets
    }

    public func bigPictureRegisterSet(modelContext: ModelContext) {
        guard let id = bigPictureCurrentExerciseID,
              let sets = activeSets[id],
              let setIndex = sets.firstIndex(where: { (set: SetInputState) -> Bool in
                  return !set.isCompleted
              }) else { return }

        toggleSetCompletion(for: id, setIndex: setIndex, modelContext: modelContext)

        // Guardado automático: solo cuando TODAS las series de TODOS los ejercicios
        // de la rutina están completadas, y el usuario acaba de completar la última
        // serie del último ejercicio, se invoca finishWorkout().
        let isLastExercise: Bool = bigPictureSortedExercises.last?.id == id
        let updatedSets = activeSets[id] ?? []
        let isLastSet: Bool = setIndex == updatedSets.count - 1

        guard isLastExercise && isLastSet else { return }

        let allExercisesCompleted: Bool = bigPictureSortedExercises.allSatisfy { (routineExercise: RoutineExercise) -> Bool in
            guard let exerciseSets = activeSets[routineExercise.id] else { return false }
            return !exerciseSets.isEmpty && exerciseSets.allSatisfy { (set: SetInputState) -> Bool in
                return set.isCompleted
            }
        }

        if allExercisesCompleted {
            finishWorkout(modelContext: modelContext)
            onWorkoutFinished?()
        }
    }

    // MARK: - BPM History (Big Picture chart)

    public struct BPMDataPoint: Identifiable {
        public let id = UUID()
        public let timestamp: Date
        public let bpm: Int
    }

    /// Buffer de telemetría cardíaca aislado del ViewModel.
    ///
    /// El sensor entrega muestras a hasta 4 Hz. Publicar cada una desde el
    /// ViewModel invalidaba la vista completa del entrenamiento en cada latido.
    /// Este objeto agrupa las lecturas y solo notifica a quien lo observa (el
    /// chart de Big Picture) como máximo una vez por segundo.
    public final class BPMFeed: ObservableObject {
        @Published public private(set) var revision: Int = 0

        public private(set) var points: [BPMDataPoint] = []
        private let retentionWindow: TimeInterval = 185.0
        private var lastPublishDate: Date = .distantPast
        private let publishInterval: TimeInterval = 1.0

        public init() {}

        public func append(_ point: BPMDataPoint) {
            points.append(point)
            prune(relativeTo: point.timestamp)

            if point.timestamp.timeIntervalSince(lastPublishDate) >= publishInterval {
                lastPublishDate = point.timestamp
                revision &+= 1
            }
        }

        public func replaceAll(_ newPoints: [BPMDataPoint]) {
            points = newPoints
            revision &+= 1
        }

        public func clear() {
            points.removeAll()
            revision &+= 1
        }

        /// Lecturas dentro de la ventana indicada respecto a `date`.
        public func points(within window: TimeInterval, relativeTo date: Date) -> [BPMDataPoint] {
            let cutoff: Date = date.addingTimeInterval(-window)
            return points.filter { (sample: BPMDataPoint) -> Bool in
                return sample.timestamp >= cutoff && sample.timestamp <= date
            }
        }

        private func prune(relativeTo date: Date) {
            let cutoff: Date = date.addingTimeInterval(-retentionWindow)
            guard let firstValid: Int = points.firstIndex(where: { (sample: BPMDataPoint) -> Bool in
                return sample.timestamp >= cutoff
            }), firstValid > 0 else { return }
            points.removeFirst(firstValid)
        }
    }

    /// Historial completo de la sesión. Deliberadamente **sin publicar**: el
    /// sensor entrega lecturas de hasta 4 Hz y cada publicación invalidaba el
    /// cuerpo entero de `ActiveWorkoutView` (lista de ejercicios incluida),
    /// que era la causa principal de la sensación de lag al entrenar. La
    /// telemetría que se dibuja se expone a través de `bpmFeed`.
    public var bpmHistory: [BPMDataPoint] = []
    public let bpmFeed: BPMFeed = BPMFeed()
    private let bpmHistoryWindow: TimeInterval = 180
    private var lastBPMPersistDate: Date = .distantPast

    /// Historial de BPM filtrado a los últimos 3 minutos respecto al instante actual.
    /// Tipos de retorno explícitos para evitar fallos de inferencia en el chart.
    public var bpmHistoryLast3Minutes: [BPMDataPoint] {
        let now: Date = Date()
        let threeMinutesAgo: Date = now.addingTimeInterval(-180.0)
        return bpmHistory.filter { (sample: BPMDataPoint) -> Bool in
            return sample.timestamp >= threeMinutesAgo
        }
    }

    /// Inicia la escucha continua de pulsaciones (BLE + HealthKit). Se enlaza
    /// con el ciclo de vida del entrenamiento, no con la vista.
    private func startBPMTracking() {
        // El callback se registra siempre: si el usuario activa la medición a
        // mitad del entrenamiento, las lecturas empiezan a llegar sin reiniciar.
        BPMManager.shared.onBPMReceived = { [weak self] bpm in
            guard let self else { return }
            Task { @MainActor in
                self.onReceiveBPM(Double(bpm))
            }
        }

        // Sincroniza el sensor con los ajustes guardados y arranca el escaneo
        // (el manager lo ignora si la medición está desactivada).
        BPMManager.shared.applySettings()
        BPMManager.shared.startScanning()

        // Apple Salud solo se consulta cuando el dispositivo son los AirPods.
        guard UserSettingsManager.isHeartRateTrackingEnabled,
              UserSettingsManager.heartRateDeviceType == .airPods else { return }
        HealthKitManager.shared.startHeartRateQuery()
    }

    /// Detiene la escucha y la grabación de pulsaciones. Solo se invoca al
    /// terminar o cancelar el entrenamiento.
    private func stopBPMTracking() {
        BPMManager.shared.onBPMReceived = nil
        BPMManager.shared.stopScanning()
        HealthKitManager.shared.stopHeartRateQuery()
    }

    /// Callback único de recepción de BPM. Cada lectura, esté la app en primer
    /// plano, en otra app o con la pantalla bloqueada, se registra siempre en
    /// `bpmSamples` (haya o no descanso activo) y se envía a la Live Activity
    /// sin depender de temporizadores.
    public func onReceiveBPM(_ bpm: Double) {
        guard bpm > 0 else { return }
        guard UserSettingsManager.isHeartRateTrackingEnabled else { return }
        let value: Int = Int(bpm.rounded())
        addBPMPoint(value)
        LiveActivityManager.shared.updateBPM(value)
    }

    public func addBPMPoint(_ bpm: Int) {
        guard bpm > 0 else { return }

        let now: Date = Date()
        sessionBPMTotal += bpm
        sessionBPMCount += 1
        sessionBPMSamples.append(BPMSample(timestamp: now, bpm: Double(bpm)))
        let point: BPMDataPoint = BPMDataPoint(timestamp: now, bpm: bpm)
        bpmHistory.append(point)
        bpmFeed.append(point)
        pruneBPMHistory(relativeTo: now)
        persistBPMHistoryIfNeeded(now: now)
    }

    /// Lecturas dentro de la ventana indicada respecto a `date`. La vista la
    /// evalúa dentro de un `TimelineView`, por lo que la ventana de 3 minutos
    /// se desplaza sola aunque no lleguen nuevas lecturas.
    public func bpmPoints(
        within window: TimeInterval = 180,
        relativeTo date: Date = Date()
    ) -> [BPMDataPoint] {
        let cutoff: Date = date.addingTimeInterval(-window)
        return bpmHistory.filter { (sample: BPMDataPoint) -> Bool in
            return sample.timestamp >= cutoff && sample.timestamp <= date
        }
    }

    private func pruneBPMHistory(relativeTo date: Date) {
        let cutoff: Date = date.addingTimeInterval(-(bpmHistoryWindow + 5))
        guard let firstValid: Int = bpmHistory.firstIndex(where: { (sample: BPMDataPoint) -> Bool in
            return sample.timestamp >= cutoff
        }), firstValid > 0 else { return }
        bpmHistory.removeFirst(firstValid)
    }

    private func persistBPMHistoryIfNeeded(now: Date) {
        guard session.endDate == nil else { return }
        guard now.timeIntervalSince(lastBPMPersistDate) >= 15 else { return }
        lastBPMPersistDate = now
        // Volcamos las muestras en la sesión antes de persistir: así el
        // histórico completo sobrevive a un cierre inesperado o a que el
        // sistema libere memoria en segundo plano.
        session.bpmSamples = sessionBPMSamples
        persistState()
    }

    public func clearBPMHistory() {
        bpmHistory.removeAll()
        bpmFeed.clear()
        sessionBPMTotal = 0
        sessionBPMCount = 0
    }
}
