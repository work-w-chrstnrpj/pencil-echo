import Foundation
import Security

/// Exact normalized base URL + preset identity; a credential cannot migrate to
/// another host, path, port or region by changing a provider setting.
struct ProviderIdentity: Hashable, Sendable {
    let presetID: String
    let baseURL: URL

    init(presetID: String, baseURL: URL) throws {
        guard !presetID.isEmpty, var parts = URLComponents(url: baseURL, resolvingAgainstBaseURL: false),
              parts.scheme?.lowercased() == "https", let host = parts.host, !host.isEmpty,
              parts.user == nil, parts.password == nil, parts.query == nil, parts.fragment == nil else {
            throw AIError.invalidRequest
        }
        parts.scheme = "https"
        parts.host = host.lowercased()
        while parts.path.hasSuffix("/") { parts.path.removeLast() }
        guard let url = parts.url else { throw AIError.invalidRequest }
        self.presetID = presetID
        self.baseURL = url
    }

    var account: String { presetID + "\n" + baseURL.absoluteString }
}

protocol ProviderCredentials: Sendable {
    func read(for identity: ProviderIdentity) throws -> String?
}

struct KeychainStore: ProviderCredentials {
    private let service = "com.chrixcrusher.pencilecho.ai-keys"

    private func query(_ identity: ProviderIdentity) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: identity.account,
         kSecAttrSynchronizable as String: false]
    }

    func read(for identity: ProviderIdentity) throws -> String? {
        var request = query(identity)
        request[kSecReturnData as String] = true
        request[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(request as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess else { throw AIError.keychain(status) }
        guard let data = result as? Data, let key = String(data: data, encoding: .utf8) else { throw AIError.invalidCredentials }
        return key
    }

    func save(_ key: String, for identity: ProviderIdentity) throws {
        let key = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty, key.utf8.count <= 4_096, !key.contains("\r"), !key.contains("\n") else { throw AIError.invalidCredentials }
        let attributes: [String: Any] = [kSecValueData as String: Data(key.utf8),
                                        kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly]
        let existing = query(identity)
        var status = SecItemUpdate(existing as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            status = SecItemAdd(existing.merging(attributes) { _, new in new } as CFDictionary, nil)
        }
        guard status == errSecSuccess else { throw AIError.keychain(status) }
    }

    func delete(for identity: ProviderIdentity) throws {
        let status = SecItemDelete(query(identity) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw AIError.keychain(status) }
    }
}
