import SwiftUI

// MARK: - Motion and Animation Accessibility
extension View {
    
    /// Conditionally applies animation based on user's reduce motion preference
    func accessibleAnimation<V: Equatable>(
        _ animation: Animation? = .default,
        value: V,
        fallback: Animation? = nil
    ) -> some View {
        self.modifier(AccessibleAnimationModifier(animation: animation, value: value, fallback: fallback))
    }
    
    /// Conditionally applies transition based on user's reduce motion preference
    func accessibleTransition(
        _ transition: AnyTransition,
        fallback: AnyTransition = .identity
    ) -> some View {
        self.modifier(AccessibleTransitionModifier(transition: transition, fallback: fallback))
    }
    
    /// Conditionally shows visual effects based on accessibility preferences
    func accessibleVisualEffect<Content: View>(
        @ViewBuilder effect: @escaping () -> Content,
        @ViewBuilder fallback: @escaping () -> Content = { EmptyView() }
    ) -> some View {
        self.modifier(AccessibleVisualEffectModifier(effect: effect, fallback: fallback))
    }
}

struct AccessibleAnimationModifier<V: Equatable>: ViewModifier {
    @Environment(\.accessibilityReduceMotion) var reduceMotion
    
    let animation: Animation?
    let value: V
    let fallback: Animation?
    
    func body(content: Content) -> some View {
        if reduceMotion {
            content.animation(fallback, value: value)
        } else {
            content.animation(animation, value: value)
        }
    }
}

struct AccessibleTransitionModifier: ViewModifier {
    @Environment(\.accessibilityReduceMotion) var reduceMotion
    
    let transition: AnyTransition
    let fallback: AnyTransition
    
    func body(content: Content) -> some View {
        if reduceMotion {
            content.transition(fallback)
        } else {
            content.transition(transition)
        }
    }
}

struct AccessibleVisualEffectModifier<EffectContent: View, FallbackContent: View>: ViewModifier {
    @Environment(\.accessibilityReduceTransparency) var reduceTransparency
    @Environment(\.accessibilityReduceMotion) var reduceMotion
    
    let effect: () -> EffectContent
    let fallback: () -> FallbackContent
    
    func body(content: Content) -> some View {
        ZStack {
            content
            
            if !reduceTransparency && !reduceMotion {
                effect()
            } else {
                fallback()
            }
        }
    }
}

// MARK: - Haptic Feedback Accessibility
extension View {
    func accessibleHapticFeedback(
        _ style: UIImpactFeedbackGenerator.FeedbackStyle = .medium,
        condition: Bool = true
    ) -> some View {
        self.modifier(AccessibleHapticModifier(style: style, condition: condition))
    }
}

struct AccessibleHapticModifier: ViewModifier {
    let style: UIImpactFeedbackGenerator.FeedbackStyle
    let condition: Bool
    
    func body(content: Content) -> some View {
        content.onChange(of: condition) { _, newValue in
            if newValue && !UIAccessibility.isReduceMotionEnabled {
                HapticFeedback.impact(style)
            }
        }
    }
}

// MARK: - Voice Control Support
extension View {
    /// Adds voice control support with custom commands
    func voiceControlSupport(
        commands: [String],
        action: @escaping () -> Void
    ) -> some View {
        self.modifier(VoiceControlModifier(commands: commands, action: action))
    }
}

struct VoiceControlModifier: ViewModifier {
    let commands: [String]
    let action: () -> Void
    
    func body(content: Content) -> some View {
        content
            .accessibilityAction(named: "Activate") {
                action()
            }
            // Add custom accessibility actions for voice commands
            .accessibilityAction(named: commands.first ?? "Activate") {
                action()
            }
    }
}

// MARK: - Switch Control Support  
extension View {
    /// Optimizes view for Switch Control navigation
    func switchControlOptimized() -> some View {
        self.modifier(SwitchControlModifier())
    }
}

struct SwitchControlModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .accessibilityElement(children: .contain)
            .accessibilityAddTraits(.allowsDirectInteraction)
    }
}

// MARK: - Guided Access Support
extension View {
    /// Restricts interaction areas for Guided Access
    func guidedAccessRestricted(
        _ isRestricted: Bool = true
    ) -> some View {
        self.modifier(GuidedAccessModifier(isRestricted: isRestricted))
    }
}

struct GuidedAccessModifier: ViewModifier {
    let isRestricted: Bool
    
    func body(content: Content) -> some View {
        content
            .allowsHitTesting(!isRestricted || !UIAccessibility.isGuidedAccessEnabled)
            .opacity(isRestricted && UIAccessibility.isGuidedAccessEnabled ? 0.5 : 1.0)
    }
}