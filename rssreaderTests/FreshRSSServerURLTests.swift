import Foundation
import Testing
@testable import SDC_RSS

struct FreshRSSServerURLTests {
    @Test(arguments: [
        ("example.com", "https://example.com"),
        ("  https://example.com/  ", "https://example.com"),
        ("\"https://example.com\"", "https://example.com"),
        ("https://https://example.com", "https://example.com"),
        ("http://http://example.com", "http://example.com"),
        ("https:/example.com", "https://example.com"),
        ("https://example.com/api/greader.php", "https://example.com"),
        ("https://example.com/rss/api/greader.php/", "https://example.com/rss"),
        ("example.com:8443/rss/", "https://example.com:8443/rss"),
        ("", ""),
    ])
    func normalizesWhateverTheUserTyped(input: String, expected: String) {
        #expect(FreshRSSServerURL.normalize(input) == expected)
    }

    @Test(arguments: ["192.168.1.5", "100.64.0.1", "::1", "nas", "nas.local", "NAS.LOCAL"])
    func allowsCleartextWhereAppTransportSecurityDoes(host: String) {
        #expect(FreshRSSServerURL.allowsCleartext(host: host))
    }

    @Test(arguments: ["example.com", "rss.example.com", "host.ts.net", "host.vpn.example.com"])
    func blocksCleartextToInternetHosts(host: String) {
        #expect(!FreshRSSServerURL.allowsCleartext(host: host))
    }

    @Test func validationOnlyAppliesToHTTP() throws {
        try FreshRSSServerURL.validateTransportSecurity(of: #require(URL(string: "https://example.com")))
        try FreshRSSServerURL.validateTransportSecurity(of: #require(URL(string: "http://192.168.1.5")))

        #expect(throws: FreshRSSError.self) {
            try FreshRSSServerURL.validateTransportSecurity(of: #require(URL(string: "http://example.com")))
        }
    }

    @Test func insecureErrorExplainsTheFix() {
        let message = FreshRSSError.insecureServerURL(host: "example.com").localizedDescription
        #expect(message.contains("example.com"))
        #expect(message.contains("https://"))
    }

    @Test func detectsVPNStyleHosts() {
        #expect(FreshRSSServerURL.isVPNStyleHost("rss.vpn.example.com"))
        #expect(FreshRSSServerURL.isVPNStyleHost("box.tail1234.ts.net"))
        #expect(!FreshRSSServerURL.isVPNStyleHost("rss.example.com"))
        #expect(!FreshRSSServerURL.isVPNStyleHost(nil))
    }

    @Test func buildsAPIURLsUnderTheNormalizedBase() {
        let client = FreshRSSAPIClient(serverURL: "example.com/rss/", transport: FakeTransport { _ in (200, Data()) })
        #expect(client.gReaderURL(["reader", "api", "0", "token"])?.absoluteString == "https://example.com/rss/api/greader.php/reader/api/0/token")
        #expect(FreshRSSAPIClient(serverURL: "", transport: FakeTransport { _ in (200, Data()) }).gReaderURL(["x"]) == nil)
    }
}
