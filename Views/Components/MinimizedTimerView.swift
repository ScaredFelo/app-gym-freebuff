import SwiftUI

public struct MinimizedTimerView: View {
    public let timeRemaining: Int
    public let totalSeconds: Int
    public let isPaused: Bool
    public let onExpand: () -> Void
    public let onTogglePause: () -> Void
    public let onAdd10: () -> Void
    public let onSub10: () -> Void
    public let onSkip: () -> Void

    public init(
        timeRemaining: Int,
        totalSeconds: Int,
        isPaused: Bool,
        onExpand: @escaping () -> Void,
        onTogglePause: @escaping () -> Void,
        onAdd10: @escaping () -> Void,
        onSub10: @escaping () -> Void,
        onSkip: @escaping () -> Void
    ) {
        self.timeRemaining = timeRemaining
        self.totalSeconds = totalSeconds
        self.isPaused = isPaused
        self.onExpand = onExpand
        self.onTogglePause = onTogglePause
        self.onAdd10 = onAdd10
        self.onSub10 = onSub10
        self.onSkip = onSkip
    }

    public var body: some View {
        HStack(spacing: 10.0) {
            HStack(spacing: 5.0) {
                Rectangle()
                    .fill(isPaused ? EndfieldPalette.accentRed : EndfieldPalette.accentYellow)
                    .frame(width: 3.0, height: 16.0)

                Text(timeFormatted(timeRemaining))
                    .font(EndfieldFont.mono(19.0, weight: .heavy))
                    .monospacedDigit()
                    .foregroundStyle(EndfieldPalette.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .fixedSize()
                    .allowsHitTesting(false)
            }

            Spacer(minLength: 4.0)

            HStack(spacing: 4.0) {
                timerButton(
                    icon: isPaused ? "play" : "pause",
                    tint: isPaused ? EndfieldPalette.accentYellow : EndfieldPalette.textPrimary,
                    action: onTogglePause,
                    accessibilityLabel: isPaused ? "Reanudar" : "Pausar"
                )

                timerButton(
                    icon: "gobackward.10",
                    action: onSub10,
                    accessibilityLabel: "Restar 10 segundos"
                )

                timerButton(
                    icon: "goforward.10",
                    action: onAdd10,
                    accessibilityLabel: "Añadir 10 segundos"
                )

                timerButton(
                    icon: "forward.end",
                    tint: EndfieldPalette.accentRed,
                    action: onSkip,
                    accessibilityLabel: "Omitir descanso"
                )
            }
        }
        .padding(.horizontal, 12.0)
        .padding(.vertical, 10.0)
        .background {
            Button(action: onExpand) {
                Color.clear
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Expandir temporizador")
        }
        .background(EndfieldPalette.bgPanel)
        .clipShape(ChamferedRectangle(cut: 10.0))
        .overlay(alignment: .bottom) {
            progressBar
        }
        .overlay {
            ChamferedRectangle(cut: 10.0)
                .stroke(EndfieldPalette.borderActive, lineWidth: 1.0)
        }
        .overlay {
            TacticalCornerCrosses(size: 5.0, inset: 3.0)
        }
        .shadow(color: Color.black.opacity(0.45), radius: 10.0, x: 0.0, y: 5.0)
    }

    private var progressBar: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Rectangle()
                    .fill(EndfieldPalette.bgElevated)

                Rectangle()
                    .fill(progressTint)
                    .frame(width: proxy.size.width * CGFloat(progress))
            }
        }
        .frame(height: 3.0)
        .padding(.horizontal, 12.0)
        .padding(.bottom, 5.0)
        .animation(.linear(duration: 0.25), value: progress)
        .allowsHitTesting(false)
    }

    private func timerButton(
        icon: String,
        tint: Color = EndfieldPalette.textSecondary,
        action: @escaping () -> Void,
        accessibilityLabel: String
    ) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .renderingMode(.template)
                .font(EndfieldFont.mono(12.0, weight: .bold))
                .foregroundStyle(tint)
                .frame(width: 28.0, height: 28.0)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel)
    }

    private var progress: Double {
        guard totalSeconds > 0 else { return 0 }
        let elapsed = Double(max(0, totalSeconds - timeRemaining))
        return min(max(elapsed / Double(totalSeconds), 0), 1)
    }

    private var progressTint: Color {
        isPaused ? EndfieldPalette.accentRed : EndfieldPalette.accentYellow
    }

    private func timeFormatted(_ seconds: Int) -> String {
        let clamped = max(0, seconds)
        return String(format: "%02d:%02d", clamped / 60, clamped % 60)
    }
}
