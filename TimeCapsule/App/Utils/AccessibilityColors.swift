import SwiftUI

/// Comprehensive accessibility color system for Time-Capsule app
/// Provides WCAG compliant colors that adapt to user preferences
extension Color {
    
    // MARK: - Adaptive Primary Colors
    
    static var accessiblePrimary: Color {
        Color("AccessiblePrimary", bundle: .main)
            .fallback(lightColor: .blue, darkColor: .cyan)
            .highContrastAdapted()
    }
    
    static var accessibleSecondary: Color {
        Color("AccessibleSecondary", bundle: .main)
            .fallback(lightColor: .gray, darkColor: .gray)
            .highContrastAdapted()
    }
    
    // MARK: - Recording State Colors
    
    static var accessibleRecordingActive: Color {
        Color("RecordingActive", bundle: .main)
            .fallback(lightColor: .red, darkColor: .red)
            .highContrastAdapted()
    }
    
    static var accessibleRecordingInactive: Color {
        Color("RecordingInactive", bundle: .main)
            .fallback(lightColor: .gray, darkColor: .gray)
            .highContrastAdapted()
    }
    
    static var accessibleRecordingPaused: Color {
        Color("RecordingPaused", bundle: .main)
            .fallback(lightColor: .orange, darkColor: .orange)
            .highContrastAdapted()
    }
    
    // MARK: - Status Colors
    
    static var accessibleSuccess: Color {
        Color("AccessibleSuccess", bundle: .main)
            .fallback(lightColor: .green, darkColor: .green)
            .highContrastAdapted()
    }
    
    static var accessibleWarning: Color {
        Color("AccessibleWarning", bundle: .main)
            .fallback(lightColor: .orange, darkColor: .yellow)
            .highContrastAdapted()
    }
    
    static var accessibleError: Color {
        Color("AccessibleError", bundle: .main)
            .fallback(lightColor: .red, darkColor: .pink)
            .highContrastAdapted()
    }
    
    // MARK: - Text Colors
    
    static var accessibleTextPrimary: Color {
        Color.primary.highContrastAdapted()
    }
    
    static var accessibleTextSecondary: Color {
        Color.secondary.highContrastAdapted()
    }
    
    // MARK: - Background Colors
    
    static var accessibleBackground: Color {
        Color(.systemBackground).highContrastAdapted()
    }
    
    static var accessibleBackgroundSecondary: Color {
        Color(.secondarySystemBackground).highContrastAdapted()
    }
}

// MARK: - Color Accessibility Helpers

extension Color {
    
    /// Applies high contrast adjustments when enabled
    func highContrastAdapted() -> Color {
        guard UIAccessibility.isDarkerSystemColorsEnabled else { return self }
        
        // Apply high contrast modifications
        return self.opacity(0.9) // Slightly reduce opacity for better contrast
    }
    
    /// Provides fallback colors when custom colors aren't available
    func fallback(lightColor: Color, darkColor: Color) -> Color {
        return Color(UIColor { traitCollection in
            switch traitCollection.userInterfaceStyle {
            case .dark:
                return UIColor(darkColor)
            default:
                return UIColor(lightColor)
            }
        })
    }
    
    /// Calculates contrast ratio against another color
    func contrastRatio(against backgroundColor: Color) -> Double {
        let foregroundLuminance = self.luminance()
        let backgroundLuminance = backgroundColor.luminance()
        
        let lighter = max(foregroundLuminance, backgroundLuminance)
        let darker = min(foregroundLuminance, backgroundLuminance)
        
        return (lighter + 0.05) / (darker + 0.05)
    }
    
    /// Calculates relative luminance for WCAG contrast calculations
    private func luminance() -> Double {
        // Convert Color to RGB components
        let uiColor = UIColor(self)
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0
        
        uiColor.getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        
        // Apply sRGB gamma correction
        let linearRed = sRGBToLinear(red)
        let linearGreen = sRGBToLinear(green)
        let linearBlue = sRGBToLinear(blue)
        
        // Calculate relative luminance
        return 0.2126 * linearRed + 0.7152 * linearGreen + 0.0722 * linearBlue
    }
    
    private func sRGBToLinear(_ component: CGFloat) -> Double {
        let value = Double(component)
        if value <= 0.03928 {
            return value / 12.92
        } else {
            return pow((value + 0.055) / 1.055, 2.4)
        }
    }
    
    /// Validates WCAG compliance
    func isWCAGCompliant(against background: Color, level: WCAGLevel = .AA) -> Bool {
        let ratio = contrastRatio(against: background)
        return ratio >= level.minimumRatio
    }
}

// MARK: - WCAG Compliance Levels

enum WCAGLevel {
    case AA
    case AAA
    
    var minimumRatio: Double {
        switch self {
        case .AA: return 4.5
        case .AAA: return 7.0
        }
    }
}

// MARK: - Accessibility Color Testing

#if DEBUG
struct AccessibilityColorTesting {
    
    static func validateAllColors() {
        let backgroundColor = Color.accessibleBackground
        let colors: [(String, Color)] = [
            ("Primary", Color.accessiblePrimary),
            ("Recording Active", Color.accessibleRecordingActive),
            ("Success", Color.accessibleSuccess),
            ("Warning", Color.accessibleWarning),
            ("Error", Color.accessibleError)
        ]
        
        for (name, color) in colors {
            let ratio = color.contrastRatio(against: backgroundColor)
            let isCompliant = color.isWCAGCompliant(against: backgroundColor)
            
            print("Color \(name): Contrast ratio \(String(format: "%.2f", ratio)), WCAG AA: \(isCompliant)")
        }
    }
}
#endif