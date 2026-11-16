import SwiftUI

// MARK: - Metrics

private enum EquipmentVisualizerMetrics {
    static let totalHeight: CGFloat = 150.0
    static let drawingHeight: CGFloat = 100.0
    static let maxPlateDiameter: CGFloat = 84.0
    static let minPlateDiameter: CGFloat = 24.0
    static let maxPlateThickness: CGFloat = 14.0
    static let minPlateThickness: CGFloat = 4.0
    static let plateSpacing: CGFloat = 1.5
}

// MARK: - Main visualizer

/// Visualización vectorial proporcional del equipamiento y los discos
/// necesarios para el peso indicado.
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
        VStack(spacing: 5) {
            drawing
                .frame(maxWidth: .infinity)
                .frame(height: EquipmentVisualizerMetrics.drawingHeight)

            legendView

            Text(PlateCalculatorService.breakdownText(for: result))
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity)
        .frame(height: EquipmentVisualizerMetrics.totalHeight)
        .background(Color.white.opacity(0.04))
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        )
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
                showsStops: true,
                label: "Barra Multipower: \(UserSettingsManager.formatted(equipmentType.baseWeight)) kg"
            )
        case .olympicBar:
            LoadedBarDrawingView(
                plates: result.platesPerSide,
                barThickness: 8.0,
                showsStops: false,
                label: "Barra Olímpica: \(UserSettingsManager.formatted(equipmentType.baseWeight)) kg"
            )
        case .ezBar:
            EZBarDrawingView(
                plates: result.platesPerSide,
                label: "Barra EZ: \(UserSettingsManager.formatted(equipmentType.baseWeight)) kg"
            )
        }
    }

    // MARK: Legend

    private var legendView: some View {
        let plates: [Double] = availablePlates

        return ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 5) {
                ForEach(plates.indices, id: \.self) { (index: Int) in
                    if index > 0 {
                        Text("·")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }

                    Text(UserSettingsManager.formatted(plates[index]))
                        .font(.caption2.bold())
                        .foregroundStyle(PlateCalculatorService.color(for: plates[index]))
                }
            }
            .frame(maxWidth: .infinity, alignment: .center)
        }
        .frame(height: 14)
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
        RoundedRectangle(cornerRadius: 2.0)
            .fill(PlateCalculatorService.color(for: weight))
            .frame(width: thickness, height: diameter)
            .overlay(
                RoundedRectangle(cornerRadius: 2.0)
                    .stroke(Color.gray.opacity(0.55), lineWidth: 0.8)
            )
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
        VStack(spacing: 0) {
            ZStack {
                Circle()
                    .fill(Color.gray.opacity(0.18))
                    .frame(width: 30.0, height: 30.0)

                Circle()
                    .stroke(Color.gray.opacity(0.75), lineWidth: 2.0)
                    .frame(width: 26.0, height: 26.0)

                Circle()
                    .fill(Color.gray.opacity(0.85))
                    .frame(width: 7.0, height: 7.0)
            }

            Rectangle()
                .fill(Color.gray.opacity(0.7))
                .frame(width: 2.0, height: 30.0)

            Capsule()
                .fill(Color.gray.opacity(0.9))
                .frame(width: 58.0, height: 7.0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
    }
}

// MARK: - Dumbbell

private struct DumbbellEquipmentDrawingView: View {
    var body: some View {
        HStack(alignment: .center, spacing: 3.0) {
            dumbbellBlock(width: 5.0, height: 26.0)
            dumbbellBlock(width: 7.0, height: 38.0)

            Capsule()
                .fill(Color.gray.opacity(0.75))
                .frame(width: 62.0, height: 9.0)

            dumbbellBlock(width: 7.0, height: 38.0)
            dumbbellBlock(width: 5.0, height: 26.0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
    }

    private func dumbbellBlock(width: CGFloat, height: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: 2.0)
            .fill(Color.gray.opacity(0.75))
            .frame(width: width, height: height)
            .overlay(
                RoundedRectangle(cornerRadius: 2.0)
                    .stroke(Color.gray.opacity(0.4), lineWidth: 0.8)
            )
    }
}

// MARK: - Fixed bar

private struct FixedBarEquipmentDrawingView: View {
    var body: some View {
        HStack(alignment: .center, spacing: 4.0) {
            fixedBlock(width: 15.0, height: 44.0)

            Capsule()
                .fill(Color.gray.opacity(0.75))
                .frame(maxWidth: .infinity)
                .frame(height: 8.0)

            fixedBlock(width: 15.0, height: 44.0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        .padding(.horizontal, 12.0)
    }

    private func fixedBlock(width: CGFloat, height: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: 3.0)
            .fill(Color.gray.opacity(0.75))
            .frame(width: width, height: height)
            .overlay(
                RoundedRectangle(cornerRadius: 3.0)
                    .stroke(Color.gray.opacity(0.4), lineWidth: 0.8)
            )
    }
}

// MARK: - Plate-loaded machine

private struct PlateLoadedMachineDrawingView: View {
    let plates: [Double]

    var body: some View {
        ZStack {
            HStack(spacing: 0) {
                Capsule()
                    .fill(Color.gray.opacity(0.65))
                    .frame(height: 5.0)

                Spacer()
                    .frame(width: 76.0)

                Capsule()
                    .fill(Color.gray.opacity(0.65))
                    .frame(height: 5.0)
            }
            .padding(.horizontal, 8.0)

            HStack(alignment: .center, spacing: 2.0) {
                PlateStackView(plates: plates, mirrored: true)

                Spacer(minLength: 6.0)

                RoundedRectangle(cornerRadius: 8.0)
                    .fill(Color.gray.opacity(0.22))
                    .frame(width: 76.0, height: 56.0)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8.0)
                            .stroke(Color.gray.opacity(0.5), lineWidth: 1.0)
                    )
                    .overlay(
                        Text("MÁQUINA")
                            .font(.system(size: 8.0, weight: .bold))
                            .foregroundStyle(.secondary)
                    )

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
    let label: String

    var body: some View {
        VStack(spacing: 4.0) {
            ZStack(alignment: .center) {
                Capsule()
                    .fill(Color.gray.opacity(0.75))
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
            .frame(height: 78.0)

            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
    }

    private var stopView: some View {
        RoundedRectangle(cornerRadius: 1.0)
            .fill(Color.gray.opacity(0.9))
            .frame(width: 3.0, height: 34.0)
    }
}

// MARK: - EZ bar

private struct EZBarDrawingView: View {
    let plates: [Double]
    let label: String

    var body: some View {
        VStack(spacing: 4.0) {
            HStack(alignment: .center, spacing: 2.0) {
                PlateStackView(plates: plates, mirrored: true)

                ZStack {
                    EZBarShape()
                        .stroke(
                            Color.gray.opacity(0.8),
                            style: StrokeStyle(lineWidth: 5.0, lineCap: .round, lineJoin: .round)
                        )
                        .frame(maxWidth: .infinity)
                        .frame(height: 28.0)

                    HStack {
                        Capsule()
                            .fill(Color.gray.opacity(0.8))
                            .frame(width: 14.0, height: 5.0)
                        Spacer(minLength: 0.0)
                        Capsule()
                            .fill(Color.gray.opacity(0.8))
                            .frame(width: 14.0, height: 5.0)
                    }
                }
                .frame(maxWidth: .infinity)

                PlateStackView(plates: plates, mirrored: false)
            }
            .frame(height: 78.0)

            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
    }
}

private struct EZBarShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()

        let middleY: CGFloat = rect.midY
        let amplitude: CGFloat = rect.height * 0.32
        let inset: CGFloat = 4.0
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

            let barColor: Color = Color.gray.opacity(0.8)
            let plateColor: Color = Color.green.opacity(0.85)

            switch type {
            case .cable:
                let pulleyRect = CGRect(x: width / 2.0 - 4.0, y: 2.0, width: 8.0, height: 8.0)
                var pulley = Path()
                pulley.addEllipse(in: pulleyRect)
                context.stroke(pulley, with: .color(barColor), lineWidth: 1.4)

                var cable = Path()
                cable.move(to: CGPoint(x: width / 2.0, y: 10.0))
                cable.addLine(to: CGPoint(x: width / 2.0, y: 17.0))
                context.stroke(cable, with: .color(barColor), lineWidth: 1.2)

                var handle = Path()
                handle.addRoundedRect(
                    in: CGRect(x: width / 2.0 - 6.0, y: 17.0, width: 12.0, height: 3.0),
                    cornerSize: CGSize(width: 1.5, height: 1.5)
                )
                context.fill(handle, with: .color(barColor))

            case .dumbbell:
                var handle = Path()
                handle.addRoundedRect(
                    in: CGRect(x: 8.0, y: middleY - 1.5, width: 12.0, height: 3.0),
                    cornerSize: CGSize(width: 1.0, height: 1.0)
                )
                context.fill(handle, with: .color(barColor))

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
                machine.addRoundedRect(
                    in: CGRect(x: 9.0, y: middleY - 6.0, width: 10.0, height: 12.0),
                    cornerSize: CGSize(width: 2.0, height: 2.0)
                )
                context.fill(machine, with: .color(Color.gray.opacity(0.35)))
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
                    style: StrokeStyle(lineWidth: 1.8, lineCap: .round, lineJoin: .round)
                )
                self.fillRect(context: &context, x: 4.0, y: middleY - 4.0, width: 2.0, height: 8.0, color: plateColor)
                self.fillRect(context: &context, x: 22.0, y: middleY - 4.0, width: 2.0, height: 8.0, color: plateColor)
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
