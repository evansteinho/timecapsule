import Foundation
import CoreData

final class PersistenceService {
    static let shared = PersistenceService()
    
    lazy var persistentContainer: NSPersistentContainer = {
        let model = CoreDataModelHelper.createModel()
        let container = NSPersistentContainer(name: "TimeCapsule", managedObjectModel: model)
        
        // Configure for encrypted storage
        let storeURL = container.defaultDirectoryURL().appendingPathComponent("TimeCapsule.sqlite")
        let description = NSPersistentStoreDescription(url: storeURL)
        description.type = NSSQLiteStoreType
        description.setOption(FileProtectionType.complete as NSString, forKey: NSPersistentHistoryTrackingKey)
        
        container.persistentStoreDescriptions = [description]
        
        container.loadPersistentStores { _, error in
            if let error = error {
                fatalError("Core Data failed to load: \(error.localizedDescription)")
            }
        }
        
        container.viewContext.automaticallyMergesChangesFromParent = true
        return container
    }()
    
    var viewContext: NSManagedObjectContext {
        return persistentContainer.viewContext
    }
    
    func newBackgroundContext() -> NSManagedObjectContext {
        return persistentContainer.newBackgroundContext()
    }
    
    func save() {
        let context = persistentContainer.viewContext
        
        if context.hasChanges {
            do {
                try context.save()
            } catch {
                print("Save error: \(error)")
            }
        }
    }
    
    func saveContext(_ context: NSManagedObjectContext) {
        if context.hasChanges {
            do {
                try context.save()
            } catch {
                print("Save error: \(error)")
            }
        }
    }
}