import SwiftUI
import UIKit

// MARK: - Accessibility Testing Utilities
struct AccessibilityAudit {
    
    // MARK: - Color Contrast Testing
    static func auditColorContrast(
        foreground: Color,
        background: Color,
        textSize: AccessibilityTextSize = .normal
    ) -> AccessibilityAuditResult {
        let meetsStandards = foreground.meetsAccessibilityStandards(with: background, for: textSize)
        let ratio = foreground.contrastRatio(with: background)
        
        return AccessibilityAuditResult(
            category: .colorContrast,
            passed: meetsStandards,
            message: meetsStandards ? 
                "✅ Color contrast ratio \(String(format: "%.2f", ratio)) meets WCAG standards" :
                "❌ Color contrast ratio \(String(format: "%.2f", ratio)) fails WCAG standards",
            severity: meetsStandards ? .pass : .error
        )
    }
    
    // MARK: - VoiceOver Testing
    static func auditVoiceOverSupport(for view: UIView) -> [AccessibilityAuditResult] {
        var results: [AccessibilityAuditResult] = []
        
        // Check if view has accessibility label
        if view.isAccessibilityElement {
            if view.accessibilityLabel?.isEmpty != false {
                results.append(AccessibilityAuditResult(
                    category: .voiceOver,
                    passed: false,
                    message: "❌ Accessibility element missing label",
                    severity: .error
                ))
            } else {
                results.append(AccessibilityAuditResult(
                    category: .voiceOver,
                    passed: true,
                    message: "✅ Accessibility label present",
                    severity: .pass
                ))
            }
            
            // Check for appropriate traits
            if view.accessibilityTraits.isEmpty {
                results.append(AccessibilityAuditResult(
                    category: .voiceOver,
                    passed: false,
                    message: "⚠️ Consider adding accessibility traits for better context",
                    severity: .warning
                ))
            }
        }
        
        // Recursively check subviews
        for subview in view.subviews {
            results.append(contentsOf: auditVoiceOverSupport(for: subview))
        }
        
        return results
    }
    
    // MARK: - Dynamic Type Testing
    static func auditDynamicTypeSupport() -> AccessibilityAuditResult {
        let contentSize = UIApplication.shared.preferredContentSizeCategory
        let isAccessibilitySize = contentSize.isAccessibilityCategory
        
        return AccessibilityAuditResult(
            category: .dynamicType,
            passed: true,
            message: isAccessibilitySize ? 
                "ℹ️ Currently using accessibility text size: \(contentSize.rawValue)" :
                "ℹ️ Currently using standard text size: \(contentSize.rawValue)",
            severity: .info
        )
    }
    
    // MARK: - Motion Reduction Testing
    static func auditMotionReduction() -> AccessibilityAuditResult {
        let reduceMotion = UIAccessibility.isReduceMotionEnabled
        
        return AccessibilityAuditResult(
            category: .motionReduction,
            passed: true,
            message: reduceMotion ? 
                "ℹ️ Reduce Motion is enabled - ensure animations respect this setting" :
                "ℹ️ Reduce Motion is disabled - animations should work normally",
            severity: .info
        )
    }
    
    // MARK: - Transparency Reduction Testing
    static func auditTransparencyReduction() -> AccessibilityAuditResult {
        let reduceTransparency = UIAccessibility.isReduceTransparencyEnabled
        
        return AccessibilityAuditResult(
            category: .transparencyReduction,
            passed: true,
            message: reduceTransparency ? 
                "ℹ️ Reduce Transparency is enabled - avoid transparent overlays" :
                "ℹ️ Reduce Transparency is disabled - transparency effects are okay",
            severity: .info
        )
    }
    
    // MARK: - Voice Control Testing
    static func auditVoiceControlSupport(for view: UIView) -> [AccessibilityAuditResult] {
        var results: [AccessibilityAuditResult] = []
        
        if view.isAccessibilityElement {
            // Check if interactive elements have appropriate voice control support
            if view.accessibilityTraits.contains(.button) || 
               view.accessibilityTraits.contains(.link) ||
               view.accessibilityTraits.contains(.adjustable) {
                
                if view.accessibilityLabel?.isEmpty != false {
                    results.append(AccessibilityAuditResult(
                        category: .voiceControl,
                        passed: false,
                        message: "❌ Interactive element missing voice control label",
                        severity: .error
                    ))
                } else {
                    results.append(AccessibilityAuditResult(
                        category: .voiceControl,
                        passed: true,
                        message: "✅ Interactive element has voice control support",
                        severity: .pass
                    ))
                }
            }
        }
        
        for subview in view.subviews {
            results.append(contentsOf: auditVoiceControlSupport(for: subview))
        }
        
        return results
    }
    
    // MARK: - Complete Audit
    static func performCompleteAudit(for view: UIView) -> AccessibilityAuditReport {
        var results: [AccessibilityAuditResult] = []
        
        // VoiceOver audit
        results.append(contentsOf: auditVoiceOverSupport(for: view))
        
        // Voice Control audit
        results.append(contentsOf: auditVoiceControlSupport(for: view))
        
        // Dynamic Type audit
        results.append(auditDynamicTypeSupport())
        
        // Motion reduction audit
        results.append(auditMotionReduction())
        
        // Transparency reduction audit
        results.append(auditTransparencyReduction())
        
        return AccessibilityAuditReport(results: results)
    }
}

// MARK: - Audit Result Models
struct AccessibilityAuditResult {
    let category: AccessibilityCategory
    let passed: Bool
    let message: String
    let severity: AccessibilitySeverity
}

struct AccessibilityAuditReport {
    let results: [AccessibilityAuditResult]
    
    var passedCount: Int {
        results.filter { $0.passed }.count
    }
    
    var failedCount: Int {
        results.filter { !$0.passed }.count
    }
    
    var warningCount: Int {
        results.filter { $0.severity == .warning }.count
    }
    
    var errorCount: Int {
        results.filter { $0.severity == .error }.count
    }
    
    var summary: String {
        """
        Accessibility Audit Summary:
        ✅ Passed: \(passedCount)
        ❌ Failed: \(failedCount)
        ⚠️ Warnings: \(warningCount)
        🚨 Errors: \(errorCount)
        """
    }
}

enum AccessibilityCategory {
    case voiceOver
    case voiceControl
    case dynamicType
    case colorContrast
    case motionReduction
    case transparencyReduction
    case switchControl
    case guidedAccess
}

enum AccessibilitySeverity {
    case pass
    case info
    case warning
    case error
}

// MARK: - Debug View for Accessibility Testing
#if DEBUG
struct AccessibilityDebugView: View {
    @State private var auditReport: AccessibilityAuditReport?
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Accessibility Debug Panel")
                .font(.headline)
                .fontWeight(.bold)
            
            Button("Run Accessibility Audit") {
                // This would need to be implemented to audit the current view hierarchy
                // For now, we'll create a sample report
                auditReport = AccessibilityAuditReport(results: [
                    AccessibilityAuditResult(
                        category: .voiceOver,
                        passed: true,
                        message: "✅ VoiceOver labels present",
                        severity: .pass
                    ),
                    AccessibilityAuditResult(
                        category: .dynamicType,
                        passed: true,
                        message: "ℹ️ Dynamic Type supported",
                        severity: .info
                    )
                ])
            }
            .padding()
            .background(Color.blue)
            .foregroundColor(.white)
            .cornerRadius(8)
            
            if let report = auditReport {
                ScrollView {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(report.summary)
                            .font(.subheadline)
                            .padding()
                            .background(Color.gray.opacity(0.1))
                            .cornerRadius(8)
                        
                        ForEach(Array(report.results.enumerated()), id: \.offset) { _, result in
                            Text(result.message)
                                .font(.caption)
                                .padding(.horizontal)
                        }
                    }
                }
                .frame(maxHeight: 200)
            }
            
            Spacer()
        }
        .padding()
    }
}
#endif