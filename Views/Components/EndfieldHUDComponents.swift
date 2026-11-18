import SwiftUI

// MARK: - 1. Forma angular

/// Rectángulo con esquinas cortadas en diagonal a 45°. Sustituye a las
/// tarjetas redondeadas tradicionales de iOS.
public struct ChamferedRectangle: Shape {
    public var topTrailingCut: CGFloat
    public var bottomLeadingCut: CGFloat

    public init(cut: CGFloat = EndfieldMetrics.cornerCut) {
        self.topTrailingCut = max(0.0, cut)
        self.bottomLeadingCut = max(0.0, cut)
    }

    public init(topTrailingCut: CGFloat, bottomLeadingCut: CGFloat) {
        self.topTrailingCut = max(0.0, topTrailingCut)
        self.bottomLeadingCut = max(0.0, bottomLeadingCut)
    }

    public func path(in rect: CGRect) -> Path {
        let limit: CGFloat = min(rect.width, rect.height) * 0.5
        let topRight: CGFloat = min(topTrailingCut, limit)
        let bottomLeft: CGFloat = min(bottomLeadingCut, limit)

        var path: Path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX - topRight, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY + topRight))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX + bottomLeft, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY - bottomLeft))
        path.closeSubpath()
        return path
    }
}

// MARK: - 2. Retícula táctica

/// Retícula arquitectónica muy sutil, sin fondo propio.
public struct TechnicalGridOverlay: View {
    public var step: CGFloat
    public var lineColor: Color
    public var lineWidth: CGFloat

    public init(
        step: CGFloat = EndfieldMetrics.gridStep,
        lineColor: Color = EndfieldPalette.gridLine,
        lineWidth: CGFloat = 0.5
    ) {
        self.step = step
        self.lineColor = lineColor
        self.lineWidth = lineWidth
    }

    public var body: some View {
        Canvas { context, size in
            let stride: CGFloat = max(step, 1.0)
            var path: Path = Path()

            var column: CGFloat = 0.0
            while column <= size.width {
                path.move(to: CGPoint(x: column, y: 0.0))
                path.addLine(to: CGPoint(x: column, y: size.height))
                column += stride
            }

            var row: CGFloat = 0.0
            while row <= size.height {
                path.move(to: CGPoint(x: 0.0, y: row))
                path.addLine(to: CGPoint(x: size.width, y: row))
                row += stride
            }

            context.stroke(path, with: .color(lineColor), lineWidth: lineWidth)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// Fondo completo de las pantallas principales: negro mate + retícula.
public struct TechnicalGridBackground: View {
    public var step: CGFloat

    public init(step: CGFloat = EndfieldMetrics.gridStep) {
        self.step = step
    }

    public var body: some View {
        ZStack {
            EndfieldPalette.bgPrimary
            TechnicalGridOverlay(step: step)
        }
        .ignoresSafeArea()
    }
}

// MARK: - 3. Franja de peligro industrial

/// Franja horizontal con patrón diagonal `///` en amarillo táctico y negro.
public struct HazardStripeBar: View {
    public var height: CGFloat
    public var stripeWidth: CGFloat
    public var gap: CGFloat
    public var tint: Color

    public init(
        height: CGFloat = 7.0,
        stripeWidth: CGFloat = 9.0,
        gap: CGFloat = 9.0,
        tint: Color = EndfieldPalette.accentYellow
    ) {
        self.height = height
        self.stripeWidth = stripeWidth
        self.gap = gap
        self.tint = tint
    }

    public var body: some View {
        Canvas { context, size in
            let canvasHeight: CGFloat = max(size.height, 1.0)
            let stripe: CGFloat = max(stripeWidth, 1.0)
            let spacing: CGFloat = stripe + max(gap, 0.0)
            let slant: CGFloat = canvasHeight

            var start: CGFloat = -slant - stripe
            while start < size.width + slant {
                var path: Path = Path()
                path.move(to: CGPoint(x: start, y: canvasHeight))
                path.addLine(to: CGPoint(x: start + slant, y: 0.0))
                path.addLine(to: CGPoint(x: start + slant + stripe, y: 0.0))
                path.addLine(to: CGPoint(x: start + stripe, y: canvasHeight))
                path.closeSubpath()
                context.fill(path, with: .color(tint))
                start += spacing
            }
        }
        .frame(height: height)
        .background(EndfieldPalette.bgPrimary)
        .clipped()
        .accessibilityHidden(true)
    }
}

// MARK: - 4. Cruces de retícula

/// Cuatro cruces `+` de 6 pt en las esquinas de un panel.
public struct TacticalCornerCrosses: View {
    private var crossSize: CGFloat
    public var inset: CGFloat
    public var tint: Color

    public init(
        size: CGFloat = 6.0,
        inset: CGFloat = 4.0,
        tint: Color = EndfieldPalette.accentYellow.opacity(0.55)
    ) {
        self.crossSize = size
        self.inset = inset
        self.tint = tint
    }

    public var body: some View {
        // Una sola capa (`Canvas`) en vez de cuatro overlays con dos
        // rectángulos cada uno.
        let arm: CGFloat = max(crossSize, 2.0)
        let thickness: CGFloat = 1.0
        let edgeInset: CGFloat = inset
        let crossTint: Color = tint

        Canvas { context, size in
            let centers: [CGPoint] = [
                CGPoint(x: edgeInset + arm / 2.0, y: edgeInset + arm / 2.0),
                CGPoint(x: size.width - edgeInset - arm / 2.0, y: edgeInset + arm / 2.0),
                CGPoint(x: edgeInset + arm / 2.0, y: size.height - edgeInset - arm / 2.0),
                CGPoint(x: size.width - edgeInset - arm / 2.0, y: size.height - edgeInset - arm / 2.0)
            ]

            var path: Path = Path()
            for center in centers {
                path.addRect(
                    CGRect(
                        x: center.x - arm / 2.0,
                        y: center.y - thickness / 2.0,
                        width: arm,
                        height: thickness
                    )
                )
                path.addRect(
                    CGRect(
                        x: center.x - thickness / 2.0,
                        y: center.y - arm / 2.0,
                        width: thickness,
                        height: arm
                    )
                )
            }

            context.fill(path, with: .color(crossTint))
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

// MARK: - 5. Panel táctico

/// Contenedor brutalista: fondo carbón, esquinas cortadas, borde fino,
/// cruces de retícula en las esquinas y cabecera técnica opcional.
public struct TacticalPanel<Content: View>: View {
    private let code: String?
    private let title: String?
    private let accentBorder: Bool
    private let showsCorners: Bool
    private let contentPadding: CGFloat
    private let content: Content

    public init(
        code: String? = nil,
        title: String? = nil,
        accentBorder: Bool = false,
        showsCorners: Bool = true,
        contentPadding: CGFloat = EndfieldMetrics.contentPadding,
        @ViewBuilder content: () -> Content
    ) {
        self.code = code
        self.title = title
        self.accentBorder = accentBorder
        self.showsCorners = showsCorners
        self.contentPadding = contentPadding
        self.content = content()
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 0.0) {
            if let header: HeaderLine = headerLine {
                headerLineView(header)
            }

            content
                .padding(contentPadding)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        // Relleno con la forma angular en lugar de `.clipShape`: el contenido
        // siempre va dentro del padding, así que recortar solo añadía una
        // máscara fuera de pantalla por tarjeta (caro al hacer scroll).
        .background(ChamferedRectangle(cut: EndfieldMetrics.cornerCut).fill(EndfieldPalette.bgPanel))
        .overlay {
            ChamferedRectangle(cut: EndfieldMetrics.cornerCut)
                .stroke(borderColor, lineWidth: EndfieldMetrics.borderWidth)
        }
        .overlay {
            if showsCorners {
                TacticalCornerCrosses()
            }
        }
    }

    // MARK: Cabecera

    private struct HeaderLine {
        let code: String
        let title: String?
    }

    private var headerLine: HeaderLine? {
        let trimmedCode: String = (code ?? "").trimmingCharacters(in: .whitespaces)
        let trimmedTitle: String = (title ?? "").trimmingCharacters(in: .whitespaces)

        if trimmedCode.isEmpty && trimmedTitle.isEmpty { return nil }

        return HeaderLine(
            code: trimmedCode.isEmpty ? "//" : trimmedCode,
            title: trimmedTitle.isEmpty ? nil : trimmedTitle.uppercased()
        )
    }

    @ViewBuilder
    private func headerLineView(_ header: HeaderLine) -> some View {
        VStack(spacing: 6.0) {
            HStack(spacing: 7.0) {
                Text(header.code)
                    .font(EndfieldFont.label(9.0))
                    .tracking(1.2)
                    .foregroundStyle(accentBorder ? EndfieldPalette.accentYellow : EndfieldPalette.textSecondary)
                    .fixedSize()

                if let title: String = header.title {
                    Text("//")
                        .font(EndfieldFont.label(9.0))
                        .foregroundStyle(EndfieldPalette.textSecondary.opacity(0.5))

                    Text(title)
                        .font(EndfieldFont.label(9.0))
                        .tracking(1.2)
                        .foregroundStyle(EndfieldPalette.textSecondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }

                Spacer(minLength: 4.0)
            }
            .padding(.horizontal, contentPadding)
            .padding(.top, 9.0)

            Rectangle()
                .fill(borderColor)
                .frame(height: 1.0)
                .padding(.horizontal, contentPadding)
        }
        .padding(.bottom, 8.0)
    }

    private var borderColor: Color {
        return accentBorder ? EndfieldPalette.borderActive : EndfieldPalette.borderSubtle
    }
}

// MARK: - 6. Etiqueta compacta angular

public struct TacticalTagBadge: View {
    private let text: String
    private let tint: Color
    private let filled: Bool

    public init(text: String, tint: Color = EndfieldPalette.textSecondary, filled: Bool = false) {
        self.text = text
        self.tint = tint
        self.filled = filled
    }

    public var body: some View {
        Text(text.uppercased())
            .font(EndfieldFont.label(9.0))
            .tracking(1.2)
            .foregroundStyle(filled ? EndfieldPalette.bgPrimary : tint)
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .padding(.horizontal, 6.0)
            .padding(.vertical, 3.0)
            .background(
                ChamferedRectangle(cut: EndfieldMetrics.tightCut * 0.6)
                    .fill(filled ? tint : tint.opacity(0.10))
            )
            .overlay {
                ChamferedRectangle(cut: EndfieldMetrics.tightCut * 0.6)
                    .stroke(tint.opacity(filled ? 1.0 : 0.45), lineWidth: 1.0)
            }
    }
}

// MARK: - 7. Estilos de botón

/// Botón principal biselado en amarillo táctico con texto negro.
public struct EndfieldPrimaryButtonStyle: ButtonStyle {
    private let fullWidth: Bool
    private let compact: Bool

    public init(fullWidth: Bool = true, compact: Bool = false) {
        self.fullWidth = fullWidth
        self.compact = compact
    }

    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(EndfieldFont.mono(compact ? 11.0 : 13.0, weight: .heavy))
            .tracking(1.2)
            .foregroundStyle(EndfieldPalette.bgPrimary)
            .frame(maxWidth: fullWidth ? CGFloat.infinity : nil)
            .padding(.horizontal, compact ? 12.0 : 16.0)
            .padding(.vertical, compact ? 9.0 : 14.0)
            .background(
                ChamferedRectangle(cut: EndfieldMetrics.tightCut * 0.8)
                    .fill(EndfieldPalette.accentYellow.opacity(configuration.isPressed ? 0.72 : 1.0))
            )
            .overlay {
                ChamferedRectangle(cut: EndfieldMetrics.tightCut * 0.8)
                    .stroke(EndfieldPalette.accentYellow, lineWidth: 1.0)
            }
    }
}

/// Botón secundario con fondo transparente y borde fino blanco/amarillo.
public struct EndfieldSecondaryButtonStyle: ButtonStyle {
    private let fullWidth: Bool
    private let compact: Bool
    private let tint: Color

    public init(
        fullWidth: Bool = true,
        compact: Bool = false,
        tint: Color = EndfieldPalette.textPrimary
    ) {
        self.fullWidth = fullWidth
        self.compact = compact
        self.tint = tint
    }

    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(EndfieldFont.mono(compact ? 11.0 : 13.0, weight: .bold))
            .tracking(1.2)
            .foregroundStyle(tint)
            .frame(maxWidth: fullWidth ? CGFloat.infinity : nil)
            .padding(.horizontal, compact ? 12.0 : 16.0)
            .padding(.vertical, compact ? 9.0 : 13.0)
            .background(
                ChamferedRectangle(cut: EndfieldMetrics.tightCut * 0.8)
                    .fill(tint.opacity(configuration.isPressed ? 0.16 : 0.05))
            )
            .overlay {
                ChamferedRectangle(cut: EndfieldMetrics.tightCut * 0.8)
                    .stroke(tint.opacity(0.5), lineWidth: 1.0)
            }
    }
}

/// Botón cuadrado de icono (cajas técnicas de eliminar / equipamiento).
public struct EndfieldSquareButtonStyle: ButtonStyle {
    private let tint: Color
    private let size: CGFloat
    private let filled: Bool

    public init(
        tint: Color = EndfieldPalette.textPrimary,
        size: CGFloat = 30.0,
        filled: Bool = false
    ) {
        self.tint = tint
        self.size = size
        self.filled = filled
    }

    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(EndfieldFont.mono(12.0, weight: .bold))
            .foregroundStyle(filled ? EndfieldPalette.bgPrimary : tint)
            .frame(width: size, height: size)
            .background(
                ChamferedRectangle(cut: 3.0)
                    .fill(filled ? tint : EndfieldPalette.bgElevated)
            )
            .overlay {
                ChamferedRectangle(cut: 3.0)
                    .stroke(tint.opacity(filled ? 1.0 : 0.55), lineWidth: 1.0)
            }
            .opacity(configuration.isPressed ? 0.6 : 1.0)
    }
}

// MARK: - 8. Barra de energía segmentada

/// Barra de progreso lineal dividida en segmentos (estilo carga de energía).
public struct SegmentedProgressBar: View {
    private let progress: Double
    private let segments: Int
    private let tint: Color
    private let trackColor: Color
    private let height: CGFloat
    private let spacing: CGFloat

    public init(
        progress: Double,
        segments: Int = 24,
        tint: Color = EndfieldPalette.accentYellow,
        trackColor: Color = EndfieldPalette.bgElevated,
        height: CGFloat = 4.0,
        spacing: CGFloat = 2.0
    ) {
        self.progress = min(max(progress, 0.0), 1.0)
        self.segments = max(segments, 1)
        self.tint = tint
        self.trackColor = trackColor
        self.height = height
        self.spacing = spacing
    }

    public var body: some View {
        // Un único `Canvas` en lugar de N rectángulos apilados: la barra se
        // redibuja con un solo trazo por fotograma y no crea N vistas ni N
        // animaciones implícitas.
        let segmentCount: Int = segments
        let litCount: Int = litSegmentCount
        let gap: CGFloat = spacing
        let barHeight: CGFloat = height
        let litColor: Color = tint
        let emptyColor: Color = trackColor

        Canvas { context, size in
            let totalGap: CGFloat = gap * CGFloat(max(segmentCount - 1, 0))
            let available: CGFloat = max(0.0, size.width - totalGap)
            let segmentWidth: CGFloat = available / CGFloat(max(segmentCount, 1))
            let drawnHeight: CGFloat = min(barHeight, size.height)

            var index: Int = 0
            while index < segmentCount {
                let x: CGFloat = CGFloat(index) * (segmentWidth + gap)
                let rect: CGRect = CGRect(x: x, y: 0.0, width: segmentWidth, height: drawnHeight)
                context.fill(Path(rect), with: .color(index < litCount ? litColor : emptyColor))
                index += 1
            }
        }
        .frame(height: height)
        .frame(maxWidth: .infinity)
        .animation(.linear(duration: 0.2), value: progress)
        .accessibilityHidden(true)
    }

    private var litSegmentCount: Int {
        var count: Int = 0
        var index: Int = 0
        while index < segments {
            let threshold: Double = Double(index + 1) / Double(segments)
            if threshold <= progress + 0.0001 {
                count += 1
            }
            index += 1
        }
        return count
    }
}

// MARK: - 9. Desplegable técnico

/// Sustituto angular del `DisclosureGroup` con cabecera de código.
public struct EndfieldDisclosure<Content: View>: View {
    private let code: String
    private let title: String
    @Binding private var isExpanded: Bool
    private let content: Content

    public init(
        code: String,
        title: String,
        isExpanded: Binding<Bool>,
        @ViewBuilder content: () -> Content
    ) {
        self.code = code
        self.title = title
        self._isExpanded = isExpanded
        self.content = content()
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 0.0) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    isExpanded.toggle()
                }
            } label: {
                HStack(spacing: 8.0) {
                    Text(code)
                        .font(EndfieldFont.label(9.0))
                        .tracking(1.2)
                        .foregroundStyle(EndfieldPalette.accentYellow.opacity(0.85))
                        .fixedSize()

                    Text(title.uppercased())
                        .font(EndfieldFont.label(10.0))
                        .tracking(1.2)
                        .foregroundStyle(EndfieldPalette.textPrimary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)

                    Spacer(minLength: 4.0)

                    Text(isExpanded ? "–" : "+")
                        .font(EndfieldFont.mono(13.0, weight: .bold))
                        .foregroundStyle(EndfieldPalette.textSecondary)
                        .fixedSize()
                }
                .contentShape(Rectangle())
                .padding(.horizontal, 12.0)
                .padding(.vertical, 11.0)
            }
            .buttonStyle(.plain)

            if isExpanded {
                Rectangle()
                    .fill(EndfieldPalette.borderSubtle)
                    .frame(height: 1.0)

                content
                    .padding(12.0)
                    .transition(.opacity)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(ChamferedRectangle(cut: 8.0).fill(EndfieldPalette.bgPanel))
        .overlay {
            ChamferedRectangle(cut: 8.0)
                .stroke(EndfieldPalette.borderSubtle, lineWidth: 1.0)
        }
    }
}

// MARK: - 10. Indicador LIVE parpadeante

/// Punto cuadrado rojo que parpadea como indicador de señal en vivo.
public struct EndfieldLiveDot: View {
    private let size: CGFloat
    @State private var isDim: Bool = false

    public init(size: CGFloat = 6.0) {
        self.size = size
    }

    public var body: some View {
        Rectangle()
            .fill(EndfieldPalette.accentRed)
            .frame(width: size, height: size)
            .opacity(isDim ? 0.25 : 1.0)
            .onAppear {
                withAnimation(.easeInOut(duration: 0.55).repeatForever(autoreverses: true)) {
                    isDim = true
                }
            }
            .accessibilityHidden(true)
    }
}

// MARK: - 11. Cabecera técnica de sección

/// Título de sección con código numérico y línea de separación técnica.
public struct EndfieldSectionHeader: View {
    private let code: String
    private let title: String
    private let tint: Color

    public init(code: String, title: String, tint: Color = EndfieldPalette.textSecondary) {
        self.code = code
        self.title = title
        self.tint = tint
    }

    public var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8.0) {
            Text(code)
                .font(EndfieldFont.label(9.0))
                .tracking(1.2)
                .foregroundStyle(EndfieldPalette.accentYellow.opacity(0.85))
                .fixedSize()

            Text(title.uppercased())
                .font(EndfieldFont.label(10.0))
                .tracking(1.2)
                .foregroundStyle(EndfieldPalette.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.75)

            Rectangle()
                .fill(EndfieldPalette.borderSubtle)
                .frame(height: 1.0)
        }
        .accessibilityAddTraits(.isHeader)
    }
}

// MARK: - 12. Campo de texto técnico

/// Caja de entrada angular: fondo elevado, borde fino y tipografía
/// monoespaciada. Sustituye al `TextField` con borde redondeado del sistema.
public struct TacticalFieldModifier: ViewModifier {
    private let alignment: TextAlignment

    public init(alignment: TextAlignment = .leading) {
        self.alignment = alignment
    }

    public func body(content: Content) -> some View {
        content
            .font(EndfieldFont.mono(13.0, weight: .semibold))
            .foregroundStyle(EndfieldPalette.textPrimary)
            .tint(EndfieldPalette.accentYellow)
            .multilineTextAlignment(alignment)
            .textFieldStyle(.plain)
            .padding(.horizontal, 10.0)
            .padding(.vertical, 9.0)
            .background(
                ChamferedRectangle(cut: EndfieldMetrics.tightCut * 0.8)
                    .fill(EndfieldPalette.bgElevated)
            )
            .overlay {
                ChamferedRectangle(cut: EndfieldMetrics.tightCut * 0.8)
                    .stroke(EndfieldPalette.borderSubtle, lineWidth: 1.0)
            }
    }
}

public extension View {
    /// Aplica la caja de entrada angular de la identidad Endfield.
    func tacticalField(alignment: TextAlignment = .leading) -> some View {
        return modifier(TacticalFieldModifier(alignment: alignment))
    }
}

// MARK: - 13. Fila de ajuste numérico

/// Ajuste `−  valor  +` con estética de consola. Mantiene la semántica de
/// `Stepper` (rango y paso) pero con botones angulares propios.
public struct TacticalStepperRow: View {
    private let code: String
    private let title: String
    @Binding private var value: Int
    private let range: ClosedRange<Int>
    private let step: Int
    private let unit: String
    private let tint: Color

    public init(
        code: String,
        title: String,
        value: Binding<Int>,
        range: ClosedRange<Int>,
        step: Int = 1,
        unit: String = "",
        tint: Color = EndfieldPalette.accentYellow
    ) {
        self.code = code
        self.title = title
        self._value = value
        self.range = range
        self.step = max(1, step)
        self.unit = unit
        self.tint = tint
    }

    public var body: some View {
        HStack(spacing: 8.0) {
            VStack(alignment: .leading, spacing: 2.0) {
                Text(code)
                    .font(EndfieldFont.label(8.0))
                    .tracking(1.2)
                    .foregroundStyle(EndfieldPalette.textSecondary)
                    .lineLimit(1)

                Text(title)
                    .font(EndfieldFont.mono(11.0, weight: .semibold))
                    .foregroundStyle(EndfieldPalette.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }

            Spacer(minLength: 6.0)

            stepButton(systemName: "minus", action: decrease)
                .accessibilityLabel("Restar \(title)")

            Text("\(value)\(unit)")
                .font(EndfieldFont.mono(16.0, weight: .heavy))
                .monospacedDigit()
                .foregroundStyle(tint)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .frame(minWidth: 46.0)
                .contentTransition(.numericText())

            stepButton(systemName: "plus", action: increase)
                .accessibilityLabel("Sumar \(title)")
        }
        .padding(.horizontal, 9.0)
        .padding(.vertical, 7.0)
        .background(
            ChamferedRectangle(cut: EndfieldMetrics.tightCut * 0.8)
                .fill(EndfieldPalette.bgElevated)
        )
        .overlay {
            ChamferedRectangle(cut: EndfieldMetrics.tightCut * 0.8)
                .stroke(EndfieldPalette.borderSubtle, lineWidth: 1.0)
        }
        .accessibilityElement(children: .contain)
        .accessibilityValue("\(value)\(unit)")
    }

    private func stepButton(systemName: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(EndfieldFont.mono(12.0, weight: .heavy))
        }
        .buttonStyle(EndfieldSquareButtonStyle(tint: tint, size: 28.0))
    }

    private func decrease() {
        value = max(range.lowerBound, value - step)
    }

    private func increase() {
        value = min(range.upperBound, value + step)
    }
}
