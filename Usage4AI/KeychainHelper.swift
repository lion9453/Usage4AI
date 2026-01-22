import Foundation
import Security

enum KeychainError: Error {
    case itemNotFound
    case unexpectedData
    case unhandledError(status: OSStatus)
    case jsonParsingError
    case tokenNotFound
}

struct KeychainHelper {
    private static let claudeCodeService = "Claude Code-credentials"
    private static let ownService = "Usage4AI-token"
    private static let account = "oauth-token"

    /// 取得 OAuth Token（優先從自己的 keychain 讀取，避免重複詢問密碼）
    static func getOAuthToken() throws -> String {
        // 1. 先嘗試從自己的 keychain 讀取
        if let cachedToken = try? getOwnToken() {
            return cachedToken
        }

        // 2. 從 Claude Code 的 keychain 讀取
        let token = try getClaudeCodeToken()

        // 3. 存到自己的 keychain（下次就不用再問密碼）
        try? saveOwnToken(token)

        return token
    }

    /// 從自己的 keychain 讀取 token
    private static func getOwnToken() throws -> String {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: ownService,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess,
              let data = result as? Data,
              let token = String(data: data, encoding: .utf8) else {
            throw KeychainError.itemNotFound
        }

        return token
    }

    /// 儲存 token 到自己的 keychain
    private static func saveOwnToken(_ token: String) throws {
        let tokenData = token.data(using: .utf8)!

        // 先嘗試刪除舊的
        let deleteQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: ownService,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(deleteQuery as CFDictionary)

        // 新增 token
        let addQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: ownService,
            kSecAttrAccount as String: account,
            kSecValueData as String: tokenData,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock
        ]

        let status = SecItemAdd(addQuery as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw KeychainError.unhandledError(status: status)
        }
    }

    /// 清除自己的 token 快取（token 失效時呼叫）
    static func clearCachedToken() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: ownService,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(query as CFDictionary)
    }

    /// 從 Claude Code 的 keychain 讀取 token
    private static func getClaudeCodeToken() throws -> String {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: claudeCodeService,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status != errSecItemNotFound else {
            throw KeychainError.itemNotFound
        }

        guard status == errSecSuccess else {
            throw KeychainError.unhandledError(status: status)
        }

        guard let data = result as? Data else {
            throw KeychainError.unexpectedData
        }

        guard let jsonString = String(data: data, encoding: .utf8) else {
            throw KeychainError.unexpectedData
        }

        return try extractAccessToken(from: jsonString)
    }

    private static func extractAccessToken(from jsonString: String) throws -> String {
        guard let jsonData = jsonString.data(using: .utf8) else {
            throw KeychainError.jsonParsingError
        }

        guard let json = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any] else {
            throw KeychainError.jsonParsingError
        }

        guard let claudeAiOauth = json["claudeAiOauth"] as? [String: Any],
              let accessToken = claudeAiOauth["accessToken"] as? String else {
            throw KeychainError.tokenNotFound
        }

        return accessToken
    }
}
