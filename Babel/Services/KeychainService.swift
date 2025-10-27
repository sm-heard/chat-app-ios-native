import Foundation
import Security

struct AuthenticatedUser: Codable, Equatable {
    var id: String                   // Stream user id (sanitized)
    var appleUserId: String?         // Raw Apple-provided identifier
    var name: String?
    var email: String?
    var identityToken: String?
    var refreshToken: String?
    var authorizationCode: String?
    var language: String?
}

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

    func loadAuthenticatedUser() throws -> AuthenticatedUser? {
        guard let data = try readData() else {
            return nil
        }

        if var user = try? JSONDecoder().decode(AuthenticatedUser.self, from: data) {
            if user.appleUserId == nil {
                user.appleUserId = user.id
            }
            return user
        }

        if let legacyId = String(data: data, encoding: .utf8), !legacyId.isEmpty {
            return AuthenticatedUser(id: legacyId, name: nil, email: nil, language: nil)
        }

        return nil
    }

    func saveAuthenticatedUser(_ user: AuthenticatedUser) throws {
        let data = try JSONEncoder().encode(user)
        try save(data: data)
    }

    func deleteAuthenticatedUser() throws {
        let status = SecItemDelete(baseQuery as CFDictionary)
        switch status {
        case errSecSuccess, errSecItemNotFound:
            return
        default:
            throw KeychainServiceError.unexpectedStatus(status)
        }
    }

    // MARK: - Private helpers

    private func readData() throws -> Data? {
        var query = baseQuery
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

        guard let data = item as? Data else {
            return nil
        }

        return data
    }

    private func save(data: Data) throws {
        var query = baseQuery
        query[kSecValueData as String] = data

        let status = SecItemAdd(query as CFDictionary, nil)

        switch status {
        case errSecSuccess:
            return
        case errSecDuplicateItem:
            let attributes: [String: Any] = [kSecValueData as String: data]
            let updateStatus = SecItemUpdate(baseQuery as CFDictionary, attributes as CFDictionary)
            guard updateStatus == errSecSuccess else {
                throw KeychainServiceError.unexpectedStatus(updateStatus)
            }
        default:
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
