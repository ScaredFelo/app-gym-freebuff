import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

// MARK: - Cromo del flujo

/// Datos de cabecera compartidos por todas las pantallas del flujo.
struct OnboardingChrome {
    let contextTitle: String
    let stepLabel: String
    let progress: Double
    let showsCancel: Bool
    let onCancel: (() -> Void)?
}

// MARK: - Feedback háptico

enum OnboardingHaptics {
    static func selection() {
        #if canImport(UIKit)
        UISelectionFeedbackGenerator().selectionChanged()
        #endif
    }

    static func confirmation() {
        #if canImport(UIKit)
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        #endif
    }
}

// MARK: - Cabecera de progreso

struct OnboardingProgressHeader: View {
    let chrome: OnboardingChrome

    var body: some View {
        VStack(alignment: .leading, spacing: 6.0) {
            HStack(spacing: 8.0) {
                Text("APPGYM // SETUP")
                    .font(EndfieldFont.label(8.0))
                    .tracking(1.2)
                    .foregroundStyle(EndfieldPalette.accentYellow)

                Spacer(minLength: 4.0)

                Text(chrome.stepLabel)
                    .font(EndfieldFont.label(8.0))
                    .tracking(0.8)
                    .foregroundStyle(EndfieldPalette.textSecondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }

            SegmentedProgressBar(progress: chrome.progress, segments: 16, height: 3.0)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Progreso del onboarding")
        .accessibilityValue("\(chrome.stepLabel), \(Int(chrome.progress * 100.0)) por ciento")
    }
}

// MARK: - Estructura de paso

/// Contenedor común: retícula técnica, barra de progreso fija, cabecera,
/// contenido con scroll de padding lateral 16 y footer fijo con
/// `safeAreaInset`.
struct OnboardingStepLayout<Content: View>: View {
    private let chrome: OnboardingChrome
    private let title: String
    private let subtitle: String?
    private let footer: AnyView?
    private let content: Content

    init(
        chrome: OnboardingChrome,
        title: String,
        subtitle: String? = nil,
        footer: AnyView? = nil,
        @ViewBuilder content: () -> Content
    ) {
        self.chrome = chrome
        self.title = title
        self.subtitle = subtitle
        self.footer = footer
        self.content = content()
    }

    var body: some View {
        ZStack {
            TechnicalGridBackground()

            VStack(spacing: 0.0) {
                OnboardingProgressHeader(chrome: chrome)
                    .padding(.horizontal, 16.0)
                    .padding(.top, 4.0)
                    .padding(.bottom, 10.0)

                ScrollView {
                    VStack(alignment: .leading, spacing: 14.0) {
                        header
                        content
                    }
                    .padding(.horizontal, 16.0)
                    .padding(.bottom, 24.0)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .navigationTitle(chrome.contextTitle)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if chrome.showsCancel {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        chrome.onCancel?()
                    } label: {
                        Image(systemName: "xmark")
                            .font(EndfieldFont.mono(12.0, weight: .bold))
                            .foregroundStyle(EndfieldPalette.textSecondary)
                    }
                    .accessibilityLabel("Cancelar y cerrar")
                }
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0.0) {
            footerSurface
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6.0) {
            Text(title.uppercased())
                .font(EndfieldFont.mono(19.0, weight: .heavy))
                .foregroundStyle(EndfieldPalette.textPrimary)
                .fixedSize(horizontal: false, vertical: true)

            if let subtitle {
                Text(subtitle)
                    .font(EndfieldFont.mono(10.0))
                    .foregroundStyle(EndfieldPalette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }

    @ViewBuilder
    private var footerSurface: some View {
        if let footer {
            VStack(spacing: 0.0) {
                Rectangle()
                    .fill(EndfieldPalette.borderSubtle)
                    .frame(height: 1.0)

                footer
                    .padding(.horizontal, 16.0)
                    .padding(.top, 10.0)
                    .padding(.bottom, 8.0)
            }
            .frame(maxWidth: .infinity)
            .background(EndfieldPalette.bgPrimary)
        }
    }
}

// MARK: - Tarjeta seleccionable

/// Tarjeta técnica de selección única: código, título, descripción y estado
/// de selección con borde de acento.
struct OnboardingChoiceCard: View {
    let code: String
    let title: String
    let caption: String
    let symbolName: String
    let isSelected: Bool
    let tint: Color
    let action: () -> Void

    init(
        code: String,
        title: String,
        caption: String,
        symbolName: String,
        isSelected: Bool,
        tint: Color = EndfieldPalette.accentYellow,
        action: @escaping () -> Void
    ) {
        self.code = code
        self.title = title
        self.caption = caption
        self.symbolName = symbolName
        self.isSelected = isSelected
        self.tint = tint
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: 11.0) {
                Image(systemName: symbolName)
                    .font(.system(size: 15.0, weight: .semibold))
                    .foregroundStyle(isSelected ? tint : EndfieldPalette.textSecondary)
                    .frame(width: 24.0, height: 24.0)
                    .fixedSize()

                VStack(alignment: .leading, spacing: 4.0) {
                    Text(code)
                        .font(EndfieldFont.label(8.0))
                        .tracking(1.4)
                        .foregroundStyle(isSelected ? tint : EndfieldPalette.textSecondary)

                    Text(title.uppercased())
                        .font(EndfieldFont.mono(13.0, weight: .heavy))
                        .foregroundStyle(EndfieldPalette.textPrimary)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)

                    Text(caption)
                        .font(EndfieldFont.mono(9.0))
                        .foregroundStyle(EndfieldPalette.textSecondary)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 4.0)

                Image(systemName: isSelected ? "checkmark.square.fill" : "square")
                    .font(EndfieldFont.mono(12.0, weight: .bold))
                    .foregroundStyle(isSelected ? tint : EndfieldPalette.textSecondary.opacity(0.6))
                    .fixedSize()
            }
            .padding(12.0)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                ChamferedRectangle(cut: EndfieldMetrics.cornerCut)
                    .fill(isSelected ? EndfieldPalette.bgElevated : EndfieldPalette.bgPanel)
            )
            .overlay {
                ChamferedRectangle(cut: EndfieldMetrics.cornerCut)
                    .stroke(
                        isSelected ? tint.opacity(0.75) : EndfieldPalette.borderSubtle,
                        lineWidth: isSelected ? 1.5 : 1.0
                    )
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }
}

// MARK: - Nota técnica

struct OnboardingInfoNote: View {
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: 7.0) {
            Rectangle()
                .fill(EndfieldPalette.accentYellow.opacity(0.6))
                .frame(width: 2.0)

            Text(text)
                .font(EndfieldFont.mono(9.0))
                .foregroundStyle(EndfieldPalette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Módulo pendiente de integración

/// Marcador visual de los puntos donde se conectarán los generadores de las
/// fases 02 y 03. No contiene lógica provisional.
struct OnboardingIntegrationPlaceholder: View {
    let code: String
    let title: String
    let message: String
    let symbolName: String

    var body: some View {
        TacticalPanel(code: code, title: title, contentPadding: 12.0) {
            VStack(alignment: .leading, spacing: 9.0) {
                HStack(spacing: 7.0) {
                    Image(systemName: symbolName)
                        .font(EndfieldFont.mono(13.0, weight: .bold))
                        .foregroundStyle(EndfieldPalette.accentCyan)
                        .fixedSize()

                    Text("INTEGRACIÓN PENDIENTE")
                        .font(EndfieldFont.label(8.0))
                        .tracking(1.2)
                        .foregroundStyle(EndfieldPalette.accentCyan)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)

                    Spacer(minLength: 4.0)
                }

                Text(message)
                    .font(EndfieldFont.mono(9.0))
                    .foregroundStyle(EndfieldPalette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

// MARK: - Botón de avance

/// Footer estándar con una única acción principal.
struct OnboardingPrimaryFooter: View {
    let title: String
    let isEnabled: Bool
    let isLoading: Bool
    let action: () -> Void

    init(title: String, isEnabled: Bool = true, isLoading: Bool = false, action: @escaping () -> Void) {
        self.title = title
        self.isEnabled = isEnabled
        self.isLoading = isLoading
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8.0) {
                if isLoading {
                    ProgressView()
                        .tint(EndfieldPalette.bgPrimary)
                }

                Text(title)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
        }
        .buttonStyle(EndfieldPrimaryButtonStyle())
        .disabled(!isEnabled || isLoading)
        .opacity(isEnabled ? 1.0 : 0.45)
    }
}
