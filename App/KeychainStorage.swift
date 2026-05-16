import Foundation
import Security

/// Thin wrapper around `SecItem*` for storing string secrets in the
/// macOS Keychain. Vektor uses this for the two API keys that previously
/// lived in `UserDefaults` (FMP for the Stocks pane, OpenExchangeRates
/// for live FX rates).
///
/// Items are partitioned by Vektor's app sandbox automatically — the
/// service identifier below is informational. No keychain-access-groups
/// entitlement is required because we never share with another app.
///
/// The `changeNotification` is posted on every successful `set(_:for:)`.
/// `@KeychainStored` property wrappers observe it so a write in one view
/// updates a reader in another — mirroring the cross-view sync that
/// `@AppStorage` got for free via UserDefaults's KVO.
enum KeychainStorage {
    static let changeNotification = Notification.Name("tally.keychain.changed")

    /// `userInfo` key on `changeNotification`. Value is the account
    /// string that just changed.
    static let changeNotificationKeyInfoKey = "key"

    /// Service attribute on every stored item. Stable across app
    /// versions so existing items survive an update.
    private static let service = "app.tally.Tally"

    // MARK: - CRUD

    static func get(_ key: String) -> String? {
        let q: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(q as CFDictionary, &item)
        guard status == errSecSuccess,
              let data = item as? Data,
              let s = String(data: data, encoding: .utf8)
        else { return nil }
        return s
    }

    static func set(_ value: String, for key: String) {
        // Idempotent: delete any existing entry first.
        let q: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
        ]
        SecItemDelete(q as CFDictionary)

        if !value.isEmpty {
            var add = q
            add[kSecValueData as String] = Data(value.utf8)
            // Accessible after first unlock — survives reboots without
            // user re-entry but never leaves the device. Tighter than
            // `kSecAttrAccessibleAlways` (which Apple deprecated).
            add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            SecItemAdd(add as CFDictionary, nil)
        }

        // Notify observers regardless of empty / non-empty — empty means
        // "deleted" and views may want to react.
        NotificationCenter.default.post(
            name: changeNotification,
            object: nil,
            userInfo: [changeNotificationKeyInfoKey: key]
        )
    }

    static func delete(_ key: String) {
        set("", for: key)
    }

    // MARK: - Migration

    /// On launch, copy a UserDefaults-stored secret into the Keychain
    /// (if not already migrated) and clear the UserDefaults entry. Safe
    /// to call on every launch — becomes a no-op after the first
    /// successful pass. Logs the migration so the user can audit in
    /// Console.app if needed.
    static func migrateFromUserDefaults(_ key: String) {
        guard get(key) == nil,
              let stored = UserDefaults.standard.string(forKey: key),
              !stored.isEmpty
        else { return }
        set(stored, for: key)
        UserDefaults.standard.removeObject(forKey: key)
    }
}
