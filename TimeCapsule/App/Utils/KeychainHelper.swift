import Foundation
import Security

final class KeychainHelper {
    private let service = "com.timecapsule.app"
    
    func save(data: Data, key: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        ]
        
        // Delete any existing item
        SecItemDelete(query as CFDictionary)
        
        // Add new item
        let status = SecItemAdd(query as CFDictionary, nil)
        
        if status != errSecSuccess {
            print("Keychain save error: \(status)")
        }
    }
    
    func load(key: String) -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        
        guard status == errSecSuccess else {
            return nil
        }
        
        return item as? Data
    }
    
    func delete(key: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key
        ]
        
        SecItemDelete(query as CFDictionary)
    }
    
    func exists(key: String) -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecReturnData as String: false,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        
        return SecItemCopyMatching(query as CFDictionary, nil) == errSecSuccess
    }
    
    // Additional helper methods
    func save(_ data: Data, key: String) {
        save(data: data, key: key)
    }
    
    func savePassword(_ password: String, for key: String) {
        guard let data = password.data(using: .utf8) else { return }
        save(data: data, key: key)
    }
    
    func retrievePassword(for key: String) -> String? {
        guard let data = load(key: key) else { return nil }
        return String(data: data, encoding: .utf8)
    }
}