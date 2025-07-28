import Foundation
import CoreData
import Combine

protocol CapsuleServiceProtocol {
    func saveCapsule(_ capsule: Capsule, localFileURL: URL?) async throws
    func pollTranscription(for capsuleId: String) async throws -> Capsule
    func getAllCapsules() async throws -> [Capsule]
    func getCapsule(by id: String) async throws -> Capsule?
    func startPollingForPendingCapsules()
    func stopPolling()
}

final class CapsuleService: CapsuleServiceProtocol {
    private let networkService: NetworkServiceProtocol
    private let persistenceService: PersistenceService
    private var pollingTimer: Timer?
    private var cancellables = Set<AnyCancellable>()
    
    // Polling configuration
    private let pollingInterval: TimeInterval = 5.0 // 5 seconds
    private let maxPollingAttempts = 120 // 10 minutes max (5s * 120 = 600s)
    private let exponentialBackoffBase: TimeInterval = 2.0
    
    init(
        networkService: NetworkServiceProtocol = NetworkService(),
        persistenceService: PersistenceService = .shared
    ) {
        self.networkService = networkService
        self.persistenceService = persistenceService
    }
    
    // MARK: - Public Methods
    
    func saveCapsule(_ capsule: Capsule, localFileURL: URL?) async throws {
        let context = persistenceService.newBackgroundContext()
        
        try await context.perform {
            // Check if capsule already exists
            let fetchRequest: NSFetchRequest<CapsuleEntity> = CapsuleEntity.fetchRequest()
            fetchRequest.predicate = NSPredicate(format: "id == %@", capsule.id)
            
            let existingCapsules = try context.fetch(fetchRequest)
            let capsuleEntity = existingCapsules.first ?? CapsuleEntity(context: context)
            
            // Update entity with capsule data
            capsuleEntity.updateFromCapsule(capsule)
            capsuleEntity.localFileURL = localFileURL
            capsuleEntity.lastPolledAt = Date()
            
            self.persistenceService.saveContext(context)
        }
    }
    
    func pollTranscription(for capsuleId: String) async throws -> Capsule {
        let capsule: Capsule = try await networkService.get(path: "/v0/capsules/\(capsuleId)")
        
        // Update local storage
        try await saveCapsule(capsule, localFileURL: nil)
        
        return capsule
    }
    
    func getAllCapsules() async throws -> [Capsule] {
        let context = persistenceService.viewContext
        
        return try await context.perform {
            let fetchRequest: NSFetchRequest<CapsuleEntity> = CapsuleEntity.fetchRequest()
            fetchRequest.sortDescriptors = [NSSortDescriptor(keyPath: \CapsuleEntity.createdAt, ascending: false)]
            
            let entities = try context.fetch(fetchRequest)
            return entities.map { $0.toCapsule() }
        }
    }
    
    func getCapsule(by id: String) async throws -> Capsule? {
        let context = persistenceService.viewContext
        
        return try await context.perform {
            let fetchRequest: NSFetchRequest<CapsuleEntity> = CapsuleEntity.fetchRequest()
            fetchRequest.predicate = NSPredicate(format: "id == %@", id)
            fetchRequest.fetchLimit = 1
            
            guard let entity = try context.fetch(fetchRequest).first else {
                return nil
            }
            
            return entity.toCapsule()
        }
    }
    
    func startPollingForPendingCapsules() {
        stopPolling() // Stop any existing polling
        
        pollingTimer = Timer.scheduledTimer(withTimeInterval: pollingInterval, repeats: true) { [weak self] _ in
            Task {
                await self?.pollPendingCapsules()
            }
        }
    }
    
    func stopPolling() {
        pollingTimer?.invalidate()
        pollingTimer = nil
    }
    
    // MARK: - Private Methods
    
    private func pollPendingCapsules() async {
        do {
            let pendingCapsules = try await getPendingCapsules()
            
            for capsuleEntity in pendingCapsules {
                await pollCapsuleWithBackoff(capsuleEntity)
            }
        } catch {
            print("Error polling pending capsules: \(error)")
        }
    }
    
    private func getPendingCapsules() async throws -> [CapsuleEntity] {
        let context = persistenceService.viewContext
        
        return try await context.perform {
            let fetchRequest: NSFetchRequest<CapsuleEntity> = CapsuleEntity.fetchRequest()
            
            // Only poll capsules that are still processing
            let processingStatuses = [
                CapsuleStatus.uploading.rawValue,
                CapsuleStatus.processing.rawValue,
                CapsuleStatus.transcribing.rawValue
            ]
            
            fetchRequest.predicate = NSPredicate(format: "status IN %@", processingStatuses)
            
            // Optionally filter by last polled time to avoid excessive polling
            let cutoffTime = Date().addingTimeInterval(-self.pollingInterval)
            let lastPolledPredicate = NSPredicate(format: "lastPolledAt == nil OR lastPolledAt < %@", cutoffTime as NSDate)
            
            fetchRequest.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
                fetchRequest.predicate!,
                lastPolledPredicate
            ])
            
            return try context.fetch(fetchRequest)
        }
    }
    
    private func pollCapsuleWithBackoff(_ capsuleEntity: CapsuleEntity) async {
        let capsuleId = capsuleEntity.id
        
        do {
            let updatedCapsule = try await pollTranscription(for: capsuleId)
            
            // Check if processing is complete
            if !updatedCapsule.status.isProcessing {
                print("Capsule \(capsuleId) processing completed with status: \(updatedCapsule.status.displayName)")
            }
            
        } catch {
            print("Error polling capsule \(capsuleId): \(error)")
            
            // Update last polled time even on error to prevent excessive retries
            await updateLastPolledTime(for: capsuleId)
            
            // Implement exponential backoff for failed requests
            await handlePollingError(for: capsuleEntity, error: error)
        }
    }
    
    private func updateLastPolledTime(for capsuleId: String) async {
        let context = persistenceService.newBackgroundContext()
        
        try? await context.perform {
            let fetchRequest: NSFetchRequest<CapsuleEntity> = CapsuleEntity.fetchRequest()
            fetchRequest.predicate = NSPredicate(format: "id == %@", capsuleId)
            
            if let entity = try context.fetch(fetchRequest).first {
                entity.lastPolledAt = Date()
                self.persistenceService.saveContext(context)
            }
        }
    }
    
    private func handlePollingError(for capsuleEntity: CapsuleEntity, error: Error) async {
        // For now, just log the error
        // In the future, could implement more sophisticated error handling:
        // - Exponential backoff
        // - Maximum retry limits
        // - Different handling based on error type
        print("Polling error for capsule \(capsuleEntity.id): \(error.localizedDescription)")
        
        // If it's a 404, the capsule might have been deleted on the server
        if let networkError = error as? NetworkError, case .notFound = networkError {
            await markCapsuleAsFailed(capsuleEntity.id)
        }
    }
    
    private func markCapsuleAsFailed(_ capsuleId: String) async {
        let context = persistenceService.newBackgroundContext()
        
        try? await context.perform {
            let fetchRequest: NSFetchRequest<CapsuleEntity> = CapsuleEntity.fetchRequest()
            fetchRequest.predicate = NSPredicate(format: "id == %@", capsuleId)
            
            if let entity = try context.fetch(fetchRequest).first {
                entity.capsuleStatus = .failed
                entity.lastPolledAt = Date()
                self.persistenceService.saveContext(context)
            }
        }
    }
}

// MARK: - Polling State Management
extension CapsuleService {
    /// Check if there are any capsules currently being processed
    func hasPendingCapsules() async -> Bool {
        do {
            let pendingCapsules = try await getPendingCapsules()
            return !pendingCapsules.isEmpty
        } catch {
            return false
        }
    }
    
    /// Get count of capsules by status
    func getCapsuleCount(for status: CapsuleStatus) async throws -> Int {
        let context = persistenceService.viewContext
        
        return try await context.perform {
            let fetchRequest: NSFetchRequest<CapsuleEntity> = CapsuleEntity.fetchRequest()
            fetchRequest.predicate = NSPredicate(format: "status == %@", status.rawValue)
            return try context.count(for: fetchRequest)
        }
    }
}