import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

// MARK: - Paleta táctica

/// Paleta estática de la identidad visual "Endfield":
/// negro mate profundo, gris carbón industrial, amarillo táctico, rojo alerta
/// y cian de telemetría. Todos los valores son `Color` explícitos.
public enum EndfieldPalette {
    public static let bgPrimary: Color = Color(hex: "#090A0C")
    public static let bgPanel: Color = Color(hex: "#111318")
    public static let bgElevated: Color = Color(hex: "#181C24")
    public static let accentYellow: Color = Color(hex: "#FFE600")
    public static let accentRed: Color = Color(hex: "#FF3B30")
    public static let accentCyan: Color = Color(hex: "#00E5FF")
    public static let textPrimary: Color = Color(hex: "#F2F4F7")
    public static let textSecondary: Color = Color(hex: "#8A93A2")
    public static let borderSubtle: Color = Color.white.opacity(0.14)
    public static let borderActive: Color = Color(hex: "#FFE600").opacity(0.65)

    /// Retícula táctica: trazo muy sutil sobre `bgPrimary`.
    public static let gridLine: Color = Color.white.opacity(0.035)
}

// MARK: - Métricas del sistema

public enum EndfieldMetrics {
    public static let cornerCut: CGFloat = 10.0
    public static let tightCut: CGFloat = 6.0
    public static let cellCut: CGFloat = 2.0
    public static let gridStep: CGFloat = 28.0
    public static let borderWidth: CGFloat = 1.0
    public static let contentPadding: CGFloat = 14.0
}

// MARK: - Tipografía técnica

public enum EndfieldFont {
    /// Fuente monoespaciada base del HUD.
    public static func mono(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        return Font.system(size: size, weight: weight, design: .monospaced)
    }

    /// Etiqueta de telemetría (mayúsculas + tracking aplicado en la vista).
    public static func label(_ size: CGFloat = 9.0, weight: Font.Weight = .bold) -> Font {
        return Font.system(size: size, weight: weight, design: .monospaced)
    }
}

// MARK: - Apariencia global de barras del sistema

/// Configura `UITabBar` y `UINavigationBar` con el fondo `#090A0C`, un borde
/// superior fino y el tint táctico `#FFE600`.
public enum EndfieldAppearance {
    public static func apply() {
        #if canImport(UIKit)
        let background: UIColor = UIColor(EndfieldPalette.bgPrimary)
        let accent: UIColor = UIColor(EndfieldPalette.accentYellow)
        let primary: UIColor = UIColor(EndfieldPalette.textPrimary)
        let secondary: UIColor = UIColor(EndfieldPalette.textSecondary)
        let hairline: UIColor = UIColor(white: 1.0, alpha: 0.12)

        let tabAppearance: UITabBarAppearance = UITabBarAppearance()
        tabAppearance.configureWithOpaqueBackground()
        tabAppearance.backgroundColor = background
        tabAppearance.shadowColor = hairline

        let normalFont: UIFont = UIFont.monospacedSystemFont(ofSize: 10.0, weight: .semibold)
        let selectedFont: UIFont = UIFont.monospacedSystemFont(ofSize: 10.0, weight: .bold)

        let stacked: UITabBarItemAppearance = tabAppearance.stackedLayoutAppearance
        stacked.normal.iconColor = secondary
        stacked.normal.titleTextAttributes = [
            .foregroundColor: secondary,
            .font: normalFont
        ]
        stacked.selected.iconColor = accent
        stacked.selected.titleTextAttributes = [
            .foregroundColor: accent,
            .font: selectedFont
        ]

        tabAppearance.inlineLayoutAppearance = stacked
        tabAppearance.compactInlineLayoutAppearance = stacked

        UITabBar.appearance().standardAppearance = tabAppearance
        UITabBar.appearance().scrollEdgeAppearance = tabAppearance
        UITabBar.appearance().tintColor = accent
        UITabBar.appearance().unselectedItemTintColor = secondary

        let navigationAppearance: UINavigationBarAppearance = UINavigationBarAppearance()
        navigationAppearance.configureWithOpaqueBackground()
        navigationAppearance.backgroundColor = background
        navigationAppearance.shadowColor = hairline
        navigationAppearance.titleTextAttributes = [
            .foregroundColor: primary,
            .font: UIFont.monospacedSystemFont(ofSize: 14.0, weight: .bold)
        ]
        navigationAppearance.largeTitleTextAttributes = [
            .foregroundColor: primary,
            .font: UIFont.monospacedSystemFont(ofSize: 24.0, weight: .heavy)
        ]

        UINavigationBar.appearance().standardAppearance = navigationAppearance
        UINavigationBar.appearance().compactAppearance = navigationAppearance
        UINavigationBar.appearance().scrollEdgeAppearance = navigationAppearance
        UINavigationBar.appearance().tintColor = accent
        #endif
    }
}
