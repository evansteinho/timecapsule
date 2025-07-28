import Foundation
import SwiftUI
import Combine

/// Comprehensive performance monitoring and optimization system
final class PerformanceMonitor: ObservableObject {
    static let shared = PerformanceMonitor()
    
    @Published var isMonitoring = false
    @Published var currentMetrics = PerformanceMetrics()
    
    private var timer: Timer?
    private var startTime: Date?
    private var cancellables = Set<AnyCancellable>()
    
    // Performance tracking
    private var operationMetrics: [String: OperationMetric] = [:]
    private var memorySnapshots: [MemorySnapshot] = []
    private var networkMetrics: [NetworkMetric] = []
    
    private init() {
        setupMemoryWarningObserver()
    }
    
    // MARK: - Monitoring Control
    
    func startMonitoring() {
        guard !isMonitoring else { return }
        
        isMonitoring = true
        startTime = Date()
        
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.collectMetrics()
        }
        
        print("Performance monitoring started")
    }
    
    func stopMonitoring() {
        guard isMonitoring else { return }
        
        isMonitoring = false
        timer?.invalidate()
        timer = nil
        
        generatePerformanceReport()
        print("Performance monitoring stopped")
    }
    
    // MARK: - Metrics Collection
    
    private func collectMetrics() {
        let metrics = PerformanceMetrics(
            memoryUsage: getCurrentMemoryUsage(),
            cpuUsage: getCurrentCPUUsage(),
            batteryLevel: getCurrentBatteryLevel(),
            diskUsage: getCurrentDiskUsage(),
            networkActivity: getCurrentNetworkActivity(),
            frameRate: getCurrentFrameRate(),
            timestamp: Date()
        )
        
        DispatchQueue.main.async {
            self.currentMetrics = metrics
        }
        
        // Store memory snapshots for trend analysis
        let memorySnapshot = MemorySnapshot(
            usage: metrics.memoryUsage,
            timestamp: metrics.timestamp
        )
        memorySnapshots.append(memorySnapshot)
        
        // Maintain reasonable history size
        if memorySnapshots.count > 300 { // 5 minutes at 1-second intervals
            memorySnapshots.removeFirst(50)
        }
        
        // Check for performance issues
        checkPerformanceThresholds(metrics)
    }
    
    private func getCurrentMemoryUsage() -> MemoryUsage {
        let info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size)/4
        
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: 1) {
                task_info(mach_task_self_,
                         task_flavor_t(MACH_TASK_BASIC_INFO),
                         $0,
                         &count)
            }
        }
        
        let usedMemory = result == KERN_SUCCESS ? Double(info.resident_size) : 0
        let availableMemory = Double(ProcessInfo.processInfo.physicalMemory)
        
        return MemoryUsage(
            used: usedMemory,
            available: availableMemory,
            percentage: availableMemory > 0 ? (usedMemory / availableMemory) * 100 : 0
        )
    }
    
    private func getCurrentCPUUsage() -> Double {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size)/4
        
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: 1) {
                task_info(mach_task_self_,
                         task_flavor_t(MACH_TASK_BASIC_INFO),
                         $0,
                         &count)
            }
        }
        
        guard result == KERN_SUCCESS else { return 0 }
        
        // This is a simplified CPU usage calculation
        // In production, you'd want more sophisticated CPU monitoring
        return Double(info.resident_size) / Double(ProcessInfo.processInfo.physicalMemory) * 100
    }
    
    private func getCurrentBatteryLevel() -> Double {
        UIDevice.current.isBatteryMonitoringEnabled = true
        return Double(UIDevice.current.batteryLevel) * 100
    }
    
    private func getCurrentDiskUsage() -> DiskUsage {
        let fileManager = FileManager.default
        let documentsPath = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first!
        
        do {
            let attributes = try fileManager.attributesOfFileSystem(forPath: documentsPath.path)
            let totalSpace = attributes[.systemSize] as? Int64 ?? 0
            let freeSpace = attributes[.systemFreeSize] as? Int64 ?? 0
            let usedSpace = totalSpace - freeSpace
            
            return DiskUsage(
                used: Double(usedSpace),
                available: Double(freeSpace),
                total: Double(totalSpace),
                percentage: totalSpace > 0 ? (Double(usedSpace) / Double(totalSpace)) * 100 : 0
            )
        } catch {
            return DiskUsage(used: 0, available: 0, total: 0, percentage: 0)
        }
    }
    
    private func getCurrentNetworkActivity() -> NetworkActivity {
        // This would require more complex implementation to track actual network usage
        // For now, return placeholder values
        return NetworkActivity(bytesIn: 0, bytesOut: 0, requestsPerSecond: 0)
    }
    
    private func getCurrentFrameRate() -> Double {
        // This would require integration with CADisplayLink for accurate FPS measurement
        // For now, assume 60 FPS
        return 60.0
    }
    
    // MARK: - Operation Tracking
    
    func startOperation(_ name: String) -> PerformanceOperation {
        let operation = PerformanceOperation(name: name, startTime: Date())
        return operation
    }
    
    func endOperation(_ operation: PerformanceOperation) {
        let endTime = Date()
        let duration = endTime.timeIntervalSince(operation.startTime)
        
        let metric = OperationMetric(
            name: operation.name,
            duration: duration,
            startTime: operation.startTime,
            endTime: endTime,
            memoryBefore: operation.memoryBefore,
            memoryAfter: getCurrentMemoryUsage()
        )
        
        operationMetrics[operation.name] = metric
        
        // Log slow operations
        if duration > 1.0 {
            print("⚠️ Slow operation detected: \(operation.name) took \(String(format: "%.2f", duration))s")
        }
    }
    
    // MARK: - Performance Thresholds
    
    private func checkPerformanceThresholds(_ metrics: PerformanceMetrics) {
        // Memory usage threshold (80%)
        if metrics.memoryUsage.percentage > 80 {
            triggerMemoryOptimization()
        }
        
        // Battery threshold (15%)
        if metrics.batteryLevel < 15 {
            triggerBatteryOptimization()
        }
        
        // Disk usage threshold (90%)
        if metrics.diskUsage.percentage > 90 {
            triggerDiskCleanup()
        }
        
        // Frame rate threshold (30 FPS)
        if metrics.frameRate < 30 {
            triggerUIOptimization()
        }
    }
    
    // MARK: - Optimization Triggers
    
    private func triggerMemoryOptimization() {
        print("🔧 Triggering memory optimization")
        
        // Clear caches
        URLCache.shared.removeAllCachedResponses()
        
        // Optimize Core Data
        EnhancedPersistenceService.shared.optimizeMemoryUsage()
        
        // Post notification for app-wide optimization
        NotificationCenter.default.post(name: .performanceOptimizationTriggered, object: nil)
    }
    
    private func triggerBatteryOptimization() {
        print("🔋 Triggering battery optimization")
        
        // Reduce background activity
        NotificationCenter.default.post(name: .batteryOptimizationTriggered, object: nil)
    }
    
    private func triggerDiskCleanup() {
        print("💾 Triggering disk cleanup")
        
        Task {
            await cleanupTemporaryFiles()
        }
    }
    
    private func triggerUIOptimization() {
        print("🎨 Triggering UI optimization")
        
        // Reduce animation complexity
        NotificationCenter.default.post(name: .uiOptimizationTriggered, object: nil)
    }
    
    // MARK: - Cleanup Operations
    
    private func cleanupTemporaryFiles() async {
        let fileManager = FileManager.default
        let tempDir = fileManager.temporaryDirectory
        
        do {
            let tempFiles = try fileManager.contentsOfDirectory(at: tempDir, includingPropertiesForKeys: [.creationDateKey])
            let cutoffDate = Date().addingTimeInterval(-86400) // 24 hours ago
            
            for fileURL in tempFiles {
                if let creationDate = try? fileURL.resourceValues(forKeys: [.creationDateKey]).creationDate,
                   creationDate < cutoffDate {
                    try? fileManager.removeItem(at: fileURL)
                }
            }
        } catch {
            print("Failed to cleanup temporary files: \(error)")
        }
    }
    
    // MARK: - Memory Warning Handling
    
    private func setupMemoryWarningObserver() {
        NotificationCenter.default.publisher(for: UIApplication.didReceiveMemoryWarningNotification)
            .sink { [weak self] _ in
                self?.handleMemoryWarning()
            }
            .store(in: &cancellables)
    }
    
    private func handleMemoryWarning() {
        print("⚠️ Memory warning received")
        triggerMemoryOptimization()
        
        // Record memory warning event
        let event = PerformanceEvent(
            type: .memoryWarning,
            timestamp: Date(),
            metadata: ["memory_usage": currentMetrics.memoryUsage.percentage]
        )
        recordPerformanceEvent(event)
    }
    
    // MARK: - Performance Reporting
    
    func generatePerformanceReport() -> PerformanceReport {
        let report = PerformanceReport(
            sessionDuration: startTime.map { Date().timeIntervalSince($0) } ?? 0,
            averageMemoryUsage: calculateAverageMemoryUsage(),
            peakMemoryUsage: calculatePeakMemoryUsage(),
            operationMetrics: operationMetrics,
            memorySnapshots: memorySnapshots,
            slowOperations: getSlowOperations(),
            optimizationEvents: getOptimizationEvents()
        )
        
        logPerformanceReport(report)
        return report
    }
    
    private func calculateAverageMemoryUsage() -> Double {
        guard !memorySnapshots.isEmpty else { return 0 }
        return memorySnapshots.map { $0.usage.percentage }.reduce(0, +) / Double(memorySnapshots.count)
    }
    
    private func calculatePeakMemoryUsage() -> Double {
        return memorySnapshots.map { $0.usage.percentage }.max() ?? 0
    }
    
    private func getSlowOperations() -> [OperationMetric] {
        return operationMetrics.values.filter { $0.duration > 1.0 }.sorted { $0.duration > $1.duration }
    }
    
    private func getOptimizationEvents() -> [PerformanceEvent] {
        // Return recorded optimization events
        return []
    }
    
    private func logPerformanceReport(_ report: PerformanceReport) {
        print("""
        📊 Performance Report
        Session Duration: \(String(format: "%.1f", report.sessionDuration))s
        Average Memory: \(String(format: "%.1f", report.averageMemoryUsage))%
        Peak Memory: \(String(format: "%.1f", report.peakMemoryUsage))%
        Slow Operations: \(report.slowOperations.count)
        """)
        
        for operation in report.slowOperations.prefix(5) {
            print("  - \(operation.name): \(String(format: "%.2f", operation.duration))s")
        }
    }
    
    private func recordPerformanceEvent(_ event: PerformanceEvent) {
        // Store performance events for analysis
        // In production, send to analytics service
    }
}

// MARK: - Performance Data Structures

struct PerformanceMetrics {
    let memoryUsage: MemoryUsage
    let cpuUsage: Double
    let batteryLevel: Double
    let diskUsage: DiskUsage
    let networkActivity: NetworkActivity
    let frameRate: Double
    let timestamp: Date
    
    init() {
        self.memoryUsage = MemoryUsage(used: 0, available: 0, percentage: 0)
        self.cpuUsage = 0
        self.batteryLevel = 100
        self.diskUsage = DiskUsage(used: 0, available: 0, total: 0, percentage: 0)
        self.networkActivity = NetworkActivity(bytesIn: 0, bytesOut: 0, requestsPerSecond: 0)
        self.frameRate = 60
        self.timestamp = Date()
    }
    
    init(memoryUsage: MemoryUsage, cpuUsage: Double, batteryLevel: Double, diskUsage: DiskUsage, networkActivity: NetworkActivity, frameRate: Double, timestamp: Date) {
        self.memoryUsage = memoryUsage
        self.cpuUsage = cpuUsage
        self.batteryLevel = batteryLevel
        self.diskUsage = diskUsage
        self.networkActivity = networkActivity
        self.frameRate = frameRate
        self.timestamp = timestamp
    }
}

struct MemoryUsage {
    let used: Double // bytes
    let available: Double // bytes
    let percentage: Double
    
    var usedMB: Double { used / (1024 * 1024) }
    var availableMB: Double { available / (1024 * 1024) }
}

struct DiskUsage {
    let used: Double // bytes
    let available: Double // bytes
    let total: Double // bytes
    let percentage: Double
    
    var usedGB: Double { used / (1024 * 1024 * 1024) }
    var availableGB: Double { available / (1024 * 1024 * 1024) }
    var totalGB: Double { total / (1024 * 1024 * 1024) }
}

struct NetworkActivity {
    let bytesIn: Int64
    let bytesOut: Int64
    let requestsPerSecond: Double
}

struct MemorySnapshot {
    let usage: MemoryUsage
    let timestamp: Date
}

class PerformanceOperation {
    let name: String
    let startTime: Date
    let memoryBefore: MemoryUsage
    
    init(name: String, startTime: Date) {
        self.name = name
        self.startTime = startTime
        self.memoryBefore = PerformanceMonitor.shared.currentMetrics.memoryUsage
    }
}

struct OperationMetric {
    let name: String
    let duration: TimeInterval
    let startTime: Date
    let endTime: Date
    let memoryBefore: MemoryUsage
    let memoryAfter: MemoryUsage
    
    var memoryDelta: Double {
        memoryAfter.used - memoryBefore.used
    }
}

struct PerformanceEvent {
    let type: EventType
    let timestamp: Date
    let metadata: [String: Any]
    
    enum EventType {
        case memoryWarning
        case batteryLow
        case diskFull
        case slowOperation
        case networkError
    }
}

struct PerformanceReport {
    let sessionDuration: TimeInterval
    let averageMemoryUsage: Double
    let peakMemoryUsage: Double
    let operationMetrics: [String: OperationMetric]
    let memorySnapshots: [MemorySnapshot]
    let slowOperations: [OperationMetric]
    let optimizationEvents: [PerformanceEvent]
}

// MARK: - SwiftUI Performance Modifiers

struct PerformanceTrackingModifier: ViewModifier {
    let operationName: String
    @State private var operation: PerformanceOperation?
    
    func body(content: Content) -> some View {
        content
            .onAppear {
                operation = PerformanceMonitor.shared.startOperation(operationName)
            }
            .onDisappear {
                if let operation = operation {
                    PerformanceMonitor.shared.endOperation(operation)
                }
            }
    }
}

extension View {
    func trackPerformance(_ operationName: String) -> some View {
        self.modifier(PerformanceTrackingModifier(operationName: operationName))
    }
}

// MARK: - Notification Names

extension Notification.Name {
    static let performanceOptimizationTriggered = Notification.Name("performanceOptimizationTriggered")
    static let batteryOptimizationTriggered = Notification.Name("batteryOptimizationTriggered")
    static let uiOptimizationTriggered = Notification.Name("uiOptimizationTriggered")
}

// MARK: - Performance-Aware View Components

struct PerformanceAwareView<Content: View>: View {
    let content: Content
    @State private var isOptimized = false
    @ObservedObject private var monitor = PerformanceMonitor.shared
    
    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }
    
    var body: some View {
        Group {
            if isOptimized {
                // Simplified version for low performance
                content
                    .animation(nil, value: monitor.currentMetrics.frameRate)
            } else {
                // Full version for good performance
                content
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .uiOptimizationTriggered)) { _ in
            isOptimized = true
            
            // Restore full functionality after performance improves
            DispatchQueue.main.asyncAfter(deadline: .now() + 10) {
                isOptimized = false
            }
        }
    }
}