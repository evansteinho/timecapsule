import Foundation
import CoreData
import CryptoKit

/// Enhanced PersistenceService with encryption, performance optimizations, and error recovery
final class EnhancedPersistenceService {
    static let shared = EnhancedPersistenceService()
    
    private var _persistentContainer: NSPersistentContainer?
    private let containerQueue = DispatchQueue(label: "persistence.container", qos: .userInitiated)
    private let encryptionManager = DatabaseEncryptionManager()
    
    lazy var persistentContainer: NSPersistentContainer = {
        if let container = _persistentContainer {
            return container
        }
        
        let container = createPersistentContainer()
        _persistentContainer = container
        return container
    }()
    
    var viewContext: NSManagedObjectContext {
        persistentContainer.viewContext
    }
    
    private init() {
        setupMemoryManagement()
    }
    
    // MARK: - Enhanced Container Creation
    
    private func createPersistentContainer() -> NSPersistentContainer {
        let model = CoreDataModelHelper.createModel()
        let container = NSPersistentContainer(name: "TimeCapsule", managedObjectModel: model)
        
        let storeURL = container.defaultDirectoryURL().appendingPathComponent("TimeCapsule.sqlite")
        let description = NSPersistentStoreDescription(url: storeURL)
        
        // Configure store type and protection
        description.type = NSSQLiteStoreType
        description.setOption(FileProtectionType.complete as NSString, 
                            forKey: NSPersistentStoreFileProtectionKey)
        
        // Enable persistent history tracking for sync
        description.setOption(true as NSNumber, 
                            forKey: NSPersistentHistoryTrackingKey)
        description.setOption(true as NSNumber, 
                            forKey: NSPersistentStoreRemoteChangeNotificationPostOptionKey)
        
        // Configure encryption if available
        if let encryptionKey = encryptionManager.getOrCreateEncryptionKey() {
            configureSQLCipherEncryption(description: description, key: encryptionKey)
        }
        
        // Performance optimizations
        description.setOption("DELETE" as NSString, forKey: "journal_mode")
        description.setOption("NORMAL" as NSString, forKey: "synchronous")
        description.setOption("10000" as NSString, forKey: "cache_size")
        
        container.persistentStoreDescriptions = [description]
        
        // Load store with error recovery
        loadStoreWithRecovery(container: container)
        
        // Configure contexts
        configureContexts(container: container)
        
        return container
    }
    
    private func configureSQLCipherEncryption(description: NSPersistentStoreDescription, key: String) {
        // Note: This requires SQLCipher integration
        // In a real implementation, you would add SQLCipher as a dependency
        #if SQLCIPHER_ENABLED
        description.setOption(key as NSString, forKey: "passphrase")
        description.setOption("PRAGMA cipher_default_kdf_iter = 64000;" as NSString, forKey: "pragma")
        description.setOption("PRAGMA cipher_default_page_size = 4096;" as NSString, forKey: "pragma")
        #else
        // Fallback to file-level encryption using built-in iOS encryption
        print("SQLCipher not available, using iOS file protection")
        #endif
    }
    
    private func loadStoreWithRecovery(container: NSPersistentContainer) {
        var loadError: Error?
        let group = DispatchGroup()
        
        group.enter()
        container.loadPersistentStores { _, error in
            loadError = error
            group.leave()
        }
        
        group.wait()
        
        if let error = loadError {
            handleStoreLoadingError(error, container: container)
        }
    }
    
    private func handleStoreLoadingError(_ error: Error, container: NSPersistentContainer) {
        print("Core Data store loading failed: \(error)")
        
        // Attempt recovery strategies
        do {
            try attemptStoreRecovery(container: container)
        } catch {
            print("Store recovery failed: \(error)")
            
            // Last resort: reset the store
            resetStore(container: container)
        }
    }
    
    private func attemptStoreRecovery(container: NSPersistentContainer) throws {
        guard let storeURL = container.persistentStoreDescriptions.first?.url else {
            throw PersistenceError.storeURLNotFound
        }
        
        // Try to repair the store
        let coordinator = NSPersistentStoreCoordinator(managedObjectModel: container.managedObjectModel)
        
        do {
            let options: [String: Any] = [
                NSMigratePersistentStoresAutomaticallyOption: true,
                NSInferMappingModelAutomaticallyOption: true
            ]
            
            _ = try coordinator.addPersistentStore(
                ofType: NSSQLiteStoreType,
                configurationName: nil,
                at: storeURL,
                options: options
            )
            
            print("Store recovery successful")
        } catch {
            throw PersistenceError.storeRecoveryFailed
        }
    }
    
    private func resetStore(container: NSPersistentContainer) {
        guard let storeURL = container.persistentStoreDescriptions.first?.url else { return }
        
        do {
            // Remove existing store files
            let fileManager = FileManager.default
            if fileManager.fileExists(atPath: storeURL.path) {
                try fileManager.removeItem(at: storeURL)
            }
            
            // Remove associated files
            let walURL = storeURL.appendingPathExtension("wal")
            let shmURL = storeURL.appendingPathExtension("shm")
            
            try? fileManager.removeItem(at: walURL)
            try? fileManager.removeItem(at: shmURL)
            
            // Reload the store
            container.loadPersistentStores { _, error in
                if let error = error {
                    print("Failed to reload store after reset: \(error)")
                } else {
                    print("Store reset and reloaded successfully")
                }
            }
        } catch {
            print("Failed to reset store: \(error)")
        }
    }
    
    private func configureContexts(container: NSPersistentContainer) {
        // Configure view context
        let viewContext = container.viewContext
        viewContext.automaticallyMergesChangesFromParent = true
        viewContext.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
        viewContext.undoManager = nil // Disable undo for performance
        
        // Set up change notifications
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(contextDidSave),
            name: .NSManagedObjectContextDidSave,
            object: nil
        )
    }
    
    @objc private func contextDidSave(_ notification: Notification) {
        guard let context = notification.object as? NSManagedObjectContext,
              context !== viewContext else { return }
        
        viewContext.performAndWait {
            viewContext.mergeChanges(fromContextDidSave: notification)
        }
    }
    
    // MARK: - Enhanced Context Management
    
    func createBackgroundContext(name: String) -> NSManagedObjectContext {
        let context = persistentContainer.newBackgroundContext()
        context.name = name
        context.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
        context.undoManager = nil
        
        return context
    }
    
    func performBackgroundTask<T>(
        named taskName: String = "BackgroundTask",
        _ operation: @escaping (NSManagedObjectContext) throws -> T
    ) async throws -> T {
        let context = createBackgroundContext(name: taskName)
        
        return try await context.perform {
            do {
                let result = try operation(context)
                
                if context.hasChanges {
                    try context.save()
                }
                
                return result
            } catch {
                context.rollback()
                throw error
            }
        }
    }
    
    // MARK: - Enhanced Save Operations
    
    func save() throws {
        try saveContext(viewContext)
    }
    
    func saveContext(_ context: NSManagedObjectContext) throws {
        guard context.hasChanges else { return }
        
        do {
            try context.save()
        } catch {
            context.rollback()
            throw PersistenceError.saveFailed(error)
        }
    }
    
    // MARK: - Batch Operations
    
    func batchInsert<T: NSManagedObject>(
        entityType: T.Type,
        objects: [[String: Any]]
    ) async throws {
        try await performBackgroundTask(named: "BatchInsert") { context in
            let request = NSBatchInsertRequest(
                entityName: String(describing: entityType),
                objects: objects
            )
            request.resultType = .objectIDs
            
            let result = try context.execute(request) as? NSBatchInsertResult
            
            if let objectIDs = result?.result as? [NSManagedObjectID] {
                let changes = [NSInsertedObjectsKey: objectIDs]
                NSManagedObjectContext.mergeChanges(
                    fromRemoteContextSave: changes,
                    into: [self.viewContext]
                )
            }
        }
    }
    
    func batchUpdate<T: NSManagedObject>(
        entityType: T.Type,
        predicate: NSPredicate,
        propertiesToUpdate: [String: Any]
    ) async throws -> Int {
        return try await performBackgroundTask(named: "BatchUpdate") { context in
            let request = NSBatchUpdateRequest(entityName: String(describing: entityType))
            request.predicate = predicate
            request.propertiesToUpdate = propertiesToUpdate
            request.resultType = .updatedObjectsCountResultType
            
            let result = try context.execute(request) as? NSBatchUpdateResult
            
            // Refresh objects in view context
            context.refreshAllObjects()
            
            return result?.result as? Int ?? 0
        }
    }
    
    func batchDelete<T: NSManagedObject>(
        entityType: T.Type,
        predicate: NSPredicate
    ) async throws -> Int {
        return try await performBackgroundTask(named: "BatchDelete") { context in
            let request = NSBatchDeleteRequest(
                fetchRequest: NSFetchRequest<NSFetchRequestResult>(entityName: String(describing: entityType))
            )
            request.fetchRequest.predicate = predicate
            request.resultType = .resultTypeCount
            
            let result = try context.execute(request) as? NSBatchDeleteResult
            
            return result?.result as? Int ?? 0
        }
    }
    
    // MARK: - Memory Management
    
    private func setupMemoryManagement() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleMemoryWarning),
            name: UIApplication.didReceiveMemoryWarningNotification,
            object: nil
        )
    }
    
    @objc private func handleMemoryWarning() {
        optimizeMemoryUsage()
    }
    
    func optimizeMemoryUsage() {
        // Clear cached objects
        viewContext.refreshAllObjects()
        
        // Reset context if it has too many objects
        let objectCount = viewContext.registeredObjects.count
        if objectCount > 1000 {
            print("Resetting view context due to high object count: \(objectCount)")
            viewContext.reset()
        }
        
        // Clear any cached metadata
        URLCache.shared.removeAllCachedResponses()
    }
    
    // MARK: - Query Optimization
    
    func optimizedFetch<T: NSManagedObject>(
        entityType: T.Type,
        predicate: NSPredicate? = nil,
        sortDescriptors: [NSSortDescriptor] = [],
        limit: Int? = nil,
        offset: Int = 0,
        prefetchKeyPaths: [String] = []
    ) async throws -> [T] {
        return try await performBackgroundTask(named: "OptimizedFetch") { context in
            let request = NSFetchRequest<T>(entityName: String(describing: entityType))
            
            request.predicate = predicate
            request.sortDescriptors = sortDescriptors
            request.relationshipKeyPathsForPrefetching = prefetchKeyPaths
            request.returnsObjectsAsFaults = false
            request.includesSubentities = false
            
            if let limit = limit {
                request.fetchLimit = limit
            }
            request.fetchOffset = offset
            
            return try context.fetch(request)
        }
    }
    
    // MARK: - Data Export/Import
    
    func exportData() async throws -> Data {
        return try await performBackgroundTask(named: "DataExport") { context in
            let capsules = try context.fetch(CapsuleEntity.fetchRequest())
            let exportData = capsules.map { $0.toCapsule() }
            return try JSONEncoder().encode(exportData)
        }
    }
    
    func importData(_ data: Data) async throws {
        let capsules = try JSONDecoder().decode([Capsule].self, from: data)
        
        try await performBackgroundTask(named: "DataImport") { context in
            for capsule in capsules {
                let entity = CapsuleEntity(context: context)
                entity.updateFromCapsule(capsule)
            }
        }
    }
}

// MARK: - Database Encryption Manager

final class DatabaseEncryptionManager {
    private let keyAlias = "TimeCapsule_CoreData_Key_v2"
    private let keychain = KeychainHelper()
    
    func getOrCreateEncryptionKey() -> String? {
        // Try to retrieve existing key
        if let existingKey = getExistingKey() {
            return existingKey
        }
        
        // Generate new key if none exists
        let newKey = generateEncryptionKey()
        saveEncryptionKey(newKey)
        return newKey
    }
    
    private func getExistingKey() -> String? {
        guard let keyData = keychain.load(key: keyAlias) else { return nil }
        return String(data: keyData, encoding: .utf8)
    }
    
    private func generateEncryptionKey() -> String {
        let keyData = SymmetricKey(size: .bits256)
        return keyData.withUnsafeBytes { bytes in
            Data(bytes).base64EncodedString()
        }
    }
    
    private func saveEncryptionKey(_ key: String) {
        guard let keyData = key.data(using: .utf8) else { return }
        keychain.save(keyData, key: keyAlias)
    }
    
    func rotateEncryptionKey() {
        // Remove old key
        keychain.delete(key: keyAlias)
        
        // Generate and save new key
        let newKey = generateEncryptionKey()
        saveEncryptionKey(newKey)
    }
}

// MARK: - Enhanced Errors

enum PersistenceError: LocalizedError {
    case storeURLNotFound
    case storeRecoveryFailed
    case saveFailed(Error)
    case fetchFailed(Error)
    case migrationFailed(Error)
    case encryptionKeyNotFound
    
    var errorDescription: String? {
        switch self {
        case .storeURLNotFound:
            return "Database store URL not found"
        case .storeRecoveryFailed:
            return "Failed to recover database store"
        case .saveFailed(let error):
            return "Failed to save data: \(error.localizedDescription)"
        case .fetchFailed(let error):
            return "Failed to fetch data: \(error.localizedDescription)"
        case .migrationFailed(let error):
            return "Database migration failed: \(error.localizedDescription)"
        case .encryptionKeyNotFound:
            return "Database encryption key not found"
        }
    }
    
    var recoverySuggestion: String? {
        switch self {
        case .storeRecoveryFailed:
            return "The app will attempt to reset the database. Some data may be lost."
        case .saveFailed:
            return "Please try again. If the problem persists, restart the app."
        case .encryptionKeyNotFound:
            return "The app will generate a new encryption key. Previous data may not be accessible."
        default:
            return nil
        }
    }
}

// MARK: - Migration Support

final class CoreDataMigrationManager {
    static func performMigrationIfNeeded(for container: NSPersistentContainer) throws {
        let coordinator = container.persistentStoreCoordinator
        
        guard let storeURL = container.persistentStoreDescriptions.first?.url else {
            throw PersistenceError.storeURLNotFound
        }
        
        guard FileManager.default.fileExists(atPath: storeURL.path) else {
            // No existing store, no migration needed
            return
        }
        
        guard let metadata = try? NSPersistentStoreCoordinator.metadataForPersistentStore(
            ofType: NSSQLiteStoreType,
            at: storeURL,
            options: nil
        ) else {
            throw PersistenceError.migrationFailed(NSError(domain: "CoreData", code: 1, userInfo: [NSLocalizedDescriptionKey: "Unable to read store metadata"]))
        }
        
        let currentModel = container.managedObjectModel
        
        if !currentModel.isConfiguration(withName: nil, compatibleWithStoreMetadata: metadata) {
            print("Core Data migration required")
            try performMigration(from: metadata, to: currentModel, at: storeURL, coordinator: coordinator)
        }
    }
    
    private static func performMigration(
        from sourceMetadata: [String: Any],
        to destinationModel: NSManagedObjectModel,
        at storeURL: URL,
        coordinator: NSPersistentStoreCoordinator
    ) throws {
        // For now, use automatic migration
        // In production, implement custom migration policies for complex changes
        let options: [String: Any] = [
            NSMigratePersistentStoresAutomaticallyOption: true,
            NSInferMappingModelAutomaticallyOption: true
        ]
        
        do {
            try coordinator.addPersistentStore(
                ofType: NSSQLiteStoreType,
                configurationName: nil,
                at: storeURL,
                options: options
            )
            print("Core Data migration completed successfully")
        } catch {
            throw PersistenceError.migrationFailed(error)
        }
    }
}