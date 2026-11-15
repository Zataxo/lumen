import CryptoKit
import Foundation
import Observation
import Security

/// A local account. Until there is a backend, accounts are seeded here. Passwords are never
/// stored in plain text: only a salted SHA-256 hash.
///
/// Note: this is an access gate for the app, not real security — anything shipped inside the
/// app can be inspected. Replace with server-side authentication when the backend exists.
nonisolated struct LocalAccount: Hashable, Sendable {
    var username: String
    var displayName: String
    var salt: String
    var passwordHash: String

    func matches(password: String) -> Bool {
        let digest = SHA256.hash(data: Data((salt + password).utf8))
        let hex = digest.map { String(format: "%02x", $0) }.joined()
        // Compare every character so timing doesn't reveal how much matched.
        guard hex.utf8.count == passwordHash.utf8.count else { return false }
        return zip(hex.utf8, passwordHash.utf8).reduce(0) { $0 | ($1.0 ^ $1.1) } == 0
    }

    /// Seeded accounts (both use the password "Admin123").
    static let seeded: [LocalAccount] = [
        LocalAccount(
            username: "zataxo", displayName: "Zataxo",
            salt: "8346520f87d2dc6f200e1ea00f4f6e9c",
            passwordHash: "d1a7cc82321e7b63edeeb94d0064d970188074e2c3ad2b296e73f55894102ab6"
        ),
        LocalAccount(
            username: "zaad", displayName: "Zaad",
            salt: "a373c4d9314364bf74ca50470f9e809c",
            passwordHash: "f1ecb0a456f5dc8144f0cc2a7f31a27d369c0764451881bde108521cb30ba0f4"
        ),
    ]
}

/// Where the signed-in username is remembered between launches.
nonisolated protocol SessionStorage: Sendable {
    func load() -> String?
    func save(_ username: String?)
}

/// Keychain-backed session (this device only).
nonisolated struct KeychainSessionStorage: SessionStorage {
    private let service = "zataxo.swift.llm-app.session"
    private let account = "current-user"

    private var query: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: account]
    }

    func load() -> String? {
        var query = query
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess, let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    func save(_ username: String?) {
        SecItemDelete(query as CFDictionary)
        guard let username else { return }
        var attributes = query
        attributes[kSecValueData as String] = Data(username.utf8)
        attributes[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        SecItemAdd(attributes as CFDictionary, nil)
    }
}

/// Signed-in state for the whole app. Every window and the Settings scene observe it.
@Observable
final class AuthStore {
    enum SignInResult: Equatable {
        case success(LocalAccount)
        case invalidCredentials(attemptsLeft: Int)
        case lockedOut(until: Date)
    }

    static let maxAttempts = 5
    static let lockoutDuration: TimeInterval = 30

    private(set) var currentAccount: LocalAccount?
    /// Shown once, right after signing in.
    var pendingWelcome: LocalAccount?
    private(set) var failedAttempts = 0
    private(set) var lockedUntil: Date?

    @ObservationIgnored private let accounts: [LocalAccount]
    @ObservationIgnored private let storage: any SessionStorage
    @ObservationIgnored private let now: () -> Date

    var isSignedIn: Bool { currentAccount != nil }

    init(accounts: [LocalAccount] = LocalAccount.seeded, storage: any SessionStorage = KeychainSessionStorage(), now: @escaping () -> Date = { .now }) {
        self.accounts = accounts
        self.storage = storage
        self.now = now
        if let saved = storage.load() {
            currentAccount = accounts.first { $0.username == saved }
        }
    }

    func signIn(username rawUsername: String, password: String) -> SignInResult {
        if let lockedUntil, lockedUntil > now() {
            return .lockedOut(until: lockedUntil)
        }
        let username = rawUsername.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard let account = accounts.first(where: { $0.username == username }), account.matches(password: password) else {
            failedAttempts += 1
            if failedAttempts >= Self.maxAttempts {
                failedAttempts = 0
                let until = now().addingTimeInterval(Self.lockoutDuration)
                lockedUntil = until
                return .lockedOut(until: until)
            }
            return .invalidCredentials(attemptsLeft: Self.maxAttempts - failedAttempts)
        }
        failedAttempts = 0
        lockedUntil = nil
        currentAccount = account
        pendingWelcome = account
        storage.save(account.username)
        return .success(account)
    }

    func signOut() {
        currentAccount = nil
        pendingWelcome = nil
        storage.save(nil)
    }
}
