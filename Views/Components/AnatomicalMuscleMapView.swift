import SwiftUI

// MARK: - Rol de iluminación

/// Nivel de implicación de un músculo en el ejercicio actual.
enum MuscleHighlightRole {
    case inactive
    case secondary
    case primary

    static let accent: Color = Color(red: 1.0, green: 0.23, blue: 0.19)

    var fillColor: Color {
        switch self {
        case .inactive:
            return Color.white.opacity(0.08)
        case .secondary:
            return MuscleHighlightRole.accent.opacity(0.45)
        case .primary:
            return MuscleHighlightRole.accent
        }
    }

    var strokeColor: Color {
        switch self {
        case .inactive:
            return Color.white.opacity(0.18)
        case .secondary:
            return MuscleHighlightRole.accent.opacity(0.55)
        case .primary:
            return Color.white.opacity(0.6)
        }
    }

    var glowColor: Color {
        switch self {
        case .inactive:
            return Color.clear
        case .secondary:
            return MuscleHighlightRole.accent.opacity(0.25)
        case .primary:
            return MuscleHighlightRole.accent.opacity(0.8)
        }
    }

    var glowRadius: CGFloat {
        switch self {
        case .inactive:
            return 0.0
        case .secondary:
            return 3.0
        case .primary:
            return 6.0
        }
    }

    var legendColor: Color {
        switch self {
        case .inactive:
            return Color.white.opacity(0.3)
        case .secondary:
            return MuscleHighlightRole.accent.opacity(0.55)
        case .primary:
            return MuscleHighlightRole.accent
        }
    }
}

// MARK: - Formas anatómicas

/// Tipos de forma usados por los músculos del mapa.
enum AnatomicalMuscleShapeKind {
    case ellipse
    case capsule
    case roundedRect(cornerRadius: CGFloat)
    case polygon(points: [CGPoint])

    var shape: AnyShape {
        switch self {
        case .ellipse:
            return AnyShape(Ellipse())
        case .capsule:
            return AnyShape(Capsule())
        case .roundedRect(let cornerRadius):
            return AnyShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        case .polygon(let points):
            return AnyShape(NormalizedPolygonShape(points: points))
        }
    }
}

/// Polígono definido con puntos normalizados (0...1) dentro de su rectángulo.
struct NormalizedPolygonShape: Shape {
    let points: [CGPoint]

    func path(in rect: CGRect) -> Path {
        var path: Path = Path()
        guard let first: CGPoint = points.first else { return path }

        path.move(to: CGPoint(
            x: rect.minX + first.x * rect.width,
            y: rect.minY + first.y * rect.height
        ))

        for point in points.dropFirst() {
            path.addLine(to: CGPoint(
                x: rect.minX + point.x * rect.width,
                y: rect.minY + point.y * rect.height
            ))
        }

        path.closeSubpath()
        return path
    }
}

/// Músculo individual dibujado en el espacio de 120 x 240 puntos del cuerpo.
struct AnatomicalMuscleItem: Identifiable {
    let id: String
    let muscle: MuscleGroup
    let kind: AnatomicalMuscleShapeKind
    let rect: CGRect
    let rotationDegrees: Double
}

/// Silueta de un músculo con su iluminación según el rol.
struct MuscleShapeView: View {
    let shape: AnyShape
    let role: MuscleHighlightRole

    var body: some View {
        shape
            .fill(role.fillColor)
            .overlay {
                shape.stroke(role.strokeColor, lineWidth: 0.8)
            }
            .shadow(color: role.glowColor, radius: role.glowRadius)
    }
}

// MARK: - Silueta neutra

/// Cuerpo base limpio (cabeza, torso, brazos y piernas) sobre el que se
/// superponen los músculos iluminados.
struct NeutralBodySilhouetteView: View {
    private let fillColor: Color = Color.white.opacity(0.06)
    private let strokeColor: Color = Color.white.opacity(0.14)

    private let torsoPoints: [CGPoint] = [
        CGPoint(x: 0.12, y: 0.00),
        CGPoint(x: 0.88, y: 0.00),
        CGPoint(x: 0.94, y: 0.18),
        CGPoint(x: 0.78, y: 0.55),
        CGPoint(x: 0.84, y: 1.00),
        CGPoint(x: 0.16, y: 1.00),
        CGPoint(x: 0.22, y: 0.55),
        CGPoint(x: 0.06, y: 0.18)
    ]

    var body: some View {
        ZStack {
            Ellipse()
                .fill(fillColor)
                .overlay { Ellipse().stroke(strokeColor, lineWidth: 0.8) }
                .frame(width: 26.0, height: 30.0)
                .position(x: 60.0, y: 22.0)

            RoundedRectangle(cornerRadius: 3.0)
                .fill(fillColor)
                .overlay { RoundedRectangle(cornerRadius: 3.0).stroke(strokeColor, lineWidth: 0.8) }
                .frame(width: 13.0, height: 12.0)
                .position(x: 60.0, y: 40.0)

            NormalizedPolygonShape(points: torsoPoints)
                .fill(fillColor)
                .overlay { NormalizedPolygonShape(points: torsoPoints).stroke(strokeColor, lineWidth: 0.8) }
                .frame(width: 56.0, height: 106.0)
                .position(x: 60.0, y: 95.0)

            bodyLimb(width: 16.0, height: 54.0, x: 24.0, y: 73.0, rotation: 7.0)
            bodyLimb(width: 16.0, height: 54.0, x: 96.0, y: 73.0, rotation: -7.0)
            bodyLimb(width: 14.0, height: 56.0, x: 15.0, y: 122.0, rotation: 4.0)
            bodyLimb(width: 14.0, height: 56.0, x: 105.0, y: 122.0, rotation: -4.0)

            bodyLimb(width: 20.0, height: 58.0, x: 46.0, y: 165.0, rotation: 0.0)
            bodyLimb(width: 20.0, height: 58.0, x: 74.0, y: 165.0, rotation: 0.0)
            bodyLimb(width: 16.0, height: 44.0, x: 46.0, y: 212.0, rotation: 0.0)
            bodyLimb(width: 16.0, height: 44.0, x: 74.0, y: 212.0, rotation: 0.0)
        }
        .frame(width: 120.0, height: 240.0)
    }

    private func bodyLimb(width: CGFloat, height: CGFloat, x: CGFloat, y: CGFloat, rotation: Double) -> some View {
        Capsule()
            .fill(fillColor)
            .overlay { Capsule().stroke(strokeColor, lineWidth: 0.8) }
            .frame(width: width, height: height)
            .rotationEffect(.degrees(rotation))
            .position(x: x, y: y)
    }
}

// MARK: - Vista frontal

struct FrontHumanSilhouetteView: View {
    let role: (MuscleGroup) -> MuscleHighlightRole

    var body: some View {
        ZStack {
            NeutralBodySilhouetteView()

            ForEach(FrontHumanSilhouetteView.muscleItems) { (item: AnatomicalMuscleItem) in
                MuscleShapeView(shape: item.kind.shape, role: role(item.muscle))
                    .frame(width: item.rect.width, height: item.rect.height)
                    .rotationEffect(.degrees(item.rotationDegrees))
                    .position(x: item.rect.midX, y: item.rect.midY)
            }
        }
        .frame(width: 120.0, height: 240.0)
        .accessibilityLabel("Vista frontal de los músculos implicados")
    }

    static let muscleItems: [AnatomicalMuscleItem] = [
        AnatomicalMuscleItem(id: "chest-l", muscle: .chest, kind: .roundedRect(cornerRadius: 8.0), rect: CGRect(x: 33.0, y: 48.0, width: 24.0, height: 22.0), rotationDegrees: 0.0),
        AnatomicalMuscleItem(id: "chest-r", muscle: .chest, kind: .roundedRect(cornerRadius: 8.0), rect: CGRect(x: 63.0, y: 48.0, width: 24.0, height: 22.0), rotationDegrees: 0.0),
        AnatomicalMuscleItem(id: "delt-l", muscle: .frontShoulders, kind: .ellipse, rect: CGRect(x: 24.0, y: 42.0, width: 22.0, height: 20.0), rotationDegrees: 0.0),
        AnatomicalMuscleItem(id: "delt-r", muscle: .frontShoulders, kind: .ellipse, rect: CGRect(x: 74.0, y: 42.0, width: 22.0, height: 20.0), rotationDegrees: 0.0),
        AnatomicalMuscleItem(id: "biceps-l", muscle: .biceps, kind: .capsule, rect: CGRect(x: 18.0, y: 62.0, width: 13.0, height: 30.0), rotationDegrees: 8.0),
        AnatomicalMuscleItem(id: "biceps-r", muscle: .biceps, kind: .capsule, rect: CGRect(x: 89.0, y: 62.0, width: 13.0, height: 30.0), rotationDegrees: -8.0),
        AnatomicalMuscleItem(id: "forearm-l", muscle: .forearms, kind: .capsule, rect: CGRect(x: 10.0, y: 94.0, width: 12.0, height: 34.0), rotationDegrees: 5.0),
        AnatomicalMuscleItem(id: "forearm-r", muscle: .forearms, kind: .capsule, rect: CGRect(x: 98.0, y: 94.0, width: 12.0, height: 34.0), rotationDegrees: -5.0),
        AnatomicalMuscleItem(id: "abs-1", muscle: .abs, kind: .roundedRect(cornerRadius: 4.0), rect: CGRect(x: 45.0, y: 74.0, width: 30.0, height: 11.0), rotationDegrees: 0.0),
        AnatomicalMuscleItem(id: "abs-2", muscle: .abs, kind: .roundedRect(cornerRadius: 4.0), rect: CGRect(x: 45.0, y: 87.0, width: 30.0, height: 11.0), rotationDegrees: 0.0),
        AnatomicalMuscleItem(id: "abs-3", muscle: .abs, kind: .roundedRect(cornerRadius: 4.0), rect: CGRect(x: 45.0, y: 100.0, width: 30.0, height: 11.0), rotationDegrees: 0.0),
        AnatomicalMuscleItem(id: "quads-l", muscle: .quads, kind: .capsule, rect: CGRect(x: 35.0, y: 148.0, width: 21.0, height: 44.0), rotationDegrees: 0.0),
        AnatomicalMuscleItem(id: "quads-r", muscle: .quads, kind: .capsule, rect: CGRect(x: 64.0, y: 148.0, width: 21.0, height: 44.0), rotationDegrees: 0.0),
        AnatomicalMuscleItem(id: "adductors-l", muscle: .adductors, kind: .capsule, rect: CGRect(x: 51.0, y: 154.0, width: 7.0, height: 34.0), rotationDegrees: 0.0),
        AnatomicalMuscleItem(id: "adductors-r", muscle: .adductors, kind: .capsule, rect: CGRect(x: 62.0, y: 154.0, width: 7.0, height: 34.0), rotationDegrees: 0.0),
        AnatomicalMuscleItem(id: "calves-l", muscle: .calves, kind: .capsule, rect: CGRect(x: 37.0, y: 192.0, width: 16.0, height: 40.0), rotationDegrees: 0.0),
        AnatomicalMuscleItem(id: "calves-r", muscle: .calves, kind: .capsule, rect: CGRect(x: 67.0, y: 192.0, width: 16.0, height: 40.0), rotationDegrees: 0.0)
    ]
}

// MARK: - Vista posterior

struct BackHumanSilhouetteView: View {
    let role: (MuscleGroup) -> MuscleHighlightRole

    private static let trapeziusPoints: [CGPoint] = [
        CGPoint(x: 0.50, y: 0.00),
        CGPoint(x: 0.96, y: 0.28),
        CGPoint(x: 0.78, y: 0.86),
        CGPoint(x: 0.50, y: 1.00),
        CGPoint(x: 0.22, y: 0.86),
        CGPoint(x: 0.04, y: 0.28)
    ]

    private static let latLeftPoints: [CGPoint] = [
        CGPoint(x: 0.95, y: 0.00),
        CGPoint(x: 1.00, y: 0.55),
        CGPoint(x: 0.55, y: 1.00),
        CGPoint(x: 0.12, y: 0.40),
        CGPoint(x: 0.45, y: 0.02)
    ]

    private static let latRightPoints: [CGPoint] = [
        CGPoint(x: 0.05, y: 0.00),
        CGPoint(x: 0.00, y: 0.55),
        CGPoint(x: 0.45, y: 1.00),
        CGPoint(x: 0.88, y: 0.40),
        CGPoint(x: 0.55, y: 0.02)
    ]

    var body: some View {
        ZStack {
            NeutralBodySilhouetteView()

            ForEach(BackHumanSilhouetteView.muscleItems) { (item: AnatomicalMuscleItem) in
                MuscleShapeView(shape: item.kind.shape, role: role(item.muscle))
                    .frame(width: item.rect.width, height: item.rect.height)
                    .rotationEffect(.degrees(item.rotationDegrees))
                    .position(x: item.rect.midX, y: item.rect.midY)
            }
        }
        .frame(width: 120.0, height: 240.0)
        .accessibilityLabel("Vista posterior de los músculos implicados")
    }

    static let muscleItems: [AnatomicalMuscleItem] = [
        AnatomicalMuscleItem(id: "trapezius", muscle: .upperBack, kind: .polygon(points: trapeziusPoints), rect: CGRect(x: 42.0, y: 44.0, width: 36.0, height: 32.0), rotationDegrees: 0.0),
        AnatomicalMuscleItem(id: "rear-delt-l", muscle: .rearShoulders, kind: .ellipse, rect: CGRect(x: 24.0, y: 42.0, width: 22.0, height: 20.0), rotationDegrees: 0.0),
        AnatomicalMuscleItem(id: "rear-delt-r", muscle: .rearShoulders, kind: .ellipse, rect: CGRect(x: 74.0, y: 42.0, width: 22.0, height: 20.0), rotationDegrees: 0.0),
        AnatomicalMuscleItem(id: "lat-l", muscle: .lats, kind: .polygon(points: latLeftPoints), rect: CGRect(x: 32.0, y: 68.0, width: 28.0, height: 52.0), rotationDegrees: 0.0),
        AnatomicalMuscleItem(id: "lat-r", muscle: .lats, kind: .polygon(points: latRightPoints), rect: CGRect(x: 60.0, y: 68.0, width: 28.0, height: 52.0), rotationDegrees: 0.0),
        AnatomicalMuscleItem(id: "triceps-l", muscle: .triceps, kind: .capsule, rect: CGRect(x: 18.0, y: 64.0, width: 13.0, height: 32.0), rotationDegrees: 8.0),
        AnatomicalMuscleItem(id: "triceps-r", muscle: .triceps, kind: .capsule, rect: CGRect(x: 89.0, y: 64.0, width: 13.0, height: 32.0), rotationDegrees: -8.0),
        AnatomicalMuscleItem(id: "lower-back", muscle: .lowerBack, kind: .roundedRect(cornerRadius: 6.0), rect: CGRect(x: 45.0, y: 104.0, width: 30.0, height: 26.0), rotationDegrees: 0.0),
        AnatomicalMuscleItem(id: "glutes-l", muscle: .glutes, kind: .roundedRect(cornerRadius: 11.0), rect: CGRect(x: 34.0, y: 132.0, width: 24.0, height: 26.0), rotationDegrees: 0.0),
        AnatomicalMuscleItem(id: "glutes-r", muscle: .glutes, kind: .roundedRect(cornerRadius: 11.0), rect: CGRect(x: 62.0, y: 132.0, width: 24.0, height: 26.0), rotationDegrees: 0.0),
        AnatomicalMuscleItem(id: "hamstrings-l", muscle: .hamstrings, kind: .capsule, rect: CGRect(x: 35.0, y: 158.0, width: 21.0, height: 42.0), rotationDegrees: 0.0),
        AnatomicalMuscleItem(id: "hamstrings-r", muscle: .hamstrings, kind: .capsule, rect: CGRect(x: 64.0, y: 158.0, width: 21.0, height: 42.0), rotationDegrees: 0.0),
        AnatomicalMuscleItem(id: "calves-l", muscle: .calves, kind: .capsule, rect: CGRect(x: 37.0, y: 200.0, width: 16.0, height: 32.0), rotationDegrees: 0.0),
        AnatomicalMuscleItem(id: "calves-r", muscle: .calves, kind: .capsule, rect: CGRect(x: 67.0, y: 200.0, width: 16.0, height: 32.0), rotationDegrees: 0.0)
    ]
}

// MARK: - Leyenda

struct MuscleMapLegendView: View {
    let primaryMuscles: [MuscleGroup]
    let secondaryMuscles: [MuscleGroup]

    private var highlightedMuscles: [MuscleGroup] {
        var result: [MuscleGroup] = []
        for muscle in primaryMuscles where !result.contains(muscle) {
            result.append(muscle)
        }
        for muscle in secondaryMuscles where !result.contains(muscle) {
            result.append(muscle)
        }
        return result
    }

    var body: some View {
        VStack(spacing: 6) {
            HStack(spacing: 14) {
                legendDot(color: MuscleHighlightRole.primary.legendColor, label: "Principal")
                legendDot(color: MuscleHighlightRole.secondary.legendColor, label: "Secundario")
            }

            if highlightedMuscles.isEmpty {
                Text("Sin músculos definidos para este ejercicio")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            } else {
                muscleNamesText
                    .font(.caption2.weight(.semibold))
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var muscleNamesText: Text {
        var output: Text = Text("")
        for (index, muscle) in highlightedMuscles.enumerated() {
            if index > 0 {
                output = output + Text("  ·  ").foregroundStyle(Color.white.opacity(0.25))
            }
            let role: MuscleHighlightRole = primaryMuscles.contains(muscle) ? .primary : .secondary
            output = output + Text(muscle.shortName).foregroundStyle(role.legendColor)
        }
        return output
    }

    private func legendDot(color: Color, label: String) -> some View {
        HStack(spacing: 5.0) {
            Circle()
                .fill(color)
                .frame(width: 7.0, height: 7.0)
            Text(label)
                .font(.caption2.weight(.medium))
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - Mapa completo

/// Mapa anatómico con vista frontal y posterior lado a lado.
struct AnatomicalMuscleMapView: View {
    let primaryMuscles: [MuscleGroup]
    let secondaryMuscles: [MuscleGroup]

    var body: some View {
        VStack(spacing: 12.0) {
            HStack(alignment: .top, spacing: 0.0) {
                silhouetteColumn(title: "FRONTAL", isFront: true)
                silhouetteColumn(title: "POSTERIOR", isFront: false)
            }

            MuscleMapLegendView(
                primaryMuscles: primaryMuscles,
                secondaryMuscles: secondaryMuscles
            )
        }
        .frame(maxWidth: .infinity)
    }

    private func silhouetteColumn(title: String, isFront: Bool) -> some View {
        VStack(spacing: 8.0) {
            Group {
                if isFront {
                    FrontHumanSilhouetteView(role: roleProvider)
                } else {
                    BackHumanSilhouetteView(role: roleProvider)
                }
            }
            .frame(height: 240.0)

            Text(title)
                .font(.system(size: 9.0, weight: .semibold))
                .tracking(2.0)
                .foregroundStyle(Color.white.opacity(0.45))
        }
        .frame(maxWidth: .infinity)
    }

    private var roleProvider: (MuscleGroup) -> MuscleHighlightRole {
        return { (muscle: MuscleGroup) -> MuscleHighlightRole in
            return highlightRole(for: muscle)
        }
    }

    private func highlightRole(for muscle: MuscleGroup) -> MuscleHighlightRole {
        if primaryMuscles.contains(muscle) {
            return .primary
        }
        if secondaryMuscles.contains(muscle) {
            return .secondary
        }
        return .inactive
    }
}
