import SwiftUI

// MARK: - Metrics

private enum EquipmentVisualizerMetrics {
    static let totalHeight: CGFloat = 150.0
    static let drawingHeight: CGFloat = 82.0
    static let maxPlateDiameter: CGFloat = 66.0
    static let minPlateDiameter: CGFloat = 20.0
    static let maxPlateThickness: CGFloat = 12.0
    static let minPlateThickness: CGFloat = 4.0
    static let plateSpacing: CGFloat = 1.5
}

// MARK: - Main visualizer

/// Visualización vectorial proporcional del equipamiento y los discos
/// necesarios para el peso indicado, dentro de un visor técnico con líneas
/// de cota y etiquetas de telemetría.
struct EquipmentVisualizerView: View {
    let equipmentType: EquipmentType
    let weight: Double

    @AppStorage(UserSettingsManager.availablePlatesKey)
    private var availablePlatesRaw: String = UserSettingsManager.defaultAvailablePlates

    private var availablePlates: [Double] {
        return UserSettingsManager.parsePlates(availablePlatesRaw)
    }

    private var result: PlateCalculationResult {
        return PlateCalculatorService.calculate(
            totalWeight: weight,
            equipmentType: equipmentType,
            availablePlates: availablePlates
        )
    }

    var body: some View {
        VStack(spacing: 4.0) {
            telemetryHeader

            drawingFrame

            legendView

            Text(PlateCalculatorService.breakdownText(for: result).uppercased())
                .font(EndfieldFont.label(8.0))
                .tracking(0.8)
                .foregroundStyle(EndfieldPalette.textSecondary)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
        .padding(.horizontal, 8.0)
        .padding(.vertical, 7.0)
        .frame(maxWidth: .infinity)
        .frame(height: EquipmentVisualizerMetrics.totalHeight)
        .background(EndfieldPalette.bgPanel)
        .clipShape(ChamferedRectangle(cut: 8.0))
        .overlay {
            ChamferedRectangle(cut: 8.0)
                .stroke(EndfieldPalette.borderSubtle, lineWidth: 1.0)
        }
    }

    // MARK: Telemetry header

    private var telemetryHeader: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6.0) {
            Text(baseLoadText)
                .font(EndfieldFont.label(8.0))
                .tracking(1.0)
                .foregroundStyle(EndfieldPalette.accentCyan.opacity(0.85))
                .lineLimit(1)
                .minimumScaleFactor(0.7)

            Spacer(minLength: 2.0)

            Text(sideLabelText)
                .font(EndfieldFont.label(8.0))
                .tracking(1.0)
                .foregroundStyle(EndfieldPalette.textSecondary)
                .fixedSize()
        }
    }

    private var baseLoadText: String {
        let base: Double = equipmentType.baseWeight
        guard base > 0.0 else { return "BASE_LOAD // N/A" }
        return "BASE_LOAD // \(String(format: "%.1f", base)) KG"
    }

    private var sideLabelText: String {
        return equipmentType.usesPlates ? "PER_SIDE" : "TOTAL // \(Int(weight.rounded())) KG"
    }

    // MARK: Drawing frame

    private var drawingFrame: some View {
        ZStack {
            TechnicalGridOverlay(step: 11.0, lineColor: Color.white.opacity(0.05))

            drawing
                .padding(.horizontal, 6.0)
                .padding(.vertical, 4.0)

            DimensionLinesView()
        }
        .frame(maxWidth: .infinity)
        .frame(height: EquipmentVisualizerMetrics.drawingHeight)
        .clipped()
    }

    // MARK: Drawing selector

    @ViewBuilder
    private var drawing: some View {
        switch equipmentType {
        case .cable:
            CableEquipmentDrawingView()
        case .dumbbell:
            DumbbellEquipmentDrawingView()
        case .fixedBar:
            FixedBarEquipmentDrawingView()
        case .plateLoadedMachine:
            PlateLoadedMachineDrawingView(plates: result.platesPerSide)
        case .smithMachine:
            LoadedBarDrawingView(
                plates: result.platesPerSide,
                barThickness: 7.0,
                showsStops: true
            )
        case .olympicBar:
            LoadedBarDrawingView(
                plates: result.platesPerSide,
                barThickness: 8.0,
                showsStops: false
            )
        case .ezBar:
            EZBarDrawingView(plates: result.platesPerSide)
        case .bodyweight:
            BodyweightDrawingView()
        case .cardioMachine:
            CardioMachineDrawingView()
        }
    }

    // MARK: Legend

    private var legendView: some View {
        let plates: [Double] = availablePlates

        return ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 7.0) {
                ForEach(plates.indices, id: \.self) { (index: Int) in
                    plateLegendItem(weight: plates[index])
                }
            }
            .frame(maxWidth: .infinity, alignment: .center)
        }
        .frame(height: 11.0)
    }

    private func plateLegendItem(weight plateWeight: Double) -> some View {
        HStack(spacing: 3.0) {
            Rectangle()
                .fill(PlateCalculatorService.color(for: plateWeight))
                .frame(width: 6.0, height: 6.0)
                .overlay {
                    Rectangle()
                        .stroke(Color.white.opacity(0.35), lineWidth: 0.5)
                }

            Text(UserSettingsManager.formatted(plateWeight))
                .font(EndfieldFont.label(8.0))
                .foregroundStyle(EndfieldPalette.textSecondary)
                .fixedSize()
        }
    }
}

// MARK: - Dimension lines

/// Líneas de cota sutiles con topes verticales en los extremos.
private struct DimensionLinesView: View {
    var body: some View {
        Canvas { context, size in
            let inset: CGFloat = 10.0
            let topY: CGFloat = 5.0
            let bottomY: CGFloat = max(6.0, size.height - 5.0)
            let tick: CGFloat = 3.0

            var path: Path = Path()
            path.move(to: CGPoint(x: inset, y: topY))
            path.addLine(to: CGPoint(x: size.width - inset, y: topY))
            path.move(to: CGPoint(x: inset, y: bottomY))
            path.addLine(to: CGPoint(x: size.width - inset, y: bottomY))

            path.move(to: CGPoint(x: inset, y: topY - tick))
            path.addLine(to: CGPoint(x: inset, y: topY + tick))
            path.move(to: CGPoint(x: size.width - inset, y: topY - tick))
            path.addLine(to: CGPoint(x: size.width - inset, y: topY + tick))
            path.move(to: CGPoint(x: inset, y: bottomY - tick))
            path.addLine(to: CGPoint(x: inset, y: bottomY + tick))
            path.move(to: CGPoint(x: size.width - inset, y: bottomY - tick))
            path.addLine(to: CGPoint(x: size.width - inset, y: bottomY + tick))

            context.stroke(path, with: .color(Color.white.opacity(0.10)), lineWidth: 0.8)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

// MARK: - Proportional plate

private struct PlateDiscView: View {
    let weight: Double

    private var normalizedWeight: CGFloat {
        let clamped: Double = min(max(weight, 0.5), 25.0)
        return CGFloat(clamped)
    }

    private var diameter: CGFloat {
        let span: CGFloat = EquipmentVisualizerMetrics.maxPlateDiameter - EquipmentVisualizerMetrics.minPlateDiameter
        return EquipmentVisualizerMetrics.minPlateDiameter + (normalizedWeight / 25.0) * span
    }

    private var thickness: CGFloat {
        let span: CGFloat = EquipmentVisualizerMetrics.maxPlateThickness - EquipmentVisualizerMetrics.minPlateThickness
        return EquipmentVisualizerMetrics.minPlateThickness + (normalizedWeight / 25.0) * span
    }

    var body: some View {
        Rectangle()
            .fill(PlateCalculatorService.color(for: weight))
            .frame(width: thickness, height: diameter)
            .overlay {
                Rectangle()
                    .stroke(Color.white.opacity(0.35), lineWidth: 0.8)
            }
            .accessibilityLabel("Disco de \(UserSettingsManager.formatted(weight)) kilos")
    }
}

private struct PlateStackView: View {
    let plates: [Double]
    let mirrored: Bool

    private var orderedPlates: [Double] {
        if mirrored {
            return Array(plates.reversed())
        }
        return plates
    }

    var body: some View {
        HStack(alignment: .center, spacing: EquipmentVisualizerMetrics.plateSpacing) {
            ForEach(orderedPlates.indices, id: \.self) { (index: Int) in
                PlateDiscView(weight: orderedPlates[index])
            }
        }
    }
}

// MARK: - Cable

private struct CableEquipmentDrawingView: View {
    var body: some View {
        VStack(spacing: 0.0) {
            ZStack {
                Rectangle()
                    .fill(Color.white.opacity(0.05))
                    .frame(width: 24.0, height: 24.0)

                Rectangle()
                    .stroke(Color.white.opacity(0.45), lineWidth: 1.2)
                    .frame(width: 24.0, height: 24.0)

                Rectangle()
                    .fill(EndfieldPalette.accentYellow.opacity(0.9))
                    .frame(width: 5.0, height: 5.0)
            }

            Rectangle()
                .fill(Color.white.opacity(0.45))
                .frame(width: 1.5, height: 22.0)

            Rectangle()
                .fill(Color.white.opacity(0.7))
                .frame(width: 50.0, height: 5.0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
    }
}

// MARK: - Dumbbell

private struct DumbbellEquipmentDrawingView: View {
    var body: some View {
        HStack(alignment: .center, spacing: 3.0) {
            dumbbellBlock(width: 5.0, height: 24.0)
            dumbbellBlock(width: 7.0, height: 36.0)

            Rectangle()
                .fill(Color.white.opacity(0.6))
                .frame(width: 50.0, height: 7.0)

            dumbbellBlock(width: 7.0, height: 36.0)
            dumbbellBlock(width: 5.0, height: 24.0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
    }

    private func dumbbellBlock(width: CGFloat, height: CGFloat) -> some View {
        Rectangle()
            .fill(Color.white.opacity(0.55))
            .frame(width: width, height: height)
            .overlay {
                Rectangle()
                    .stroke(Color.white.opacity(0.25), lineWidth: 0.8)
            }
    }
}

// MARK: - Fixed bar

private struct FixedBarEquipmentDrawingView: View {
    var body: some View {
        HStack(alignment: .center, spacing: 4.0) {
            fixedBlock(width: 13.0, height: 40.0)

            Rectangle()
                .fill(Color.white.opacity(0.6))
                .frame(maxWidth: .infinity)
                .frame(height: 6.0)

            fixedBlock(width: 13.0, height: 40.0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        .padding(.horizontal, 10.0)
    }

    private func fixedBlock(width: CGFloat, height: CGFloat) -> some View {
        Rectangle()
            .fill(Color.white.opacity(0.55))
            .frame(width: width, height: height)
            .overlay {
                Rectangle()
                    .stroke(Color.white.opacity(0.25), lineWidth: 0.8)
            }
    }
}

// MARK: - Plate-loaded machine

private struct PlateLoadedMachineDrawingView: View {
    let plates: [Double]

    var body: some View {
        ZStack {
            HStack(spacing: 0.0) {
                Rectangle()
                    .fill(Color.white.opacity(0.4))
                    .frame(height: 3.0)

                Spacer()
                    .frame(width: 64.0)

                Rectangle()
                    .fill(Color.white.opacity(0.4))
                    .frame(height: 3.0)
            }
            .padding(.horizontal, 8.0)

            HStack(alignment: .center, spacing: 2.0) {
                PlateStackView(plates: plates, mirrored: true)

                Spacer(minLength: 6.0)

                ZStack {
                    Rectangle()
                        .fill(Color.white.opacity(0.06))
                        .frame(width: 64.0, height: 46.0)

                    Rectangle()
                        .stroke(Color.white.opacity(0.35), lineWidth: 1.0)
                        .frame(width: 64.0, height: 46.0)

                    Text("MÁQUINA")
                        .font(EndfieldFont.label(7.0))
                        .tracking(1.0)
                        .foregroundStyle(EndfieldPalette.textSecondary)
                }

                Spacer(minLength: 6.0)

                PlateStackView(plates: plates, mirrored: false)
            }
            .padding(.horizontal, 6.0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
    }
}

// MARK: - Loaded bar (Multipower / Olympic)

private struct LoadedBarDrawingView: View {
    let plates: [Double]
    let barThickness: CGFloat
    let showsStops: Bool

    var body: some View {
        ZStack(alignment: .center) {
            Rectangle()
                .fill(Color.white.opacity(0.55))
                .frame(height: barThickness)
                .padding(.horizontal, 2.0)

            HStack(alignment: .center, spacing: 2.0) {
                PlateStackView(plates: plates, mirrored: true)

                if showsStops {
                    stopView
                }

                Spacer(minLength: 8.0)

                if showsStops {
                    stopView
                }

                PlateStackView(plates: plates, mirrored: false)
            }
            .padding(.horizontal, 6.0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
    }

    private var stopView: some View {
        Rectangle()
            .fill(Color.white.opacity(0.75))
            .frame(width: 2.0, height: 28.0)
    }
}

// MARK: - EZ bar

private struct EZBarDrawingView: View {
    let plates: [Double]

    var body: some View {
        HStack(alignment: .center, spacing: 2.0) {
            PlateStackView(plates: plates, mirrored: true)

            ZStack {
                EZBarShape()
                    .stroke(
                        Color.white.opacity(0.55),
                        style: StrokeStyle(lineWidth: 4.0, lineCap: .square, lineJoin: .miter)
                    )
                    .frame(maxWidth: .infinity)
                    .frame(height: 24.0)

                HStack {
                    Rectangle()
                        .fill(Color.white.opacity(0.6))
                        .frame(width: 12.0, height: 3.0)

                    Spacer(minLength: 0.0)

                    Rectangle()
                        .fill(Color.white.opacity(0.6))
                        .frame(width: 12.0, height: 3.0)
                }
            }
            .frame(maxWidth: .infinity)

            PlateStackView(plates: plates, mirrored: false)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
    }
}

private struct EZBarShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()

        let middleY: CGFloat = rect.midY
        let amplitude: CGFloat = rect.height * 0.30
        let inset: CGFloat = 2.0
        let left: CGFloat = rect.minX + inset
        let right: CGFloat = rect.maxX - inset
        let step: CGFloat = (right - left) / 6.0

        path.move(to: CGPoint(x: left, y: middleY))
        path.addLine(to: CGPoint(x: left + step, y: middleY - amplitude))
        path.addLine(to: CGPoint(x: left + step * 2.0, y: middleY + amplitude))
        path.addLine(to: CGPoint(x: left + step * 3.0, y: middleY - amplitude))
        path.addLine(to: CGPoint(x: left + step * 4.0, y: middleY + amplitude))
        path.addLine(to: CGPoint(x: left + step * 5.0, y: middleY - amplitude))
        path.addLine(to: CGPoint(x: right, y: middleY))

        return path
    }
}

// MARK: - Bodyweight

private struct BodyweightDrawingView: View {
    var body: some View {
        ZStack {
            Rectangle()
                .fill(Color.white.opacity(0.45))
                .frame(height: 3.0)
                .padding(.horizontal, 12.0)
                .offset(y: 28.0)

            HStack(spacing: 0.0) {
                Rectangle()
                    .fill(EndfieldPalette.accentYellow.opacity(0.85))
                    .frame(width: 10.0, height: 10.0)

                Rectangle()
                    .fill(Color.white.opacity(0.6))
                    .frame(width: 70.0, height: 7.0)

                Rectangle()
                    .fill(Color.white.opacity(0.55))
                    .frame(width: 4.0, height: 14.0)
                    .offset(y: 9.0)
            }
            .offset(y: 16.0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
    }
}

// MARK: - Cardio machine

private struct CardioMachineDrawingView: View {
    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.white.opacity(0.55), lineWidth: 3.0)
                .frame(width: 32.0, height: 32.0)
                .offset(x: -24.0, y: 16.0)

            Rectangle()
                .fill(Color.white.opacity(0.5))
                .frame(width: 66.0, height: 3.0)
                .rotationEffect(.degrees(-16.0))
                .offset(x: 6.0, y: -8.0)

            Rectangle()
                .fill(Color.white.opacity(0.45))
                .frame(width: 46.0, height: 3.0)
                .offset(x: 10.0, y: 28.0)

            Rectangle()
                .fill(EndfieldPalette.accentYellow.opacity(0.85))
                .frame(width: 10.0, height: 3.0)
                .offset(x: 34.0, y: -20.0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
    }
}

// MARK: - Compact icon

/// Icono compacto (28 x 24 pt) que resume visualmente cada equipamiento.
struct EquipmentSimplifiedIconView: View {
    let equipmentType: EquipmentType

    var body: some View {
        Canvas { context, size in
            let width: CGFloat = size.width
            let height: CGFloat = size.height
            let middleY: CGFloat = height / 2.0
            let type: EquipmentType = self.equipmentType

            let barColor: Color = Color.white.opacity(0.75)
            let plateColor: Color = EndfieldPalette.accentYellow.opacity(0.9)

            switch type {
            case .cable:
                let pulleyRect = CGRect(x: width / 2.0 - 4.0, y: 2.0, width: 8.0, height: 8.0)
                var pulley = Path()
                pulley.addRect(pulleyRect)
                context.stroke(pulley, with: .color(barColor), lineWidth: 1.2)

                var cable = Path()
                cable.move(to: CGPoint(x: width / 2.0, y: 10.0))
                cable.addLine(to: CGPoint(x: width / 2.0, y: 17.0))
                context.stroke(cable, with: .color(barColor), lineWidth: 1.2)

                self.fillRect(context: &context, x: width / 2.0 - 6.0, y: 17.0, width: 12.0, height: 3.0, color: barColor)

            case .dumbbell:
                self.fillRect(context: &context, x: 8.0, y: middleY - 1.5, width: 12.0, height: 3.0, color: barColor)
                self.fillRect(context: &context, x: 4.0, y: middleY - 6.0, width: 3.0, height: 12.0, color: barColor)
                self.fillRect(context: &context, x: 1.0, y: middleY - 4.0, width: 2.0, height: 8.0, color: barColor)
                self.fillRect(context: &context, x: 21.0, y: middleY - 6.0, width: 3.0, height: 12.0, color: barColor)
                self.fillRect(context: &context, x: 25.0, y: middleY - 4.0, width: 2.0, height: 8.0, color: barColor)

            case .fixedBar:
                self.strokeLine(context: &context, x1: 2.0, y1: middleY, x2: 26.0, y2: middleY, color: barColor, lineWidth: 2.0)
                self.fillRect(context: &context, x: 4.0, y: middleY - 5.0, width: 4.0, height: 10.0, color: barColor)
                self.fillRect(context: &context, x: 20.0, y: middleY - 5.0, width: 4.0, height: 10.0, color: barColor)

            case .plateLoadedMachine:
                self.strokeLine(context: &context, x1: 2.0, y1: middleY, x2: 9.0, y2: middleY, color: barColor, lineWidth: 1.5)
                self.strokeLine(context: &context, x1: 19.0, y1: middleY, x2: 26.0, y2: middleY, color: barColor, lineWidth: 1.5)
                self.fillRect(context: &context, x: 4.0, y: middleY - 4.0, width: 2.0, height: 8.0, color: plateColor)
                self.fillRect(context: &context, x: 22.0, y: middleY - 4.0, width: 2.0, height: 8.0, color: plateColor)

                var machine = Path()
                machine.addRect(CGRect(x: 9.0, y: middleY - 6.0, width: 10.0, height: 12.0))
                context.fill(machine, with: .color(Color.white.opacity(0.10)))
                context.stroke(machine, with: .color(barColor), lineWidth: 1.0)

            case .smithMachine:
                self.strokeLine(context: &context, x1: 2.0, y1: middleY, x2: 26.0, y2: middleY, color: barColor, lineWidth: 1.8)
                self.fillRect(context: &context, x: 5.0, y: middleY - 5.0, width: 2.0, height: 10.0, color: plateColor)
                self.fillRect(context: &context, x: 8.0, y: middleY - 4.0, width: 2.0, height: 8.0, color: plateColor)
                self.fillRect(context: &context, x: 21.0, y: middleY - 5.0, width: 2.0, height: 10.0, color: plateColor)
                self.fillRect(context: &context, x: 18.0, y: middleY - 4.0, width: 2.0, height: 8.0, color: plateColor)

            case .olympicBar:
                self.strokeLine(context: &context, x1: 1.0, y1: middleY, x2: 27.0, y2: middleY, color: barColor, lineWidth: 1.8)
                self.fillRect(context: &context, x: 5.0, y: middleY - 5.5, width: 2.5, height: 11.0, color: plateColor)
                self.fillRect(context: &context, x: 20.5, y: middleY - 5.5, width: 2.5, height: 11.0, color: plateColor)

            case .ezBar:
                var path = Path()
                let left: CGFloat = 8.0
                let right: CGFloat = 20.0
                let step: CGFloat = (right - left) / 4.0
                let amplitude: CGFloat = 3.0
                path.move(to: CGPoint(x: 3.0, y: middleY))
                path.addLine(to: CGPoint(x: left, y: middleY))
                path.addLine(to: CGPoint(x: left + step, y: middleY - amplitude))
                path.addLine(to: CGPoint(x: left + step * 2.0, y: middleY + amplitude))
                path.addLine(to: CGPoint(x: left + step * 3.0, y: middleY - amplitude))
                path.addLine(to: CGPoint(x: right, y: middleY))
                path.addLine(to: CGPoint(x: 25.0, y: middleY))
                context.stroke(
                    path,
                    with: .color(barColor),
                    style: StrokeStyle(lineWidth: 1.6, lineCap: .square, lineJoin: .miter)
                )
                self.fillRect(context: &context, x: 4.0, y: middleY - 4.0, width: 2.0, height: 8.0, color: plateColor)
                self.fillRect(context: &context, x: 22.0, y: middleY - 4.0, width: 2.0, height: 8.0, color: plateColor)

            case .bodyweight:
                self.fillRect(context: &context, x: 3.0, y: height - 5.0, width: 22.0, height: 2.0, color: barColor)
                self.fillRect(context: &context, x: 5.0, y: height / 2.0 - 6.0, width: 16.0, height: 4.0, color: barColor)
                self.fillRect(context: &context, x: 19.0, y: height / 2.0 - 2.0, width: 3.0, height: 7.0, color: plateColor)

            case .cardioMachine:
                var wheel = Path()
                wheel.addEllipse(in: CGRect(x: 2.0, y: middleY - 2.0, width: 12.0, height: 12.0))
                context.stroke(wheel, with: .color(barColor), lineWidth: 1.4)
                self.strokeLine(context: &context, x1: 2.0, y1: 21.0, x2: 26.0, y2: 21.0, color: barColor, lineWidth: 1.4)
                self.strokeLine(context: &context, x1: 10.0, y1: middleY + 8.0, x2: 21.0, y2: 7.0, color: barColor, lineWidth: 1.6)
                self.fillRect(context: &context, x: 19.0, y: 4.0, width: 6.0, height: 2.0, color: plateColor)
            }
        }
        .frame(width: 28.0, height: 24.0)
        .accessibilityLabel(equipmentType.rawValue)
    }

    // MARK: Canvas helpers

    private func fillRect(
        context: inout GraphicsContext,
        x: CGFloat,
        y: CGFloat,
        width: CGFloat,
        height: CGFloat,
        color: Color
    ) {
        var path = Path()
        path.addRect(CGRect(x: x, y: y, width: width, height: height))
        context.fill(path, with: .color(color))
    }

    private func strokeLine(
        context: inout GraphicsContext,
        x1: CGFloat,
        y1: CGFloat,
        x2: CGFloat,
        y2: CGFloat,
        color: Color,
        lineWidth: CGFloat
    ) {
        var path = Path()
        path.move(to: CGPoint(x: x1, y: y1))
        path.addLine(to: CGPoint(x: x2, y: y2))
        context.stroke(path, with: .color(color), lineWidth: lineWidth)
    }
}
