import Foundation
import Security

enum WatchTokenStore {
    private static let service = "com.codingquota.watch-token"
    private static let account = "default"

    private static var baseQuery: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }

    static func load() -> String {
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess,
              let data = item as? Data,
              let token = String(data: data, encoding: .utf8) else {
            return ""
        }
        return WatchToken.sanitize(token) ?? ""
    }

    @discardableResult
    static func save(_ rawToken: String) -> Bool {
        guard let token = WatchToken.sanitize(rawToken),
              let data = token.data(using: .utf8) else {
            return false
        }

        var addQuery = baseQuery
        addQuery[kSecValueData as String] = data
        addQuery[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly

        let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
        if addStatus == errSecSuccess {
            return true
        }
        if addStatus != errSecDuplicateItem {
            return false
        }

        let updateAttributes = [kSecValueData as String: data]
        return SecItemUpdate(baseQuery as CFDictionary, updateAttributes as CFDictionary) == errSecSuccess
    }

    static func delete() {
        SecItemDelete(baseQuery as CFDictionary)
    }

    static func migrateLegacyTokenIfNeeded(defaults: UserDefaults) -> String {
        let existing = load()
        guard existing.isEmpty else {
            defaults.removeObject(forKey: AppConstants.watchTokenKey)
            return existing
        }

        guard let legacyToken = WatchToken.sanitize(defaults.string(forKey: AppConstants.watchTokenKey)) else {
            defaults.removeObject(forKey: AppConstants.watchTokenKey)
            return ""
        }

        if save(legacyToken) {
            defaults.removeObject(forKey: AppConstants.watchTokenKey)
        }
        return legacyToken
    }
}
