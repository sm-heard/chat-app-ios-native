import Foundation
import Security

enum KeychainServiceError: LocalizedError {
    case unexpectedStatus(OSStatus)

    var errorDescription: String? {
        switch self {
        case .unexpectedStatus(let status):
            if let message = SecCopyErrorMessageString(status, nil) as String? {
                return message
            }
            return "Keychain error with status code \(status)."
        }
    }
}

final class KeychainService {
    static let shared = KeychainService()

    private let service = "com.smheard.chat-app-ios-native.device"
    private let account = "babel-device-id"

    private init() {}

    func fetchOrCreateUserId() throws -> String {
        if let existing = try readValue() {
            return existing
        }

        let newValue = UUID().uuidString
        try save(value: newValue)
        return newValue
    }

    private func readValue() throws -> String? {
        var query: [String: Any] = baseQuery
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        query[kSecReturnData as String] = true

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)

        if status == errSecItemNotFound {
            return nil
        }

        guard status == errSecSuccess else {
            throw KeychainServiceError.unexpectedStatus(status)
        }

        guard let data = item as? Data, let value = String(data: data, encoding: .utf8) else {
            return nil
        }

        return value
    }

    private func save(value: String) throws {
        let data = Data(value.utf8)

        var query: [String: Any] = baseQuery
        query[kSecValueData as String] = data

        let status = SecItemAdd(query as CFDictionary, nil)

        guard status == errSecSuccess else {
            throw KeychainServiceError.unexpectedStatus(status)
        }
    }

    private var baseQuery: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        ]
    }
}

