import Foundation

enum EmbeddedWebNavigationPolicy {
	private static let embeddedHostSuffixes: [String] = [
		"archivebuttons.com"
	]

	// Keep explicit auth/account route markers embedded so cross-domain sign-in flows
	// can complete in the web view while ordinary external article links still open outside.
	private static let authenticationTokens: Set<String> = [
		"account",
		"accounts",
		"auth",
		"login",
		"oauth",
		"register",
		"session",
		"signin",
		"signup",
		"sso"
	]
	private static let tokenSeparators = CharacterSet.alphanumerics.inverted

	static func shouldStayEmbedded(_ url: URL) -> Bool {
		if let host = url.host?.lowercased() {
			if shouldKeepHostEmbedded(host) || containsAuthenticationToken(host) {
				return true
			}
		}

		let pathSegments = url.pathComponents.map { $0.lowercased() }.filter { $0 != "/" }
		if pathSegments.contains(where: authenticationTokens.contains) {
			return true
		}

		guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
					let queryItems = components.queryItems else {
			return false
		}

		return queryItems.contains(where: { item in
			let name = item.name.lowercased()
			let value = item.value?.lowercased()
			return authenticationTokens.contains(name) || (value.map { authenticationTokens.contains($0) } ?? false)
		})
	}

	private static func containsAuthenticationToken(_ text: String) -> Bool {
		let tokens = text.components(separatedBy: tokenSeparators).filter { !$0.isEmpty }
		return !authenticationTokens.isDisjoint(with: tokens)
	}

	private static func shouldKeepHostEmbedded(_ host: String) -> Bool {
		embeddedHostSuffixes.contains(where: { host == $0 || host.hasSuffix("." + $0) })
		|| isArchiveWildcardHost(host)
	}

	private static func isArchiveWildcardHost(_ host: String) -> Bool {
		let labels = host.split(separator: ".")
		return labels.count >= 2 && labels.first == "archive"
	}
}
