import Foundation
import CoreData

@objc(CapsuleEntity)
public class CapsuleEntity: NSManagedObject {
    
    @nonobjc public class func fetchRequest() -> NSFetchRequest<CapsuleEntity> {
        return NSFetchRequest<CapsuleEntity>(entityName: "CapsuleEntity")
    }
    
    @NSManaged public var id: String
    @NSManaged public var userId: String
    @NSManaged public var localFileURL: URL?
    @NSManaged public var audioURL: URL?
    @NSManaged public var transcription: String?
    @NSManaged public var duration: Double
    @NSManaged public var fileSize: Int64
    @NSManaged public var createdAt: Date
    @NSManaged public var updatedAt: Date
    @NSManaged public var status: String
    @NSManaged public var lastPolledAt: Date?
    @NSManaged public var emotions: Data?
    @NSManaged public var topics: Data?
    @NSManaged public var summary: String?
    
    var capsuleStatus: CapsuleStatus {
        get {
            return CapsuleStatus(rawValue: status) ?? .failed
        }
        set {
            status = newValue.rawValue
        }
    }
    
    var emotionScores: [EmotionScore]? {
        get {
            guard let emotions = emotions else { return nil }
            return try? JSONDecoder().decode([EmotionScore].self, from: emotions)
        }
        set {
            emotions = try? JSONEncoder().encode(newValue)
        }
    }
    
    var topicList: [String]? {
        get {
            guard let topics = topics else { return nil }
            return try? JSONDecoder().decode([String].self, from: topics)
        }
        set {
            topics = try? JSONEncoder().encode(newValue)
        }
    }
    
    /// Convert Core Data entity to API model
    func toCapsule() -> Capsule {
        let metadata = CapsuleMetadata(
            emotions: emotionScores,
            topics: topicList,
            summary: summary
        )
        
        return Capsule(
            id: id,
            userId: userId,
            audioURL: audioURL,
            transcription: transcription,
            duration: duration,
            fileSize: fileSize,
            createdAt: createdAt,
            updatedAt: updatedAt,
            status: capsuleStatus,
            metadata: metadata
        )
    }
    
    /// Update entity from API response
    func updateFromCapsule(_ capsule: Capsule) {
        self.id = capsule.id
        self.userId = capsule.userId
        self.audioURL = capsule.audioURL
        self.transcription = capsule.transcription
        self.duration = capsule.duration
        self.fileSize = capsule.fileSize
        self.createdAt = capsule.createdAt
        self.updatedAt = capsule.updatedAt
        self.capsuleStatus = capsule.status
        
        if let metadata = capsule.metadata {
            self.emotionScores = metadata.emotions
            self.topicList = metadata.topics
            self.summary = metadata.summary
        }
    }
}