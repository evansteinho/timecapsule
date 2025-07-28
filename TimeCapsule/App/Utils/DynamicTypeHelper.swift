import SwiftUI

extension Font {
    static func scaledFont(size: CGFloat, weight: Font.Weight = .regular, design: Font.Design = .default) -> Font {
        return .system(size: size, weight: weight, design: design)
    }
    
    // Predefined scaled fonts for common use cases
    static var scaledLargeTitle: Font {
        .system(.largeTitle, design: .default)
    }
    
    static var scaledTitle: Font {
        .system(.title, design: .default)
    }
    
    static var scaledTitle2: Font {
        .system(.title2, design: .default)
    }
    
    static var scaledTitle3: Font {
        .system(.title3, design: .default)
    }
    
    static var scaledHeadline: Font {
        .system(.headline, design: .default)
    }
    
    static var scaledBody: Font {
        .system(.body, design: .default)
    }
    
    static var scaledCallout: Font {
        .system(.callout, design: .default)
    }
    
    static var scaledSubheadline: Font {
        .system(.subheadline, design: .default)
    }
    
    static var scaledFootnote: Font {
        .system(.footnote, design: .default)
    }
    
    static var scaledCaption: Font {
        .system(.caption, design: .default)
    }
    
    static var scaledCaption2: Font {
        .system(.caption2, design: .default)
    }
}

extension View {
    func dynamicTypeSize(min: DynamicTypeSize = .xSmall, max: DynamicTypeSize = .xxxLarge) -> some View {
        self.modifier(DynamicTypeSizeModifier(min: min, max: max))
    }
    
    /// Applies appropriate dynamic type constraints for accessibility
    func accessibilityDynamicTypeSize() -> some View {
        self.dynamicTypeSize(min: .small, max: .accessibility5)
    }
    
    /// Constrains dynamic type for UI elements that must maintain fixed relationships
    func constrainedDynamicTypeSize() -> some View {
        self.dynamicTypeSize(min: .small, max: .xxLarge)
    }
    
    /// Helper for text that should support full accessibility sizing
    func fullAccessibilityTextSupport() -> some View {
        self.dynamicTypeSize(min: .xSmall, max: .accessibility5)
    }
}

struct DynamicTypeSizeModifier: ViewModifier {
    let min: DynamicTypeSize
    let max: DynamicTypeSize
    
    func body(content: Content) -> some View {
        content
            .dynamicTypeSize(min...max)
    }
}

struct ScaledMetric {
    private let metric: ScaledMetric<CGFloat>
    
    init(relativeTo textStyle: Font.TextStyle, baseValue: CGFloat) {
        self.metric = SwiftUI.ScaledMetric(relativeTo: textStyle)
        self.metric.wrappedValue = baseValue
    }
    
    var value: CGFloat {
        metric.wrappedValue
    }
}

extension ScaledMetric {
    static func size(relativeTo textStyle: Font.TextStyle = .body, baseValue: CGFloat) -> CGFloat {
        let metric = SwiftUI.ScaledMetric(relativeTo: textStyle)
        return metric.wrappedValue(for: baseValue)
    }
}

// MARK: - Dynamic Type Size Detection
struct DynamicTypeSizeReader: View {
    @Binding var sizeCategory: DynamicTypeSize
    
    var body: some View {
        GeometryReader { _ in
            Color.clear
                .onReceive(NotificationCenter.default.publisher(for: UIContentSizeCategory.didChangeNotification)) { _ in
                    sizeCategory = DynamicTypeSize(UIApplication.shared.preferredContentSizeCategory)
                }
        }
    }
}

extension DynamicTypeSize {
    init(_ category: UIContentSizeCategory) {
        switch category {
        case .extraSmall: self = .xSmall
        case .small: self = .small
        case .medium: self = .medium
        case .large: self = .large
        case .extraLarge: self = .xLarge
        case .extraExtraLarge: self = .xxLarge
        case .extraExtraExtraLarge: self = .xxxLarge
        case .accessibilityMedium: self = .accessibility1
        case .accessibilityLarge: self = .accessibility2
        case .accessibilityExtraLarge: self = .accessibility3
        case .accessibilityExtraExtraLarge: self = .accessibility4
        case .accessibilityExtraExtraExtraLarge: self = .accessibility5
        default: self = .large
        }
    }
    
    var isAccessibilitySize: Bool {
        switch self {
        case .accessibility1, .accessibility2, .accessibility3, .accessibility4, .accessibility5:
            return true
        default:
            return false
        }
    }
}