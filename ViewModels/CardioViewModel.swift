import Foundation
import Combine

/// Temporizador de una sesión de cardio por tiempo.
///
/// El cálculo se hace siempre contra la hora del sistema (`Date`), de modo que
/// el tiempo sigue siendo correcto aunque la app quede en segundo plano o el
/// móvil se bloquee. La cuenta atrás se cierra sola al alcanzar el objetivo y
/// el instante de finalización queda fijado en `finishedAt`.
///
/// Mientras la sesión corre también muestrea el pulsómetro para dibujar la
/// gráfica de BPM de los últimos 3 minutos y para construir el informe final.
@MainActor
public final class CardioViewModel: ObservableObject {
    public enum Phase: Equatable {
        case running
        case paused
        case finished
    }

    public let type: CardioType
    public let startedAt: Date
    /// Zona de pulso (1–5) cuyo abandono avisa; `nil` desactiva ese aviso.
    public let targetZone: Int?

    @Published public private(set) var targetDuration: TimeInterval
    @Published public private(set) var phase: Phase = .running
    @Published public private(set) var finishedAt: Date?
    @Published public private(set) var reachedTarget = false

    /// Muestras de pulso de toda la sesión. Deliberadamente **sin publicar**:
    /// la gráfica se evalúa dentro de un `TimelineView` y no hace falta
    /// invalidar la vista en cada lectura del sensor.
    public private(set) var bpmHistory: [BPMSample] = []

    private var accumulatedBeforeSegment: TimeInterval = 0
    private var segmentStart: Date?
    private var tickTask: Task<Void, Never>?
    /// Muestreo del sensor independiente de la cuenta atrás: sigue grabando
    /// durante las pausas para que la gráfica y el informe no tengan huecos.
    private var bpmTask: Task<Void, Never>?

    /// Cadencia de muestreo de la telemetría: suficiente para 3 minutos de
    /// gráfica sin acumular lecturas redundantes del sensor.
    private let bpmSampleInterval: TimeInterval = 2.0
    private var lastBPMSampleDate: Date = .distantPast
    /// Último volcado del estado a disco; se limita para no escribir en cada
    /// lectura del sensor.
    private var lastPersistDate: Date = .distantPast

    // Avisos sonoros: cada hito suena una única vez por sesión.
    private var didAnnounceHalfway = false
    private var didAnnounceFinalMinute = false
    // Salida de la zona objetivo: solo avisa tras un rato fuera y una vez por
    // salida, para no repetir con cada lectura del sensor.
    private var zoneLeftSince: Date?
    private var zoneExitAnnounced = false

    public init(
        type: CardioType,
        targetMinutes: Int,
        startedAt: Date = Date(),
        targetZone: Int? = nil
    ) {
        self.type = type
        self.startedAt = startedAt
        self.targetZone = targetZone
        self.targetDuration = TimeInterval(max(1, targetMinutes) * 60)
        self.segmentStart = startedAt
    }

    /// Reconstruye la sesión guardada cuando iOS suspende o cierra la app con
    /// el cardio en marcha (pantalla bloqueada, cambio de app, presión de
    /// memoria). El tiempo sigue anclado al reloj, así que no se pierde nada.
    init?(snapshot: CardioSessionSnapshot) {
        guard let type: CardioType = CardioType(rawValue: snapshot.typeRaw) else { return nil }

        self.type = type
        self.startedAt = snapshot.startedAt
        self.targetZone = snapshot.targetZone
        self.targetDuration = max(60.0, snapshot.targetDuration)
        self.accumulatedBeforeSegment = max(0.0, snapshot.accumulatedBeforeSegment)
        self.segmentStart = snapshot.isPaused ? nil : (snapshot.segmentStart ?? Date())
        self.phase = snapshot.isPaused ? .paused : .running
        self.bpmHistory = snapshot.bpmSamples.sorted { (lhs: BPMSample, rhs: BPMSample) -> Bool in
            return lhs.timestamp < rhs.timestamp
        }
        self.lastBPMSampleDate = self.bpmHistory.last?.timestamp ?? .distantPast

        // Los hitos ya alcanzados no vuelven a sonar al recuperar la sesión.
        let elapsedSoFar: TimeInterval = self.elapsed(at: Date())
        self.didAnnounceHalfway = elapsedSoFar >= self.targetDuration / 2.0
        self.didAnnounceFinalMinute = self.targetDuration - elapsedSoFar <= 60.0
    }

    // MARK: - Lecturas temporales

    /// Tiempo efectivo de la sesión hasta `date`, acotado al objetivo.
    public func elapsed(at date: Date) -> TimeInterval {
        let activeSegment: TimeInterval = segmentStart.map { max(0.0, date.timeIntervalSince($0)) } ?? 0.0
        return min(targetDuration, accumulatedBeforeSegment + activeSegment)
    }

    public func remaining(at date: Date) -> TimeInterval {
        return max(0.0, targetDuration - elapsed(at: date))
    }

    public func progress(at date: Date) -> Double {
        guard targetDuration > 0 else { return 1.0 }
        return min(1.0, max(0.0, elapsed(at: date) / targetDuration))
    }

    // MARK: - Control

    /// Vigila el objetivo y cierra la sesión al llegar a cero. Es idempotente.
    public func start() {
        guard phase == .running, tickTask == nil else { return }

        resumeMonitoring()

        tickTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 250_000_000)
                guard let self, !Task.isCancelled, self.phase == .running else { return }

                let now: Date = Date()

                if self.remaining(at: now) <= 0 {
                    self.terminate(reachedTarget: true)
                    AudioAlertService.shared.playCardioGoalAlert()
                    return
                }

                self.announceMilestones(at: now)
            }
        }
    }

    /// Avisa a la mitad del objetivo y en el último minuto. Si al despertar la
    /// app ya se ha pasado el último minuto, solo suena ese aviso para no
    /// encadenar dos pitidos seguidos.
    private func announceMilestones(at date: Date) {
        let done: TimeInterval = elapsed(at: date)
        let left: TimeInterval = remaining(at: date)

        if targetDuration > 90.0, left <= 60.0 {
            didAnnounceHalfway = true
            guard !didAnnounceFinalMinute else { return }
            didAnnounceFinalMinute = true
            AudioAlertService.shared.playCardioFinalMinuteAlert()
            return
        }

        guard !didAnnounceHalfway, done >= targetDuration / 2.0 else { return }
        didAnnounceHalfway = true
        AudioAlertService.shared.playCardioHalfwayAlert()
    }

    /// Reanuda sensor, muestreo de BPM y Live Activity sin arrancar la cuenta
    /// atrás. También se usa al recuperar una sesión que quedó en pausa.
    func resumeMonitoring() {
        guard phase != .finished else { return }

        startHeartRateSensing()
        startBPMRecording()
        startCardioActivity()
        persistSnapshot()
    }

    public func pause() {
        guard phase == .running else { return }

        accumulatedBeforeSegment = elapsed(at: Date())
        segmentStart = nil
        phase = .paused
        stopTicking()
        updateCardioActivity()
        persistSnapshot()
    }

    public func resume() {
        guard phase == .paused else { return }

        segmentStart = Date()
        phase = .running
        start()
        persistSnapshot()
    }

    /// Suma o resta minutos al objetivo sin detener la cuenta atrás.
    public func adjustTarget(byMinutes minutes: Int) {
        guard phase != .finished else { return }

        let updated: TimeInterval = targetDuration + TimeInterval(minutes) * 60.0
        targetDuration = min(180.0 * 60.0, max(60.0, updated))

        // Un objetivo nuevo reabre los hitos que queden por delante; los ya
        // alcanzados siguen sin repetirse.
        let done: TimeInterval = elapsed(at: Date())
        didAnnounceHalfway = done >= targetDuration / 2.0
        didAnnounceFinalMinute = targetDuration - done <= 60.0

        updateCardioActivity()
        persistSnapshot()
    }

    /// Cierra la sesión antes de tiempo conservando el tiempo ya realizado.
    public func finishEarly() {
        guard phase != .finished else { return }
        terminate(reachedTarget: false)
    }

    /// Abandona la sesión sin guardarla en el historial.
    public func cancelSession() {
        stopTicking()
        stopBPMRecording()
        stopHeartRateSensing()
        CardioLiveActivityManager.shared.end()
        CardioSessionStore.clear()
    }

    private func terminate(reachedTarget: Bool) {
        accumulatedBeforeSegment = elapsed(at: Date())
        segmentStart = nil
        phase = .finished
        finishedAt = Date()
        self.reachedTarget = reachedTarget
        stopTicking()
        stopBPMRecording()
        stopHeartRateSensing()
        CardioLiveActivityManager.shared.end()
        CardioSessionStore.clear()
    }

    private func stopTicking() {
        tickTask?.cancel()
        tickTask = nil
    }

    // MARK: - Telemetría cardíaca

    /// Muestras dentro de la ventana indicada respecto a `date` (3 minutos por
    /// defecto), que es lo que dibuja la gráfica en vivo.
    public func bpmPoints(
        within window: TimeInterval = 180.0,
        relativeTo date: Date = Date()
    ) -> [BPMSample] {
        let cutoff: Date = date.addingTimeInterval(-window)
        return bpmHistory.filter { (sample: BPMSample) -> Bool in
            return sample.timestamp >= cutoff && sample.timestamp <= date
        }
    }

    /// Resumen de la sesión terminada. Solo contiene datos calculables en
    /// cardio: tiempo, pulsaciones y carga cardiovascular (sin volumen ni
    /// densidad, porque no se levanta peso).
    func report() -> CardioMetrics {
        let end: Date = finishedAt ?? Date()
        return WorkoutMetricsCalculator.calculateCardio(
            duration: elapsed(at: end),
            samples: bpmHistory
        )
    }

    private func startHeartRateSensing() {
        guard UserSettingsManager.isHeartRateTrackingEnabled else { return }

        BPMManager.shared.applySettings()
        BPMManager.shared.startScanning()
    }

    private func stopHeartRateSensing() {
        BPMManager.shared.stopScanning()
    }

    private func recordHeartRateSample(at date: Date) {
        guard UserSettingsManager.isHeartRateTrackingEnabled else { return }
        guard date.timeIntervalSince(lastBPMSampleDate) >= bpmSampleInterval else { return }

        let bpm: Int = BPMManager.shared.currentBPM
        guard bpm > 0 else { return }

        lastBPMSampleDate = date
        bpmHistory.append(BPMSample(timestamp: date, bpm: Double(bpm)))
        CardioLiveActivityManager.shared.updateBPM(bpm)
        evaluateZoneTarget(bpm: Double(bpm), at: date)

        if date.timeIntervalSince(lastPersistDate) >= 10.0 {
            lastPersistDate = date
            persistSnapshot()
        }
    }

    /// Aviso opcional cuando el pulso abandona la zona objetivo durante medio
    /// minuto seguido. En pausa no se evalúa: el pulso baja de forma natural.
    private func evaluateZoneTarget(bpm: Double, at date: Date) {
        guard let zoneIndex: Int = targetZone,
              phase == .running,
              let bound: (index: Int, lower: Double, upper: Double) = WorkoutMetricsCalculator
                  .heartRateZoneBounds
                  .first(where: { (item: (index: Int, lower: Double, upper: Double)) -> Bool in
                      return item.index == zoneIndex
                  }) else {
            zoneLeftSince = nil
            zoneExitAnnounced = false
            return
        }

        let hrMax: Double = UserSettingsManager.hrMax
        guard hrMax > 0 else { return }

        let ratio: Double = bpm / hrMax
        let isInside: Bool = ratio >= bound.lower && ratio < bound.upper

        if isInside {
            zoneLeftSince = nil
            zoneExitAnnounced = false
            return
        }

        guard !zoneExitAnnounced else { return }

        guard let since: Date = zoneLeftSince else {
            zoneLeftSince = date
            return
        }

        guard date.timeIntervalSince(since) >= 30.0 else { return }

        zoneExitAnnounced = true
        zoneLeftSince = nil
        AudioAlertService.shared.playCardioZoneExitAlert()
    }

    // MARK: - Muestreo continuo

    private func startBPMRecording() {
        guard bpmTask == nil else { return }

        bpmTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                guard let self, !Task.isCancelled, self.phase != .finished else { return }
                self.recordHeartRateSample(at: Date())
            }
        }
    }

    private func stopBPMRecording() {
        bpmTask?.cancel()
        bpmTask = nil
    }

    // MARK: - Live Activity

    private func cardioActivitySnapshot() -> CardioLiveActivityManager.Snapshot {
        let now: Date = Date()
        let remainingTime: TimeInterval = remaining(at: now)

        return CardioLiveActivityManager.Snapshot(
            typeName: type.title,
            sessionName: type.sessionName,
            startDate: startedAt,
            endDate: now.addingTimeInterval(remainingTime),
            isPaused: phase == .paused,
            pausedRemaining: remainingTime,
            progress: progress(at: now)
        )
    }

    private func startCardioActivity() {
        CardioLiveActivityManager.shared.start(
            snapshot: cardioActivitySnapshot(),
            bpm: BPMManager.shared.currentBPM
        )
    }

    private func updateCardioActivity() {
        CardioLiveActivityManager.shared.update(
            snapshot: cardioActivitySnapshot(),
            bpm: BPMManager.shared.currentBPM
        )
    }

    // MARK: - Persistencia

    /// Guarda el estado de la sesión para poder reanudarla si iOS cierra la
    /// app mientras el cardio sigue activo.
    private func persistSnapshot() {
        CardioSessionStore.save(
            CardioSessionSnapshot(
                typeRaw: type.rawValue,
                startedAt: startedAt,
                targetDuration: targetDuration,
                accumulatedBeforeSegment: accumulatedBeforeSegment,
                segmentStart: segmentStart,
                isPaused: phase == .paused,
                bpmSamples: bpmHistory,
                savedAt: Date(),
                elapsedAtSave: elapsed(at: Date()),
                targetZone: targetZone
            )
        )
    }
}

// MARK: - Persistencia de la sesión activa

/// Estado serializable de una sesión de cardio en curso.
struct CardioSessionSnapshot: Codable {
    var typeRaw: String
    var startedAt: Date
    var targetDuration: TimeInterval
    var accumulatedBeforeSegment: TimeInterval
    var segmentStart: Date?
    var isPaused: Bool
    var bpmSamples: [BPMSample]
    /// Última escritura del snapshot; sirve para descartar sesiones huérfanas.
    var savedAt: Date?
    /// Tiempo efectivo acumulado en esa última escritura.
    var elapsedAtSave: TimeInterval?
    /// Zona de pulso objetivo elegida para los avisos (opcional).
    var targetZone: Int?

    /// Una sesión sin actualizaciones más allá de este tiempo se considera
    /// abandonada: no se reanuda sola, se ofrece guardarla o descartarla.
    static let abandonmentThreshold: TimeInterval = 6 * 3600
}

/// Guarda la sesión de cardio activa en `UserDefaults`. Es deliberadamente
/// pequeño: una única entrada que se sobrescribe y se borra al terminar o
/// descartar la sesión.
enum CardioSessionStore {
    private static let key: String = "activeCardioSessionSnapshot"

    static func save(_ snapshot: CardioSessionSnapshot) {
        guard let data: Data = try? JSONEncoder().encode(snapshot) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }

    static func load() -> CardioSessionSnapshot? {
        guard let data: Data = UserDefaults.standard.data(forKey: key),
              let snapshot: CardioSessionSnapshot = try? JSONDecoder().decode(CardioSessionSnapshot.self, from: data) else {
            return nil
        }
        return snapshot
    }

    static func clear() {
        UserDefaults.standard.removeObject(forKey: key)
    }
}
