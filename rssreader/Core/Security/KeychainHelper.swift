import Foundation
import Security
import LocalAuthentication

public struct KeychainHelper {
    public static let serviceName = "com.seferdesign.rssreader"

    public static func save(key: String, value: String) throws {
        guard let data = value.data(using: .utf8) else {
            throw KeychainError.encodingFailed
        }

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: key,
            kSecAttrSynchronizable as String: kSecAttrSynchronizableAny,
        ]

        SecItemDelete(query as CFDictionary)

        let attributes: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: key,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlocked,
            kSecAttrSynchronizable as String: true,
        ]

        let status = SecItemAdd(attributes as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw KeychainError.saveFailed(status)
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
            let context = LAContext()
            context.interactionNotAllowed = true
            query[kSecUseAuthenticationContext as String] = context
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
