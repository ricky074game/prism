import Foundation
import Security

/// Minimal Keychain wrapper for the OAuth tokens.
///
/// Tokens go here rather than `UserDefaults` because a refresh token is a
/// long-lived credential for the user's Google account — `UserDefaults` is a
/// plist in the app container, readable by anything that can reach the
/// filesystem.
///
/// `kSecAttrAccessibleAfterFirstUnlock` rather than `WhenUnlocked`, so a token
/// refresh can still happen while the phone is locked and audio is playing in
/// the background.
enum Keychain {
    private static let service = "com.prism.client"

    static func save<T: Encodable>(_ value: T, key: String) {
        guard let data = try? JSONEncoder().encode(value) else { return }

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
        ]
        let attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock,
        ]

        // Update if present, add if not — SecItemAdd fails with errSecDuplicateItem
        // rather than overwriting.
        let status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            SecItemAdd(query.merging(attributes) { a, _ in a } as CFDictionary, nil)
        }
    }

    static func load<T: Decodable>(_ key: String, as type: T.Type) -> T? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]

        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data
        else { return nil }

        return try? JSONDecoder().decode(T.self, from: data)
    }

    static func delete(_ key: String) {
        SecItemDelete([
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
        ] as CFDictionary)
    }
}
