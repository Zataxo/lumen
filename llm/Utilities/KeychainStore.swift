import Foundation
import Security

nonisolated struct HTTPHeader: Codable, Hashable, Identifiable, Sendable {
    var id = UUID()
    var name: String
    var value: String
}

/// Secrets for one server. Stored as a single JSON blob in the Keychain.
nonisolated struct ServerSecrets: Codable, Hashable, Sendable {
    var apiKey: String?
    var headers: [HTTPHeader] = []

    var isEmpty: Bool { (apiKey ?? "").isEmpty && headers.isEmpty }
}

/// Minimal generic-password Keychain wrapper.
nonisolated enum KeychainStore {
    private static let service = "zataxo.swift.llm-app.server-secrets"

    static func secrets(for serverID: UUID) -> ServerSecrets {
        var query = baseQuery(account: serverID.uuidString)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: AnyObject?
        var status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecMissingEntitlement {
            query[kSecUseDataProtectionKeychain as String] = nil
            status = SecItemCopyMatching(query as CFDictionary, &result)
        }
        guard status == errSecSuccess, let data = result as? Data,
              let secrets = try? JSONDecoder().decode(ServerSecrets.self, from: data)
        else { return ServerSecrets() }
        return secrets
    }

    static func setSecrets(_ secrets: ServerSecrets, for serverID: UUID) {
        deleteSecrets(for: serverID)
        guard !secrets.isEmpty, let data = try? JSONEncoder().encode(secrets) else { return }

        var attributes = baseQuery(account: serverID.uuidString)
        attributes[kSecValueData as String] = data
        attributes[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        var status = SecItemAdd(attributes as CFDictionary, nil)
        if status == errSecMissingEntitlement {
            // Unsigned local builds can't use the data-protection keychain on macOS.
            attributes[kSecUseDataProtectionKeychain as String] = nil
            status = SecItemAdd(attributes as CFDictionary, nil)
        }
        assert(status == errSecSuccess, "Keychain write failed: \(status)")
    }

    /// Removes every server's secrets.
    static func deleteAllSecrets() {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecUseDataProtectionKeychain as String: true,
        ]
        SecItemDelete(query as CFDictionary)
        query[kSecUseDataProtectionKeychain as String] = nil
        SecItemDelete(query as CFDictionary)
    }

    static func deleteSecrets(for serverID: UUID) {
        var query = baseQuery(account: serverID.uuidString)
        SecItemDelete(query as CFDictionary)
        query[kSecUseDataProtectionKeychain as String] = nil
        SecItemDelete(query as CFDictionary)
    }

    private static func baseQuery(account: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecUseDataProtectionKeychain as String: true,
        ]
    }
}
