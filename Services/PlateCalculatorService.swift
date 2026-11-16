import Foundation
import SwiftUI

/// Resultado del reparto de discos por lado para un peso objetivo.
struct PlateCalculationResult {
    let platesPerSide: [Double]
    let barWeight: Double
    let achievedTotalWeight: Double
    let isExact: Bool

    static let empty = PlateCalculationResult(
        platesPerSide: [],
        barWeight: 0.0,
        achievedTotalWeight: 0.0,
        isExact: false
    )
}

/// Servicio de cálculo de discos por lado.
///
/// El algoritmo es voraz: parte del disco más pesado disponible y lo añade
/// mientras siga cabiendo en el objetivo por lado. La tolerancia evita errores
/// de coma flotante con discos como 1,25 kg.
enum PlateCalculatorService {
    static let tolerance: Double = 0.001

    // MARK: - Calculation

    static func calculate(
        totalWeight: Double,
        equipmentType: EquipmentType,
        availablePlates: [Double] = UserSettingsManager.availablePlates
    ) -> PlateCalculationResult {
        let baseWeight: Double = equipmentType.baseWeight
        let loadToDistribute: Double = max(0.0, totalWeight - baseWeight)
        let targetPerSide: Double = loadToDistribute / 2.0

        let sortedPlates: [Double] = availablePlates
            .filter { (plate: Double) -> Bool in
                return plate > 0.0
            }
            .sorted { (lhs: Double, rhs: Double) -> Bool in
                return lhs > rhs
            }

        var remaining: Double = targetPerSide
        var platesPerSide: [Double] = []

        for plate in sortedPlates {
            while remaining + tolerance >= plate {
                platesPerSide.append(plate)
                remaining -= plate
            }
        }

        let loadedPerSide: Double = platesPerSide.reduce(0.0) { (partial: Double, plate: Double) -> Double in
            return partial + plate
        }
        let achievedTotalWeight: Double = baseWeight + (loadedPerSide * 2.0)
        let isExact: Bool = abs(achievedTotalWeight - totalWeight) <= tolerance

        return PlateCalculationResult(
            platesPerSide: platesPerSide,
            barWeight: baseWeight,
            achievedTotalWeight: achievedTotalWeight,
            isExact: isExact
        )
    }

    // MARK: - Official plate colors

    static func colorHex(for plate: Double) -> String {
        let value: Double = plate

        if abs(value - 25.0) < 0.001 { return "#E53935" }
        if abs(value - 20.0) < 0.001 { return "#1E88E5" }
        if abs(value - 15.0) < 0.001 { return "#FDD835" }
        if abs(value - 10.0) < 0.001 { return "#43A047" }
        if abs(value - 5.0) < 0.001 { return "#F5F5F5" }
        if abs(value - 2.5) < 0.001 { return "#212121" }
        if abs(value - 2.0) < 0.001 { return "#FB8C00" }
        if abs(value - 1.5) < 0.001 { return "#8E24AA" }
        if abs(value - 1.25) < 0.001 { return "#9E9E9E" }
        if abs(value - 1.0) < 0.001 { return "#00ACC1" }
        if abs(value - 0.5) < 0.001 { return "#D81B60" }

        return "#757575"
    }

    static func color(for plate: Double) -> Color {
        return Color(hex: colorHex(for: plate))
    }

    // MARK: - Display helpers

    static func plateText(_ plates: [Double]) -> String {
        if plates.isEmpty {
            return "Solo barra"
        }
        let pieces: [String] = plates.map { (plate: Double) -> String in
            return UserSettingsManager.formatted(plate)
        }
        return pieces.joined(separator: " + ")
    }

    static func breakdownText(for result: PlateCalculationResult) -> String {
        if result.platesPerSide.isEmpty {
            return "Por lado: solo barra"
        }
        return "Por lado: \(plateText(result.platesPerSide)) kg"
    }

    static func achievedText(for result: PlateCalculationResult) -> String {
        let achieved: String = UserSettingsManager.formatted(result.achievedTotalWeight)
        if result.isExact {
            return "Total: \(achieved) kg"
        }
        return "Total aprox.: \(achieved) kg"
    }
}

// MARK: - Hex color helper

extension Color {
    init(hex: String) {
        let cleaned: String = hex
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "#", with: "")

        var value: UInt64 = 0
        _ = Scanner(string: cleaned).scanHexInt64(&value)

        let red: Double
        let green: Double
        let blue: Double
        let alpha: Double

        if cleaned.count == 8 {
            red = Double((value >> 24) & 0xFF) / 255.0
            green = Double((value >> 16) & 0xFF) / 255.0
            blue = Double((value >> 8) & 0xFF) / 255.0
            alpha = Double(value & 0xFF) / 255.0
        } else {
            red = Double((value >> 16) & 0xFF) / 255.0
            green = Double((value >> 8) & 0xFF) / 255.0
            blue = Double(value & 0xFF) / 255.0
            alpha = 1.0
        }

        self.init(
            .sRGB,
            red: red,
            green: green,
            blue: blue,
            opacity: alpha
        )
    }
}
