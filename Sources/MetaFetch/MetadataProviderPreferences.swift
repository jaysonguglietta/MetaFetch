import Foundation
import Security

enum MetadataProviderPreferences {
    static let tmdbAPIKeyKey = "MetaFetchTMDbAPIKey"
    static let omdbAPIKeyKey = "MetaFetchOMDbAPIKey"
    static let preferredProviderSourceKey = "MetaFetchPreferredProviderSource"
    private static let keychainService = "com.jaysonguglietta.metafetch.metadata-providers"

    static var tmdbAPIKey: String {
        get {
            storedSecret(for: tmdbAPIKeyKey)
        }
        set {
            setStoredSecret(newValue, for: tmdbAPIKeyKey)
        }
    }

    static var omdbAPIKey: String {
        get {
            storedSecret(for: omdbAPIKeyKey)
        }
        set {
            setStoredSecret(newValue, for: omdbAPIKeyKey)
        }
    }

    static var preferredProviderSource: MetadataProviderSource {
        get {
            guard let rawValue = UserDefaults.standard.string(forKey: preferredProviderSourceKey),
                  let source = MetadataProviderSource(rawValue: rawValue) else {
                return .automatic
            }

            return source
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: preferredProviderSourceKey)
        }
    }

    static func removeStoredSecrets() {
        deleteKeychainSecret(for: tmdbAPIKeyKey)
        deleteKeychainSecret(for: omdbAPIKeyKey)
        UserDefaults.standard.removeObject(forKey: tmdbAPIKeyKey)
        UserDefaults.standard.removeObject(forKey: omdbAPIKeyKey)
    }

    private static func storedSecret(for account: String) -> String {
        if let keychainSecret = keychainSecret(for: account)?.trimmedNilIfBlank {
            return keychainSecret
        }

        guard let migratedSecret = UserDefaults.standard
            .string(forKey: account)?
            .trimmedNilIfBlank else {
            UserDefaults.standard.removeObject(forKey: account)
            return ""
        }

        setKeychainSecret(migratedSecret, for: account)
        UserDefaults.standard.removeObject(forKey: account)
        return migratedSecret
    }

    private static func setStoredSecret(_ value: String, for account: String) {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        UserDefaults.standard.removeObject(forKey: account)

        guard !trimmed.isEmpty else {
            deleteKeychainSecret(for: account)
            return
        }

        setKeychainSecret(trimmed, for: account)
    }

    private static func keychainSecret(for account: String) -> String? {
        var query = keychainQuery(for: account)
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        query[kSecReturnData as String] = kCFBooleanTrue

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess,
              let data = item as? Data,
              let value = String(data: data, encoding: .utf8) else {
            return nil
        }

        return value
    }

    private static func setKeychainSecret(_ value: String, for account: String) {
        let data = Data(value.utf8)
        let updateStatus = SecItemUpdate(
            keychainQuery(for: account) as CFDictionary,
            [kSecValueData as String: data] as CFDictionary
        )

        if updateStatus == errSecSuccess {
            return
        }

        var addQuery = keychainQuery(for: account)
        addQuery[kSecValueData as String] = data
        addQuery[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        SecItemAdd(addQuery as CFDictionary, nil)
    }

    private static func deleteKeychainSecret(for account: String) {
        SecItemDelete(keychainQuery(for: account) as CFDictionary)
    }

    private static func keychainQuery(for account: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: account,
        ]
    }
}

private extension String {
    var trimmedNilIfBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
