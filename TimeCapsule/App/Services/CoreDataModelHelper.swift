import Foundation
import CoreData

/// Helper class to programmatically create Core Data model
/// Note: In production, you should create TimeCapsule.xcdatamodeld manually in Xcode
final class CoreDataModelHelper {
    
    static func createModel() -> NSManagedObjectModel {
        let model = NSManagedObjectModel()
        
        // Create CapsuleEntity
        let capsuleEntity = NSEntityDescription()
        capsuleEntity.name = "CapsuleEntity"
        capsuleEntity.managedObjectClassName = "CapsuleEntity"
        
        // Add attributes
        let attributes: [(String, NSAttributeType, Bool)] = [
            ("id", .stringAttributeType, false),
            ("userId", .stringAttributeType, false),
            ("localFileURL", .URIAttributeType, true),
            ("audioURL", .URIAttributeType, true),
            ("transcription", .stringAttributeType, true),
            ("duration", .doubleAttributeType, false),
            ("fileSize", .integer64AttributeType, false),
            ("createdAt", .dateAttributeType, false),
            ("updatedAt", .dateAttributeType, false),
            ("status", .stringAttributeType, false),
            ("lastPolledAt", .dateAttributeType, true),
            ("emotions", .binaryDataAttributeType, true),
            ("topics", .binaryDataAttributeType, true),
            ("summary", .stringAttributeType, true)
        ]
        
        capsuleEntity.properties = attributes.map { name, type, optional in
            let attribute = NSAttributeDescription()
            attribute.name = name
            attribute.attributeType = type
            attribute.isOptional = optional
            
            // Set default values
            switch name {
            case "duration":
                attribute.defaultValue = 0.0
            case "fileSize":
                attribute.defaultValue = 0
            case "status":
                attribute.defaultValue = CapsuleStatus.uploading.rawValue
            default:
                break
            }
            
            return attribute
        }
        
        model.entities = [capsuleEntity]
        return model
    }
}

// MARK: - NSPersistentContainer Extension
extension NSPersistentContainer {
    convenience init(name: String, managedObjectModel: NSManagedObjectModel) {
        self.init(name: name)
        self.managedObjectModel = managedObjectModel
    }
}