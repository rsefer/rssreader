import AppKit
import FoundationModels
import WebKit

@MainActor
private final class PageLoader {
	let controller: ArticleSummaryController
	let pageID = "test-page"
	let coordinator: WebView.WebCoordinator

	init(controller: ArticleSummaryController) {
		self.controller = controller
		coordinator = WebView.WebCoordinator(summaryController: controller)
	}

	func load(_ html: String, in webView: WKWebView) async throws {
		let revision = controller.pageRevision
		coordinator.updateLastItemID(pageID)
		webView.navigationDelegate = coordinator
		coordinator.currentNavigation = webView.loadHTMLString(
			html, baseURL: URL(string: "https://example.test/article")!
		)
		try await waitUntil { controller.pageRevision >= revision + 2 }
	}
}

@MainActor
private func waitUntil(timeout: Duration = .seconds(30), _ predicate: () -> Bool) async throws {
	let clock = ContinuousClock()
	let deadline = clock.now + timeout
	while !predicate() {
		if clock.now >= deadline { throw CheckError.timeout }
		try await Task.sleep(for: .milliseconds(50))
	}
}

private enum CheckError: Error {
	case timeout
	case failed(String)
}

@MainActor
private func result(_ controller: ArticleSummaryController, timeout: Duration = .seconds(30)) async throws -> [String] {
	try await waitUntil(timeout: timeout) {
		switch controller.state {
		case .ready, .failed: return true
		case .waiting, .generating: return false
		}
	}
	switch controller.state {
	case .ready(let paragraphs): return paragraphs
	case .failed(let message): throw CheckError.failed(message)
	case .waiting, .generating: throw CheckError.timeout
	}
}

private func check(_ condition: @autoclosure () -> Bool, _ message: String) throws {
	if !condition() { throw CheckError.failed(message) }
}

@main
struct ArticleSummaryChecks {
	@MainActor
	static func main() async throws {
		_ = NSApplication.shared
		let text = String(repeating: "A long article with Unicode 📰 and 日本語. ", count: 300)
		let chunks = ArticleSummaryText.chunks(text)
		try check(chunks.joined() == text, "Chunking lost or changed article text")
		try check(chunks.allSatisfy { $0.utf8.count <= ArticleSummaryText.maximumChunkBytes }, "Chunk exceeded the byte limit")
		try check(ArticleSummaryText.chunks("").isEmpty, "Empty input produced a chunk")
		let unbroken = String(repeating: "é", count: 3_000)
		try check(ArticleSummaryText.chunks(unbroken).joined() == unbroken, "Chunking lost an unbroken word")

		guard SystemLanguageModel.default.isAvailable else {
			print("Chunk checks passed; model-dependent checks skipped because Apple Intelligence is unavailable.")
			return
		}

		let html = """
		<html><body><nav>Navigation should not be summarized.</nav><article>
		<h1>A community garden</h1>
		<p>Residents opened a community garden on a previously vacant city lot.</p>
		<div>Volunteers prepared the soil.</div>
		<p>The project provides vegetables and offers gardening classes for local families.</p>
		</article></body></html>
		"""
		let changedHTML = html.replacingOccurrences(of: "vegetables", with: "fruit")
		var generationCount = 0
		let controller = ArticleSummaryController { article in
			generationCount += 1
			try await Task.sleep(for: .milliseconds(100))
			try check(article.contains("community garden"), "Article text was not extracted")
			try check(article.contains("Volunteers prepared the soil."), "Non-paragraph article text was lost")
			try check(!article.contains("Navigation should not"), "Navigation leaked into the article")
			return ["Summary \(generationCount)"]
		}
		let loader = PageLoader(controller: controller)
		let webView = WKWebView()
		try await loader.load(html, in: webView)
		controller.requestSummary(for: loader.pageID)
		controller.requestSummary(for: loader.pageID)
		let first = try await result(controller)
		controller.requestSummary(for: loader.pageID)
		_ = try await result(controller)
		try check(generationCount == 1, "Toggling views regenerated the summary")

		try await loader.load(html, in: webView)
		controller.requestSummary(for: loader.pageID)
		let cached = try await result(controller)
		try check(cached == first && generationCount == 1, "Reloading identical content missed the cache")

		_ = try await webView.evaluateJavaScript("document.querySelector('p:last-child').textContent += ' Updated.'")
		controller.requestSummary(for: loader.pageID)
		_ = try await result(controller)
		try check(generationCount == 2, "Changed live page content reused a stale summary")

		try await loader.load(changedHTML, in: webView)
		controller.requestSummary(for: loader.pageID)
		_ = try await result(controller)
		try check(generationCount == 3, "Changed page content reused a stale summary")

		try await loader.load("<html><body>No article here.</body></html>", in: webView)
		controller.requestSummary(for: loader.pageID)
		do {
			_ = try await result(controller)
			throw CheckError.failed("A page without an article was summarized")
		} catch CheckError.failed(let message) where message.contains("No article text") {
		}

		var started = false
		let changingController = ArticleSummaryController { article in
			if article.contains("vegetables") {
				started = true
				try await Task.sleep(for: .seconds(5))
				return ["Old page"]
			}
			return ["New page"]
		}
		let changingLoader = PageLoader(controller: changingController)
		try await changingLoader.load(html, in: webView)
		changingController.requestSummary(for: changingLoader.pageID)
		try await waitUntil { started }
		try await changingLoader.load(changedHTML, in: webView)
		changingController.requestSummary(for: changingLoader.pageID)
		let changed = try await result(changingController)
		try check(changed == ["New page"], "A stale summary replaced the new page")

		if CommandLine.arguments.contains("--real-model") {
			let actualController = ArticleSummaryController()
			let actualLoader = PageLoader(controller: actualController)
			let longHTML = """
			<html><body><article><h1>A community garden</h1>
			\(String(repeating: "<p>Residents opened a community garden on a vacant lot. Volunteers prepared the soil, grew vegetables, and taught gardening to local families.</p>", count: 25))
			</article></body></html>
			"""
			try await actualLoader.load(longHTML, in: webView)
			actualController.requestSummary(for: actualLoader.pageID)
			let paragraphs = try await result(actualController, timeout: .seconds(180))
			try check((1...3).contains(paragraphs.count), "Model returned the wrong number of paragraphs")
			try check(paragraphs.allSatisfy { !$0.isEmpty }, "Model returned an empty paragraph")
			print("On-device model produced \(paragraphs.count) paragraph(s).")
		}
		print("Article summary checks passed.")
	}
}
