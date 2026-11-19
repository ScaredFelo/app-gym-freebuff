import Foundation
import AVFoundation
import AudioToolbox
import UIKit

@MainActor
public final class AudioAlertService {
    public static let shared = AudioAlertService()

    private var backgroundPlayer: AVAudioPlayer?
    private var alertPlayer: AVAudioPlayer?
    private var restoreSessionTask: Task<Void, Never>?

    private init() {
        configureAudioSession(options: [.mixWithOthers])
    }

    private func configureAudioSession(options: AVAudioSession.CategoryOptions) {
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .default, options: options)
            try session.setActive(true)
        } catch {
            print("Failed to setup audio session: \(error)")
        }
    }

    public func startBackgroundAudio() {
        restoreSessionTask?.cancel()
        restoreSessionTask = nil
        configureAudioSession(options: [.mixWithOthers])

        if let player = backgroundPlayer {
            if !player.isPlaying {
                player.play()
            }
            return
        }

        do {
            let player = try AVAudioPlayer(data: Self.silentWAVData())
            player.numberOfLoops = -1
            player.volume = 0
            player.prepareToPlay()
            player.play()
            backgroundPlayer = player
        } catch {
            print("No se pudo mantener el audio en segundo plano: \(error.localizedDescription)")
        }
    }

    public func stopBackgroundAudio() {
        backgroundPlayer?.stop()
        backgroundPlayer = nil
    }

    public func playRestFinishedAlert() {
        restoreSessionTask?.cancel()
        configureAudioSession(options: [.duckOthers])

        var alertDuration = 1.8
        do {
            let player = try AVAudioPlayer(data: Self.boxingBellWAVData())
            player.volume = 1.0
            player.prepareToPlay()
            alertPlayer = player
            player.play()
            alertDuration = player.duration
        } catch {
            AudioServicesPlaySystemSound(1005)
        }

        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(.success)

        restoreSessionTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: UInt64((alertDuration + 0.25) * 1_000_000_000))
            guard !Task.isCancelled else { return }
            self?.configureAudioSession(options: [.mixWithOthers])
            self?.restoreSessionTask = nil
        }
    }

    public func playBpmTargetReachedAlert() {
        configureAudioSession(options: [.mixWithOthers])
        AudioServicesPlaySystemSound(1016)

        let generator = UIImpactFeedbackGenerator(style: .heavy)
        generator.impactOccurred()
    }

    // MARK: - Avisos de cardio

    /// Mitad del objetivo: un pitido medio, breve, para no tapar la música.
    public func playCardioHalfwayAlert() {
        playToneAlert(offsets: [0.0], frequency: 880.0, haptic: .medium)
    }

    /// Último minuto: tres pitidos agudos seguidos.
    public func playCardioFinalMinuteAlert() {
        playToneAlert(offsets: [0.0, 0.22, 0.44], frequency: 1318.51, haptic: .medium)
    }

    /// Objetivo completado: reutiliza la campana de fin de descanso.
    public func playCardioGoalAlert() {
        playRestFinishedAlert()
    }

    /// Salida de la zona de pulso objetivo: doble pitido grave y suave.
    public func playCardioZoneExitAlert() {
        playToneAlert(offsets: [0.0, 0.24], frequency: 587.33, haptic: .light)
    }

    /// Pitidos sintetizados en memoria: no dependen de sonidos del sistema,
    /// que cambian entre versiones de iOS y no siempre suenan en una sesión
    /// de audio activa.
    private func playToneAlert(
        offsets: [Double],
        frequency: Double,
        haptic: UIImpactFeedbackGenerator.FeedbackStyle
    ) {
        configureAudioSession(options: [.mixWithOthers])

        if let data: Data = Self.toneWAVData(frequency: frequency, offsets: offsets) {
            do {
                let player = try AVAudioPlayer(data: data)
                player.volume = 0.9
                player.prepareToPlay()
                alertPlayer = player
                player.play()
            } catch {
                AudioServicesPlaySystemSound(1057)
            }
        } else {
            AudioServicesPlaySystemSound(1057)
        }

        UIImpactFeedbackGenerator(style: haptic).impactOccurred()
    }

    private static func toneWAVData(
        frequency: Double,
        offsets: [Double],
        sampleRate: Int = 22050
    ) -> Data? {
        guard !offsets.isEmpty, frequency > 0 else { return nil }

        let beepDuration: Double = 0.16
        let total: Double = (offsets.last ?? 0.0) + beepDuration + 0.04
        let sampleCount: Int = Int(total * Double(sampleRate))
        guard sampleCount > 0 else { return nil }

        var mix = [Double](repeating: 0, count: sampleCount)

        for offset in offsets {
            let start: Int = Int(offset * Double(sampleRate))
            let length: Int = Int(beepDuration * Double(sampleRate))
            guard start >= 0, start < sampleCount else { continue }

            for index in 0..<length {
                let position: Int = start + index
                guard position < sampleCount else { break }

                let time: Double = Double(index) / Double(sampleRate)
                let attack: Double = min(1.0, time / 0.006)
                let release: Double = min(1.0, max(0.0, (beepDuration - time) / 0.02))
                mix[position] += sin(2 * Double.pi * frequency * time) * 0.55 * attack * release
            }
        }

        let samples = mix.map { (value: Double) -> Int16 in
            let clamped: Double = max(-1.0, min(1.0, value))
            return Int16(clamped * Double(Int16.max))
        }

        return wavData(sampleRate: sampleRate, samples: samples)
    }

    private static func silentWAVData(sampleRate: Int = 8000, duration: Double = 1.0) -> Data {
        let sampleCount = Int(Double(sampleRate) * duration)
        return wavData(sampleRate: sampleRate, samples: [Int16](repeating: 0, count: sampleCount))
    }

    private static func boxingBellWAVData(sampleRate: Int = 44100, duration: Double = 1.8) -> Data {
        let sampleCount = Int(Double(sampleRate) * duration)
        var mix = [Double](repeating: 0, count: sampleCount)

        let partials: [(frequency: Double, amplitude: Double, decay: Double)] = [
            (1046.50, 0.55, 4.2),
            (1567.98, 0.34, 5.4),
            (2093.00, 0.24, 6.5),
            (2637.02, 0.16, 7.8),
            (3135.96, 0.10, 9.0)
        ]

        let strikes: [Double] = [0.0, 0.30, 0.60]
        for strike in strikes {
            let start = Int(strike * Double(sampleRate))
            let strikeLength = min(sampleCount - start, Int(1.2 * Double(sampleRate)))
            guard start >= 0, strikeLength > 0 else { continue }

            for offset in 0..<strikeLength {
                let time = Double(offset) / Double(sampleRate)
                let attack = min(1.0, time / 0.003)
                var value = 0.0

                for partial in partials {
                    value += sin(2 * Double.pi * partial.frequency * time)
                        * partial.amplitude
                        * exp(-partial.decay * time)
                }

                if time < 0.02 {
                    value += (1.0 - time / 0.02) * 0.25 * sin(2 * Double.pi * 1800 * time)
                }

                mix[start + offset] += value * attack
            }
        }

        let peak = mix.reduce(0.0) { max($0, abs($1)) }
        let scale = peak > 0 ? 0.92 / peak : 1.0
        let samples = mix.map { value -> Int16 in
            let normalized = max(-1.0, min(1.0, value * scale))
            return Int16(normalized * Double(Int16.max))
        }

        return wavData(sampleRate: sampleRate, samples: samples)
    }

    private static func wavData(sampleRate: Int, samples: [Int16]) -> Data {
        let dataSize = samples.count * 2
        var data = Data()

        func append<T: FixedWidthInteger>(_ value: T) {
            var littleEndianValue = value.littleEndian
            withUnsafeBytes(of: &littleEndianValue) { bytes in
                data.append(contentsOf: bytes)
            }
        }

        data.append(contentsOf: Array("RIFF".utf8))
        append(UInt32(36 + dataSize))
        data.append(contentsOf: Array("WAVE".utf8))
        data.append(contentsOf: Array("fmt ".utf8))
        append(UInt32(16))
        append(UInt16(1))
        append(UInt16(1))
        append(UInt32(sampleRate))
        append(UInt32(sampleRate * 2))
        append(UInt16(2))
        append(UInt16(16))
        data.append(contentsOf: Array("data".utf8))
        append(UInt32(dataSize))

        for sample in samples {
            append(UInt16(bitPattern: sample))
        }

        return data
    }
}
