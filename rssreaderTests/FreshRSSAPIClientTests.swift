import Foundation
import Testing
@testable import SDC_RSS

struct FreshRSSAPIClientTests {
    // MARK: Login

    @Test func loginReturnsTheAuthToken() async throws {
        let transport = FakeTransport { _ in (200, Data("SID=ignored\nAuth=abc123\n")) }
        let token = try await FreshRSSAPIClient.test(transport).login(username: "reader", password: "se cret")

        #expect(token == "abc123")
        let request = try #require(transport.requests.first)
        #expect(request.httpMethod == "POST")
        #expect(request.url?.absoluteString == "https://rss.example.com/api/greader.php/accounts/ClientLogin")
        #expect(String(data: try #require(request.httpBody), encoding: .utf8) == "Email=reader&Passwd=se%20cret")
    }

    @Test func loginEscapesSpecialCharactersInCredentials() async throws {
        let transport = FakeTransport { _ in (200, Data("Auth=abc\n")) }

        _ = try await FreshRSSAPIClient.test(transport).login(username: "me@example.com", password: "p&ss=w+rd%1 é")

        let body = String(data: try #require(transport.requests.first?.httpBody), encoding: .utf8)
        #expect(body == "Email=me%40example.com&Passwd=p%26ss%3Dw%2Brd%251%20%C3%A9")
    }

    @Test func rejectedCredentialsThrowAuthenticationFailed() async {
        let transport = FakeTransport { _ in (403, Data("Error=BadAuthentication")) }

        await #expect(throws: FreshRSSError.self) {
            try await FreshRSSAPIClient.test(transport).login(username: "reader", password: "wrong")
        }
        #expect(transport.requests.count == 1, "Bad credentials must not be retried")
    }

    @Test func missingAuthLineThrowsAuthenticationFailed() async {
        let transport = FakeTransport { _ in (200, Data("SID=only\n")) }

        await #expect(throws: FreshRSSError.self) {
            try await FreshRSSAPIClient.test(transport).login(username: "reader", password: "secret")
        }
    }

    @Test func loginRetriesDNSFailuresThenSucceeds() async throws {
        let counter = CallCounter()
        let transport = FakeTransport { _ in
            if counter.next() < 3 { throw URLError(.cannotFindHost) }
            return (200, Data("Auth=late\n"))
        }

        let token = try await FreshRSSAPIClient.test(transport).login(username: "reader", password: "secret")

        #expect(token == "late")
        #expect(transport.requests.count == 3)
    }

    @Test func loginGivesUpAfterRepeatedDNSFailures() async {
        let transport = FakeTransport { _ in throw URLError(.dnsLookupFailed) }

        await #expect(throws: URLError.self) {
            try await FreshRSSAPIClient.test(transport).login(username: "reader", password: "secret")
        }
        #expect(transport.requests.count == 4)
    }

    @Test func loginRejectsCleartextInternetHostsWithoutSendingARequest() async {
        let transport = FakeTransport { _ in (200, Data("Auth=x")) }

        await #expect(throws: FreshRSSError.self) {
            try await FreshRSSAPIClient.test(transport, serverURL: "http://rss.example.com")
                .login(username: "reader", password: "secret")
        }
        #expect(transport.requests.isEmpty)
    }

    @Test func loginAllowsCleartextToLocalNetworkHosts() async throws {
        let transport = FakeTransport { _ in (200, Data("Auth=lan")) }
        let token = try await FreshRSSAPIClient.test(transport, serverURL: "http://192.168.1.20:8080")
            .login(username: "reader", password: "secret")

        #expect(token == "lan")
    }

    // MARK: Reading

    @Test func subscriptionsAreSortedIgnoringCase() async throws {
        let transport = FakeTransport { _ in
            (200, Data(#"{"subscriptions":[{"id":"feed/2","title":"banana"},{"id":"feed/1","title":"Apple"},{"id":"feed/3"}]}"#))
        }

        let subscriptions = try await FreshRSSAPIClient.test(transport).fetchSubscriptions(authToken: "tok")

        #expect(subscriptions.map(\.title) == ["Apple", "banana", "feed/3"])
        #expect(transport.requests.first?.value(forHTTPHeaderField: "Authorization") == "GoogleLogin auth=tok")
    }

    @Test func unreadStreamExcludesReadItems() async throws {
        let transport = FakeTransport { _ in (200, Data(#"{"items":[],"continuation":"next"}"#)) }

        let page = try await FreshRSSAPIClient.test(transport)
            .fetchStreamPage(authToken: "tok", mode: .new, continuation: "c1", todayCutoff: .now)

        #expect(page.continuation == "next")
        let query = try #require(transport.requests.first?.url?.query)
        #expect(query.contains("n=100"))
        #expect(query.contains("xt=user/-/state/com.google/read"))
        #expect(query.contains("c=c1"))
    }

    @Test func todayStreamSendsTheCutoffTimestamp() async throws {
        let transport = FakeTransport { _ in (200, Data(#"{"items":[]}"#)) }

        _ = try await FreshRSSAPIClient.test(transport).fetchStreamPage(
            authToken: "tok",
            mode: .today,
            continuation: nil,
            todayCutoff: Date(timeIntervalSince1970: 1_700_000_000)
        )

        let query = try #require(transport.requests.first?.url?.query)
        #expect(query.contains("ot=1700000000"))
        #expect(query.contains("n=250"))
    }

    @Test func serverErrorsAreReported() async {
        let transport = FakeTransport { _ in (500, Data()) }

        do {
            _ = try await FreshRSSAPIClient.test(transport)
                .fetchStreamPage(authToken: "tok", mode: .archive, continuation: nil, todayCutoff: .now)
            Issue.record("Expected a server error")
        } catch {
            #expect(error.localizedDescription == FreshRSSError.serverError(500).localizedDescription)
        }
        #expect(transport.requests.count == 1, "HTTP 500 is not retried")
    }

    // MARK: Retries

    @Test func transientStatusesAreRetriedWithBackoff() async throws {
        let counter = CallCounter()
        let transport = FakeTransport { _ in
            counter.next() < 3 ? (503, Data()) : (200, Data(#"{"items":[]}"#))
        }

        let page = try await FreshRSSAPIClient.test(transport)
            .fetchStreamPage(authToken: "tok", mode: .new, continuation: nil, todayCutoff: .now)

        #expect(page.items.isEmpty)
        #expect(transport.requests.count == 3)
    }

    @Test func persistentTransientFailuresStopAfterTheAttemptLimit() async {
        let transport = FakeTransport { _ in throw URLError(.timedOut) }

        await #expect(throws: URLError.self) {
            try await FreshRSSAPIClient.test(transport).fetchSubscriptions(authToken: "tok")
        }
        #expect(transport.requests.count == RetryPolicy().maxAttempts)
    }

    @Test func nonTransientNetworkErrorsAreNotRetried() async {
        let transport = FakeTransport { _ in throw URLError(.badURL) }

        await #expect(throws: URLError.self) {
            try await FreshRSSAPIClient.test(transport).fetchSubscriptions(authToken: "tok")
        }
        #expect(transport.requests.count == 1)
    }

    // MARK: Writing

    @Test func actionTokenIsTrimmed() async throws {
        let transport = FakeTransport { _ in (200, Data("  action-token \n")) }
        let token = try await FreshRSSAPIClient.test(transport).fetchActionToken(authToken: "tok")
        #expect(token == "action-token")
    }

    @Test func markingReadAddsTheReadTagAndUnreadRemovesIt() async throws {
        let transport = FakeTransport { _ in (200, Data("OK")) }
        let client = FreshRSSAPIClient.test(transport)

        let read = await client.setReadState(itemID: "item-1", isRead: true, authToken: "tok", actionToken: "act")
        let unread = await client.setReadState(itemID: "item-1", isRead: false, authToken: "tok", actionToken: "act")

        #expect(read == .succeeded)
        #expect(unread == .succeeded)
        let bodies = transport.requests.compactMap { $0.httpBody.flatMap { String(data: $0, encoding: .utf8) } }
        #expect(bodies[0] == "i=item-1&a=user%2F-%2Fstate%2Fcom.google%2Fread&T=act")
        #expect(bodies[1] == "i=item-1&r=user%2F-%2Fstate%2Fcom.google%2Fread&T=act")
    }

    @Test func readActionOutcomesDistinguishTokenRejection() async {
        let statuses = ["ok": 200, "stale": 401, "broken": 500]
        let transport = FakeTransport { request in
            let body = String(data: request.httpBody ?? Data(), encoding: .utf8) ?? ""
            let status = statuses.first { body.hasPrefix("i=\($0.key)&") }?.value ?? 500
            return (status, Data())
        }

        let outcomes = await FreshRSSAPIClient.test(transport)
            .setReadState(itemIDs: ["ok", "stale", "broken"], isRead: true, authToken: "tok", actionToken: "act")

        #expect(outcomes == ["ok": .succeeded, "stale": .actionTokenRejected, "broken": .failed])
    }

    @Test func largeBatchesAreAllProcessed() async {
        let ids = (1...25).map { "item-\($0)" }
        let transport = FakeTransport { _ in (200, Data()) }

        let outcomes = await FreshRSSAPIClient.test(transport)
            .setReadState(itemIDs: ids, isRead: true, authToken: "tok", actionToken: "act", maxConcurrentRequests: 3)

        #expect(Set(outcomes.keys) == Set(ids))
        #expect(outcomes.values.allSatisfy { $0 == .succeeded })
        #expect(transport.requests.count == ids.count)
    }

    // MARK: Preflight

    @Test func preflightTreatsNonDNSFailuresAsResolvedHosts() async {
        let transport = FakeTransport { _ in throw URLError(.cannotConnectToHost) }
        let result = await FreshRSSAPIClient.test(transport).probeHost()

        #expect(result.success)
        #expect(result.urlErrorCode == URLError.cannotConnectToHost.rawValue)
    }

    @Test func preflightReportsDNSFailure() async {
        let transport = FakeTransport { _ in throw URLError(.cannotFindHost) }
        let result = await FreshRSSAPIClient.test(transport).probeHost()

        #expect(!result.success)
        #expect(result.message.contains("rss.example.com"))
    }
}
