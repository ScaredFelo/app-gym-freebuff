import Foundation
import Combine

/// Temporizador de una sesión de cardio por tiempo.
///
/// El cálculo se hace siempre contra la hora del sistema (`Date`), de modo que
/// el tiempo sigue siendo correcto aunque la app quede en segundo plano o el
/// móvil se bloquee. La cuenta atrás se cierra sola al alcanzar el objetivo y
/// el instante de finalización queda fijado en `finishedAt`.
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

    private var accumulatedBeforeSegment: TimeInterval = 0
    private var segmentStart: Date?
    private var tickTask: Task<Void, Never>?

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

        tickTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 250_000_000)
                guard let self, !Task.isCancelled, self.phase == .running else { return }

                if self.remaining(at: Date()) <= 0 {
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

    private func terminate(reachedTarget: Bool) {
        accumulatedBeforeSegment = elapsed(at: Date())
        segmentStart = nil
        phase = .finished
        finishedAt = Date()
        self.reachedTarget = reachedTarget
        stopTicking()
    }

    private func stopTicking() {
        tickTask?.cancel()
        tickTask = nil
    }
}
