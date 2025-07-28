import Foundation
import Combine

@MainActor
final class CapsuleListViewModel: ObservableObject {
    @Published var capsules: [Capsule] = []
    @Published var isLoading = false
    @Published var error: Error?
    @Published var hasReachedEnd = false
    
    private let capsuleService: CapsuleServiceProtocol
    private var cancellables = Set<AnyCancellable>()
    
    init(capsuleService: CapsuleServiceProtocol = CapsuleService()) {
        self.capsuleService = capsuleService
        setupPolling()
    }
    
    func loadCapsules() async {
        isLoading = true
        error = nil
        
        do {
            capsules = try await capsuleService.getAllCapsules()
        } catch {
            self.error = error
        }
        
        isLoading = false
    }
    
    func refreshCapsules() async {
        await loadCapsules()
    }
    
    func retryFailedCapsule(_ capsule: Capsule) async {
        guard capsule.status == .failed else { return }
        
        do {
            let updatedCapsule = try await capsuleService.pollTranscription(for: capsule.id)
            
            // Update the capsule in our local array
            if let index = capsules.firstIndex(where: { $0.id == capsule.id }) {
                capsules[index] = updatedCapsule
            }
        } catch {
            self.error = error
        }
    }
    
    func deleteCapsule(_ capsule: Capsule) {
        // Remove from local array immediately for better UX
        capsules.removeAll { $0.id == capsule.id }
        
        // TODO: Implement actual deletion from server and local storage
        Task {
            // This would call capsuleService.deleteCapsule(capsule.id)
        }
    }
    
    private func setupPolling() {
        // Start polling for pending capsules when view model is created
        capsuleService.startPollingForPendingCapsules()
        
        // Refresh capsules every 30 seconds to show updates
        Timer.publish(every: 30, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                Task {
                    await self?.refreshCapsules()
                }
            }
            .store(in: &cancellables)
    }
    
    deinit {
        capsuleService.stopPolling()
    }
}

// MARK: - Computed Properties
extension CapsuleListViewModel {
    var processingCapsules: [Capsule] {
        capsules.filter { $0.status.isProcessing }
    }
    
    var completedCapsules: [Capsule] {
        capsules.filter { $0.status == .completed }
    }
    
    var failedCapsules: [Capsule] {
        capsules.filter { $0.status == .failed }
    }
    
    var groupedCapsules: [CapsuleGroup] {
        let calendar = Calendar.current
        let groupedDict = Dictionary(grouping: capsules) { capsule in
            calendar.startOfDay(for: capsule.createdAt)
        }
        
        return groupedDict.map { date, capsules in
            CapsuleGroup(date: date, capsules: capsules.sorted { $0.createdAt > $1.createdAt })
        }.sorted { $0.date > $1.date }
    }
}

// MARK: - Supporting Types
struct CapsuleGroup: Identifiable {
    let id = UUID()
    let date: Date
    let capsules: [Capsule]
    
    var displayDate: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        
        let calendar = Calendar.current
        if calendar.isDateInToday(date) {
            return "Today"
        } else if calendar.isDateInYesterday(date) {
            return "Yesterday"
        } else {
            return formatter.string(from: date)
        }
    }
}