import Foundation
import SwiftUI

public struct CircularTimerView: View {
    public let timeRemaining: Int
    public let totalSeconds: Int
    public let isPaused: Bool
    public let onAdd10: () -> Void
    public let onSub10: () -> Void
    public let onTogglePause: () -> Void
    public let onSkip: () -> Void
    public let onMinimize: () -> Void

    private let dialSize: CGFloat = 260
    private let outerLineWidth: CGFloat = 14
    private let arcStartAngle: Double = 135
    private let arcSpan: Double = 270

    private var progress: Double {
        guard totalSeconds > 0 else { return 0 }
        return min(max(Double(timeRemaining) / Double(totalSeconds), 0), 1)
    }

    public init(
        timeRemaining: Int,
        totalSeconds: Int,
        isPaused: Bool,
        onAdd10: @escaping () -> Void,
        onSub10: @escaping () -> Void,
        onTogglePause: @escaping () -> Void,
        onSkip: @escaping () -> Void,
        onMinimize: @escaping () -> Void
    ) {
        self.timeRemaining = timeRemaining
        self.totalSeconds = totalSeconds
        self.isPaused = isPaused
        self.onAdd10 = onAdd10
        self.onSub10 = onSub10
        self.onTogglePause = onTogglePause
        self.onSkip = onSkip
        self.onMinimize = onMinimize
    }

    public var body: some View {
        VStack(spacing: 14.0) {
            headerRow

            dial

            controlsRow

            Button(action: onSkip) {
                Text("OMITIR // DESCANSO")
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .buttonStyle(EndfieldPrimaryButtonStyle())
        }
        .padding(.horizontal, 18.0)
        .padding(.vertical, 16.0)
        .background(ChamferedRectangle(cut: 14.0).fill(EndfieldPalette.bgPanel))
        .overlay {
            ChamferedRectangle(cut: 14.0)
                .stroke(EndfieldPalette.borderActive, lineWidth: 1.0)
        }
        .overlay {
            TacticalCornerCrosses(size: 6.0, inset: 4.0)
        }
        .padding(.horizontal, 20.0)
    }

    // MARK: Header

    private var headerRow: some View {
        HStack(spacing: 8.0) {
            Rectangle()
                .fill(isPaused ? EndfieldPalette.accentRed : EndfieldPalette.accentYellow)
                .frame(width: 3.0, height: 12.0)

            Text(isPaused ? "OPS.REST // PAUSA" : "OPS.REST // DESCANSO ACTIVO")
                .font(EndfieldFont.label(9.0))
                .tracking(1.2)
                .foregroundStyle(EndfieldPalette.textSecondary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)

            Spacer(minLength: 4.0)

            Button(action: onMinimize) {
                Image(systemName: "xmark")
                    .font(EndfieldFont.mono(10.0, weight: .bold))
            }
            .buttonStyle(EndfieldSquareButtonStyle(tint: EndfieldPalette.accentRed, size: 26.0))
            .accessibilityLabel("Minimizar temporizador")
        }
    }

    // MARK: Controls

    private var controlsRow: some View {
        HStack(spacing: 10.0) {
            controlButton(
                icon: "gobackward.10",
                tint: EndfieldPalette.textPrimary,
                filled: false,
                accessibilityLabel: "Restar 10 segundos",
                action: onSub10
            )

            controlButton(
                icon: isPaused ? "play" : "pause",
                tint: EndfieldPalette.accentYellow,
                filled: !isPaused,
                accessibilityLabel: isPaused ? "Reanudar descanso" : "Pausar descanso",
                action: onTogglePause
            )

            controlButton(
                icon: "goforward.10",
                tint: EndfieldPalette.textPrimary,
                filled: false,
                accessibilityLabel: "Añadir 10 segundos",
                action: onAdd10
            )
        }
    }

    private func controlButton(
        icon: String,
        tint: Color,
        filled: Bool,
        accessibilityLabel: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(EndfieldFont.mono(15.0, weight: .bold))
        }
        .buttonStyle(EndfieldSquareButtonStyle(tint: tint, size: 52.0, filled: filled))
        .accessibilityLabel(accessibilityLabel)
    }

    // MARK: Dial

    private var dial: some View {
        ZStack {
            Circle()
                .fill(EndfieldPalette.bgPrimary.opacity(0.55))

            Circle()
                .trim(from: 0, to: 0.75)
                .stroke(
                    Color.white.opacity(0.08),
                    style: StrokeStyle(lineWidth: outerLineWidth, lineCap: .butt)
                )
                .rotationEffect(.degrees(arcStartAngle))

            Circle()
                .trim(from: 0, to: 0.75 * progress)
                .stroke(
                    EndfieldPalette.accentYellow,
                    style: StrokeStyle(lineWidth: outerLineWidth, lineCap: .butt)
                )
                .rotationEffect(.degrees(arcStartAngle))
                .shadow(color: EndfieldPalette.accentYellow.opacity(0.30), radius: 5.0)
                .animation(.linear(duration: 1), value: progress)

            // Capa de pulso aislada: es la única que se recompone con cada
            // lectura del sensor (hasta 4 Hz).
            BPMDialLayer(
                dialSize: dialSize,
                arcStartAngle: arcStartAngle,
                arcSpan: arcSpan
            )

            readout
        }
        .frame(width: dialSize, height: dialSize)
    }

    private var readout: some View {
        VStack(spacing: 2.0) {
            Text(isPaused ? "PAUSADO" : "DESCANSO")
                .font(EndfieldFont.label(8.0))
                .tracking(2.0)
                .foregroundStyle(isPaused ? EndfieldPalette.accentRed : EndfieldPalette.textSecondary)

            Text(timeFormatted(timeRemaining))
                .font(EndfieldFont.mono(46.0, weight: .heavy))
                .monospacedDigit()
                .foregroundStyle(EndfieldPalette.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.6)

            BPMReadoutLabel()
        }
        .padding(.horizontal, 14.0)
        .padding(.vertical, 9.0)
        .background(ChamferedRectangle(cut: 6.0).fill(EndfieldPalette.bgPanel.opacity(0.92)))
        .overlay {
            ChamferedRectangle(cut: 6.0)
                .stroke(EndfieldPalette.borderSubtle, lineWidth: 1.0)
        }
    }

    private func timeFormatted(_ seconds: Int) -> String {
        let clamped = max(0, seconds)
        return String(format: "%02d:%02d", clamped / 60, clamped % 60)
    }
}

// MARK: - Capa de pulso del dial

/// Rangos y colores de la zona cardíaca compartidos por las vistas del dial.
private enum BPMZone {
    static let bounds: ClosedRange<Double> = 50...210
    static let ticks: [Int] = [50, 70, 90, 110, 130, 150, 170, 190, 210]

    static func color(for bpm: Int) -> Color {
        guard bpm > 0 else { return EndfieldPalette.accentYellow }
        switch bpm {
        case ..<90:
            return EndfieldPalette.accentCyan
        case ..<150:
            return EndfieldPalette.accentYellow
        default:
            return EndfieldPalette.accentRed
        }
    }

    static func angle(for bpm: Int, start: Double, span: Double) -> Double {
        let clamped: Double = min(max(Double(bpm), bounds.lowerBound), bounds.upperBound)
        let fraction: Double = (clamped - bounds.lowerBound) / (bounds.upperBound - bounds.lowerBound)
        return start + fraction * span
    }
}

/// Aguja, arco de zona y marcas del dial. Aislada del resto del temporizador
/// para que las lecturas del sensor no recompongan los círculos del anillo ni
/// el bloque de texto central.
private struct BPMDialLayer: View {
    let dialSize: CGFloat
    let arcStartAngle: Double
    let arcSpan: Double

    @ObservedObject private var healthKitManager = HealthKitManager.shared

    private var effectiveBPM: Int {
        healthKitManager.currentBPM > 0 ? min(max(healthKitManager.currentBPM, 50), 210) : 50
    }

    private var zoneColor: Color {
        BPMZone.color(for: healthKitManager.currentBPM)
    }

    private var needleAngle: Double {
        BPMZone.angle(for: effectiveBPM, start: arcStartAngle, span: arcSpan) - 270.0
    }

    var body: some View {
        ZStack {
            Circle()
                .inset(by: 28)
                .trim(from: 0, to: 0.75)
                .stroke(
                    zoneColor.opacity(0.45),
                    style: StrokeStyle(lineWidth: 2.0, lineCap: .butt)
                )
                .rotationEffect(.degrees(arcStartAngle))
                .animation(.easeInOut(duration: 0.4), value: zoneColor)

            ForEach(BPMZone.ticks, id: \.self) { (bpm: Int) in
                tickMark(for: bpm)
            }

            needle
        }
        .frame(width: dialSize, height: dialSize)
        .allowsHitTesting(false)
    }

    private var needle: some View {
        ZStack {
            Rectangle()
                .fill(zoneColor)
                .frame(width: 2.0, height: 92.0)
                .offset(y: -46.0)
                .shadow(color: zoneColor.opacity(0.5), radius: 5.0)

            Rectangle()
                .fill(zoneColor)
                .frame(width: 9.0, height: 9.0)
                .overlay {
                    Rectangle()
                        .stroke(EndfieldPalette.bgPrimary, lineWidth: 2.0)
                }
        }
        .frame(width: dialSize, height: dialSize)
        .rotationEffect(.degrees(needleAngle))
        .opacity(0.9)
        .animation(.easeOut(duration: 0.28), value: healthKitManager.currentBPM)
    }

    private func tickMark(for bpm: Int) -> some View {
        let angle: Double = BPMZone.angle(for: bpm, start: arcStartAngle, span: arcSpan)
        let radians: Double = angle * Double.pi / 180.0
        let center: CGFloat = dialSize / 2.0
        let isBoundary: Bool = bpm == BPMZone.ticks.first || bpm == BPMZone.ticks.last

        return ZStack {
            Rectangle()
                .fill(zoneColor.opacity(0.85))
                .frame(width: 1.5, height: isBoundary ? 12.0 : 8.0)
                .rotationEffect(.degrees(angle + 90.0))
                .position(
                    x: center + CGFloat(cos(radians)) * 94.0,
                    y: center + CGFloat(sin(radians)) * 94.0
                )

            Text("\(bpm)")
                .font(EndfieldFont.label(7.0))
                .monospacedDigit()
                .multilineTextAlignment(.center)
                .foregroundStyle(zoneColor.opacity(0.65))
                .position(
                    x: center + CGFloat(cos(radians)) * 78.0,
                    y: center + CGFloat(sin(radians)) * 78.0
                )
        }
    }
}

/// Lectura de BPM del bloque central, aislada del resto del temporizador.
private struct BPMReadoutLabel: View {
    @ObservedObject private var healthKitManager = HealthKitManager.shared

    var body: some View {
        Text(healthKitManager.currentBPM > 0 ? "\(healthKitManager.currentBPM) BPM" : "-- BPM")
            .font(EndfieldFont.mono(11.0, weight: .bold))
            .monospacedDigit()
            .foregroundStyle(BPMZone.color(for: healthKitManager.currentBPM))
    }
}
