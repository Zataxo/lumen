import Foundation
import Synchronization
import Testing
@testable import llm_app

/// In-memory stand-in for the Keychain session.
final class MemorySessionStorage: SessionStorage, @unchecked Sendable {
    private let value = Mutex<String?>(nil)
    init(_ initial: String? = nil) { value.withLock { $0 = initial } }
    func load() -> String? { value.withLock { $0 } }
    func save(_ username: String?) { value.withLock { $0 = username } }
}

@MainActor
@Suite("Sign-in")
struct AuthTests {
    @Test(arguments: ["Zataxo", "Zaad"])
    func seededAccountsSignIn(username: String) {
        let auth = AuthStore(storage: MemorySessionStorage())
        #expect(auth.signIn(username: username, password: "Admin123") == .success(auth.currentAccount!))
        #expect(auth.isSignedIn)
        #expect(auth.currentAccount?.displayName == username)
        #expect(auth.pendingWelcome?.displayName == username)
    }

    @Test func usernameIsCaseInsensitiveAndTrimmed() {
        let auth = AuthStore(storage: MemorySessionStorage())
        if case .success = auth.signIn(username: "  ZATAXO ", password: "Admin123") {} else { Issue.record("Expected success") }
    }

    @Test(arguments: [("Zataxo", "admin123"), ("Zataxo", "Admin1234"), ("Zataxo", ""), ("nobody", "Admin123"), ("", "Admin123")])
    func wrongCredentialsAreRejected(username: String, password: String) {
        let auth = AuthStore(storage: MemorySessionStorage())
        #expect(auth.signIn(username: username, password: password) == .invalidCredentials(attemptsLeft: AuthStore.maxAttempts - 1))
        #expect(!auth.isSignedIn)
    }

    @Test func locksOutAfterRepeatedFailuresThenRecovers() {
        var clock = Date(timeIntervalSince1970: 1_000)
        let auth = AuthStore(storage: MemorySessionStorage(), now: { clock })
        for _ in 1..<AuthStore.maxAttempts {
            _ = auth.signIn(username: "Zaad", password: "nope")
        }
        #expect(auth.signIn(username: "Zaad", password: "nope") == .lockedOut(until: clock.addingTimeInterval(AuthStore.lockoutDuration)))
        // Even the right password is refused while locked out.
        if case .lockedOut = auth.signIn(username: "Zaad", password: "Admin123") {} else { Issue.record("Expected lockout") }
        clock = clock.addingTimeInterval(AuthStore.lockoutDuration + 1)
        if case .success = auth.signIn(username: "Zaad", password: "Admin123") {} else { Issue.record("Expected success after lockout") }
    }

    @Test func sessionIsRememberedAndClearedOnSignOut() {
        let storage = MemorySessionStorage()
        let first = AuthStore(storage: storage)
        _ = first.signIn(username: "Zaad", password: "Admin123")
        #expect(storage.load() == "zaad")

        let relaunched = AuthStore(storage: storage)
        #expect(relaunched.currentAccount?.displayName == "Zaad")
        #expect(relaunched.pendingWelcome == nil) // no welcome on a remembered session

        relaunched.signOut()
        #expect(storage.load() == nil)
        #expect(!AuthStore(storage: storage).isSignedIn)
    }

    @Test func unknownStoredSessionIsIgnored() {
        #expect(!AuthStore(storage: MemorySessionStorage("mallory")).isSignedIn)
    }

    @Test func passwordsAreNotStoredInPlainText() {
        for account in LocalAccount.seeded {
            #expect(!account.passwordHash.contains("Admin123"))
            #expect(account.passwordHash.count == 64)
        }
    }
}

@Suite("Fresh install")
struct FreshInstallGuardTests {
    private func defaults() -> UserDefaults {
        let name = "lumen.tests.\(UUID().uuidString)"
        return UserDefaults(suiteName: name)!
    }

    @Test func clearsKeychainOnFreshInstall() {
        let defaults = defaults()
        var cleared = 0
        #expect(FreshInstallGuard.run(defaults: defaults, hasExistingData: false) { cleared += 1 })
        #expect(cleared == 1)
        // Second launch: marker present, nothing cleared.
        #expect(!FreshInstallGuard.run(defaults: defaults, hasExistingData: false) { cleared += 1 })
        #expect(cleared == 1)
    }

    @Test func keepsSessionForExistingUsersUpdating() {
        var cleared = false
        #expect(!FreshInstallGuard.run(defaults: defaults(), hasExistingData: true) { cleared = true })
        #expect(!cleared)
    }
}
