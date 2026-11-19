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

    /// Cadencia de muestreo de la telemetría: suficiente para 3 minutos de
    /// gráfica sin acumular lecturas redundantes del sensor.
    private let bpmSampleInterval: TimeInterval = 2.0
    private var lastBPMSampleDate: Date = .distantPast

    public init(type: CardioType, targetMinutes: Int, startedAt: Date = Date()) {
        self.type = type
        self.startedAt = startedAt
        self.targetDuration = TimeInterval(max(1, targetMinutes) * 60)
        self.segmentStart = startedAt
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

        startHeartRateSensing()

        tickTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 250_000_000)
                guard let self, !Task.isCancelled, self.phase == .running else { return }

                let now: Date = Date()
                self.recordHeartRateSample(at: now)

                if self.remaining(at: now) <= 0 {
                    self.terminate(reachedTarget: true)
                    return
                }
            }
        }
    }

    public func pause() {
        guard phase == .running else { return }

        accumulatedBeforeSegment = elapsed(at: Date())
        segmentStart = nil
        phase = .paused
        stopTicking()
    }

    public func resume() {
        guard phase == .paused else { return }

        segmentStart = Date()
        phase = .running
        start()
    }

    /// Suma o resta minutos al objetivo sin detener la cuenta atrás.
    public func adjustTarget(byMinutes minutes: Int) {
        guard phase != .finished else { return }

        let updated: TimeInterval = targetDuration + TimeInterval(minutes) * 60.0
        targetDuration = min(180.0 * 60.0, max(60.0, updated))
    }

    /// Cierra la sesión antes de tiempo conservando el tiempo ya realizado.
    public func finishEarly() {
        guard phase != .finished else { return }
        terminate(reachedTarget: false)
    }

    /// Abandona la sesión sin guardarla en el historial.
    public func cancelSession() {
        stopTicking()
        stopHeartRateSensing()
    }

    private func terminate(reachedTarget: Bool) {
        accumulatedBeforeSegment = elapsed(at: Date())
        segmentStart = nil
        phase = .finished
        finishedAt = Date()
        self.reachedTarget = reachedTarget
        stopTicking()
        stopHeartRateSensing()
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
    }
}
