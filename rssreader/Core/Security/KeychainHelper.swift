import Foundation
import Security
import LocalAuthentication

public struct KeychainHelper {
    public static let serviceName = "com.seferdesign.rssreader"

    private static var accessibilityAttributes: [String: Any] {
#if os(macOS)
        // kSecAttrAccessible is an iOS-style data protection attribute and can
        // make SecItemAdd fail on macOS keychains.
        return [:]
#else
        return [kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlocked]
#endif
    }

    public static func save(key: String, value: String) throws {
        guard let data = value.data(using: .utf8) else {
            throw KeychainError.encodingFailed
        }

        // Remove any existing items (both synchronizable and local) before saving.
        let deleteQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: key,
            kSecAttrSynchronizable as String: kSecAttrSynchronizableAny,
        ]
        SecItemDelete(deleteQuery as CFDictionary)

        // Prefer iCloud-synced keychain; fall back to local-only when unavailable
        // (e.g. macOS without iCloud Keychain entitlement or iCloud disabled).
        var syncAttributes: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: key,
            kSecValueData as String: data,
            kSecAttrSynchronizable as String: true,
        ]
        syncAttributes.merge(accessibilityAttributes) { _, new in new }

        let syncStatus = SecItemAdd(syncAttributes as CFDictionary, nil)
        if syncStatus == errSecSuccess {
            return
        }
        if syncStatus == errSecDuplicateItem {
            var syncUpdateQuery: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: serviceName,
                kSecAttrAccount as String: key,
                kSecAttrSynchronizable as String: true,
            ]
            syncUpdateQuery.merge(accessibilityAttributes) { _, new in new }

            let syncUpdateAttributes: [String: Any] = [
                kSecValueData as String: data,
            ]
            let syncUpdateStatus = SecItemUpdate(syncUpdateQuery as CFDictionary, syncUpdateAttributes as CFDictionary)
            if syncUpdateStatus == errSecSuccess {
                return
            }
        }

        // iCloud Keychain unavailable — save as a local (non-synchronizable) item.
        var localAttributes: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: key,
            kSecValueData as String: data,
        ]
        localAttributes.merge(accessibilityAttributes) { _, new in new }

        let localStatus = SecItemAdd(localAttributes as CFDictionary, nil)
        if localStatus == errSecDuplicateItem {
            var localUpdateQuery: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: serviceName,
                kSecAttrAccount as String: key,
            ]
            localUpdateQuery.merge(accessibilityAttributes) { _, new in new }

            let localUpdateAttributes: [String: Any] = [
                kSecValueData as String: data,
            ]
            let localUpdateStatus = SecItemUpdate(localUpdateQuery as CFDictionary, localUpdateAttributes as CFDictionary)
            guard localUpdateStatus == errSecSuccess else {
                throw KeychainError.saveFailed(localUpdateStatus)
            }
            return
        }
        guard localStatus == errSecSuccess else {
            throw KeychainError.saveFailed(localStatus)
        }
    }

    public static func retrieve(key: String, allowUserInteraction: Bool = true) throws -> String? {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecAttrSynchronizable as String: kSecAttrSynchronizableAny,
        ]

        if !allowUserInteraction {
    #if os(macOS)
            query[kSecUseAuthenticationUI as String] = kSecUseAuthenticationUIFail
    #else
            let context = LAContext()
            context.interactionNotAllowed = true
            query[kSecUseAuthenticationContext as String] = context
    #endif
        }

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status != errSecItemNotFound else {
            return nil
        }

        guard status == errSecSuccess else {
            throw KeychainError.retrieveFailed(status)
        }

        guard let data = result as? Data, let value = String(data: data, encoding: .utf8) else {
            throw KeychainError.decodingFailed
        }

        return value
    }

    public static func delete(key: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: key,
            kSecAttrSynchronizable as String: kSecAttrSynchronizableAny,
        ]

        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.deleteFailed(status)
        }
    }

    public enum KeychainError: LocalizedError {
        case saveFailed(OSStatus)
        case retrieveFailed(OSStatus)
        case deleteFailed(OSStatus)
        case encodingFailed
        case decodingFailed

        public var errorDescription: String? {
            switch self {
            case .saveFailed(let status):
                return "Failed to save to Keychain (status: \(status))"
            case .retrieveFailed(let status):
                return "Failed to retrieve from Keychain (status: \(status))"
            case .deleteFailed(let status):
                return "Failed to delete from Keychain (status: \(status))"
            case .encodingFailed:
                return "Failed to encode credential for Keychain"
            case .decodingFailed:
                return "Failed to decode credential from Keychain"
            }
        }
    }
}
