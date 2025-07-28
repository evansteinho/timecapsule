import Foundation

struct User: Codable, Identifiable {
    let id: String
    let email: String?
    let name: String?
    let createdAt: Date
    let isProUser: Bool
    
    enum CodingKeys: String, CodingKey {
        case id
        case email
        case name
        case createdAt = "created_at"
        case isProUser = "is_pro_user"
    }
}