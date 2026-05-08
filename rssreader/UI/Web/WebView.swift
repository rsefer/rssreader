import Foundation
import SwiftUI
import WebKit

#if os(macOS)
import AppKit
#elseif os(iOS)
import UIKit
#endif

private enum EmbeddedWebNavigationPolicy {
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

	static func shouldOpenExternally(_ navigationAction: WKNavigationAction) -> Bool {
		guard navigationAction.navigationType == .linkActivated,
					let url = navigationAction.request.url else {
			return false
		}

		return !shouldStayEmbedded(url)
	}

	private static func shouldStayEmbedded(_ url: URL) -> Bool {
		let candidateComponents = [
			url.host?.lowercased() ?? "",
			url.path.lowercased(),
			url.query?.lowercased() ?? ""
		]

		return candidateComponents.contains(where: containsAuthenticationToken)
	}

	private static func containsAuthenticationToken(_ text: String) -> Bool {
		let tokens = text.components(separatedBy: CharacterSet.alphanumerics.inverted)
			.filter { !$0.isEmpty }
		return !authenticationTokens.isDisjoint(with: tokens)
	}
}

/// Wraps WKWebView for use in SwiftUI.
/// Supports loading either a remote URL or a local HTML string.
#if os(macOS)
struct WebView: NSViewRepresentable {

		enum Source: Equatable {
				case url(URL)
				case html(String)
		}

		let source: Source
		/// A unique identifier so `updateNSView` only reloads when the source actually changes.
		let itemID: String

		func makeCoordinator() -> Coordinator {
				Coordinator()
		}

		func makeNSView(context: Context) -> WKWebView {
				let config = WKWebViewConfiguration()
				let webView = WKWebView(frame: .zero, configuration: config)
				webView.navigationDelegate = context.coordinator
				webView.allowsMagnification = true
				return webView
		}

		func updateNSView(_ webView: WKWebView, context: Context) {
				guard context.coordinator.lastItemID != itemID else { return }
				context.coordinator.lastItemID = itemID

				switch source {
				case .url(let url):
						webView.load(URLRequest(url: url))
				case .html(let html):
						webView.loadHTMLString(html, baseURL: nil)
				}
		}

		// MARK: - Coordinator

		final class Coordinator: NSObject, WKNavigationDelegate {
				var lastItemID = ""

			func webView(_ webView: WKWebView,
										 decidePolicyFor navigationAction: WKNavigationAction,
										 decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
						// Open link clicks in the default browser; allow the initial page load
						if EmbeddedWebNavigationPolicy.shouldOpenExternally(navigationAction),
							 let url = navigationAction.request.url {
								NSWorkspace.shared.open(url)
								decisionHandler(.cancel)
								return
						}
						decisionHandler(.allow)
				}
		}
}

#else
struct WebView: UIViewRepresentable {

		enum Source: Equatable {
				case url(URL)
				case html(String)
		}

		let source: Source
		/// A unique identifier so `updateUIView` only reloads when the source actually changes.
		let itemID: String

		func makeCoordinator() -> Coordinator {
				Coordinator()
		}

		func makeUIView(context: Context) -> WKWebView {
				let config = WKWebViewConfiguration()
				let webView = WKWebView(frame: .zero, configuration: config)
				webView.navigationDelegate = context.coordinator
				return webView
		}

		func updateUIView(_ webView: WKWebView, context: Context) {
				guard context.coordinator.lastItemID != itemID else { return }
				context.coordinator.lastItemID = itemID

				switch source {
				case .url(let url):
						webView.load(URLRequest(url: url))
				case .html(let html):
						webView.loadHTMLString(html, baseURL: nil)
				}
		}

		final class Coordinator: NSObject, WKNavigationDelegate {
				var lastItemID = ""

				func webView(_ webView: WKWebView,
										 decidePolicyFor navigationAction: WKNavigationAction,
										 decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
						if EmbeddedWebNavigationPolicy.shouldOpenExternally(navigationAction),
							 let url = navigationAction.request.url {
								UIApplication.shared.open(url)
								decisionHandler(.cancel)
								return
						}
						decisionHandler(.allow)
				}
		}
}
#endif

/// Loads a webpage, extracts the main content block, and renders a clean reader view.
#if os(macOS)
struct ReaderWebView: NSViewRepresentable {
				let url: URL
				let itemID: String
		let fallbackHTML: String?

				func makeCoordinator() -> Coordinator {
								Coordinator(parent: self)
				}

				func makeNSView(context: Context) -> WKWebView {
								let config = WKWebViewConfiguration()
								let webView = WKWebView(frame: .zero, configuration: config)
								webView.navigationDelegate = context.coordinator
								webView.allowsMagnification = true
								return webView
				}

				func updateNSView(_ webView: WKWebView, context: Context) {
								context.coordinator.parent = self
								guard context.coordinator.lastItemID != itemID else { return }

								context.coordinator.lastItemID = itemID
								context.coordinator.didLoadReaderHTML = false
								webView.load(URLRequest(url: url))
				}

				final class Coordinator: NSObject, WKNavigationDelegate {
								var parent: ReaderWebView
								var lastItemID = ""
								var didLoadReaderHTML = false

								init(parent: ReaderWebView) {
												self.parent = parent
								}

								func webView(_ webView: WKWebView,
																				 decidePolicyFor navigationAction: WKNavigationAction,
																				 decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
												// Open link clicks in the default browser; allow the initial page load
												if EmbeddedWebNavigationPolicy.shouldOpenExternally(navigationAction),
													 let url = navigationAction.request.url {
														NSWorkspace.shared.open(url)
														decisionHandler(.cancel)
														return
												}
												decisionHandler(.allow)
								}

								func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
												guard !didLoadReaderHTML else { return }

												webView.evaluateJavaScript(Self.extractionScript) { [weak self, weak webView] result, _ in
																guard let self, let webView else { return }

																let extractedBody = (result as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
												let extractedTextLength = Self.plainTextLength(fromHTML: extractedBody)
												let shouldUseExtracted = extractedTextLength >= 450

												self.didLoadReaderHTML = true

												if shouldUseExtracted {
														let readerHTML = Self.readerHTML(body: extractedBody, sourceURL: self.parent.url)
														webView.loadHTMLString(readerHTML, baseURL: self.parent.url.deletingLastPathComponent())
														return
												}

												let fallbackBody = (self.parent.fallbackHTML ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
												if !fallbackBody.isEmpty {
														let readerHTML = Self.readerHTML(body: fallbackBody, sourceURL: self.parent.url)
														webView.loadHTMLString(readerHTML, baseURL: self.parent.url.deletingLastPathComponent())
														return
												}

												// Last resort: keep the original page already loaded in this web view.
												return
												}
								}

								private static func plainTextLength(fromHTML html: String) -> Int {
										guard !html.isEmpty else { return 0 }

										let withoutTags = html.replacingOccurrences(
												of: "<[^>]+>",
												with: " ",
												options: .regularExpression
										)
										let normalized = withoutTags.replacingOccurrences(
												of: "\\s+",
												with: " ",
												options: .regularExpression
										)
										return normalized.trimmingCharacters(in: .whitespacesAndNewlines).count
								}

								private static let extractionScript = #"""
								(() => {
										const root = document.cloneNode(true);
										root.querySelectorAll('script,style,noscript,iframe,header,footer,nav,aside,form').forEach(el => el.remove());

										const preferred = [
												root.querySelector('article'),
												root.querySelector('main'),
												root.querySelector('[role="main"]'),
												root.querySelector('.post-content, .article-content, .entry-content, .story-body, .main-content')
										].filter(Boolean);

										const score = (el) => {
												const text = (el.innerText || '').replace(/\s+/g, ' ').trim();
												const pCount = el.querySelectorAll('p').length;
												return text.length + pCount * 120;
										};

										let best = null;
										let bestScore = -1;

										for (const candidate of preferred) {
												const s = score(candidate);
												if (s > bestScore) {
														best = candidate;
														bestScore = s;
												}
										}

										if (!best) {
												const candidates = root.querySelectorAll('article, main, section, div');
												for (const candidate of candidates) {
														if (candidate.querySelectorAll('p').length < 2) continue;
														const s = score(candidate);
														if (s > bestScore) {
																best = candidate;
																bestScore = s;
														}
												}
										}

										if (!best) return '';

										best.querySelectorAll('script,style,noscript,iframe,form,button,input,svg').forEach(el => el.remove());
										return best.innerHTML || '';
								})();
								"""#

								private static func readerHTML(body: String, sourceURL: URL) -> String {
												"""
												<!DOCTYPE html>
												<html>
												<head>
												<meta charset="UTF-8">
												<meta name="viewport" content="width=device-width, initial-scale=1">
												<style>
												:root { color-scheme: light dark; }
												*, *::before, *::after { box-sizing: border-box; }
												body {
																font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Georgia, serif;
																font-size: 18px;
																line-height: 1.8;
																width: 100%;
																max-width: 760px;
																margin: 0 auto;
																padding: 28px 24px 64px;
																color: #1b1b1b;
																background: #ffffff;
												}
												@media (max-width: 820px) {
																body {
																				max-width: none;
																				margin: 0;
																				padding: 22px 16px 48px;
																}
												}
												.source {
																display: inline-block;
																margin-bottom: 18px;
																font-size: 12px;
																color: #6b7280;
																text-decoration: none;
																border: 1px solid #e5e7eb;
																border-radius: 999px;
																padding: 5px 10px;
												}
												h1, h2, h3, h4 { line-height: 1.28; margin-top: 1.45em; }
												img, video, iframe { max-width: 100%; height: auto; border-radius: 8px; }
												pre {
																background: #f5f5f6;
																border-radius: 8px;
																padding: 14px 16px;
																overflow-x: auto;
												}
												blockquote {
																border-left: 3px solid #d5d5d5;
																margin: 1.1em 0;
																padding: 2px 0 2px 14px;
																color: #666;
												}
												@media (prefers-color-scheme: dark) {
																body { color: #e6e6e6; background: #1c1c1e; }
																a { color: #7cb7ff; }
																pre { background: #2d2d31; }
																blockquote { border-color: #4a4a4f; color: #b3b3b8; }
																.source { color: #c0c4ca; border-color: #414247; }
												}
												</style>
												</head>
												<body>
												<a class="source" href="\(sourceURL.absoluteString)">Source</a>
												\(body)
												</body>
												</html>
												"""
								}
				}
}
#else
struct ReaderWebView: UIViewRepresentable {
				let url: URL
				let itemID: String
		let fallbackHTML: String?

				func makeCoordinator() -> Coordinator {
								Coordinator(parent: self)
				}

				func makeUIView(context: Context) -> WKWebView {
								let config = WKWebViewConfiguration()
								let webView = WKWebView(frame: .zero, configuration: config)
								webView.navigationDelegate = context.coordinator
								return webView
				}

				func updateUIView(_ webView: WKWebView, context: Context) {
								context.coordinator.parent = self
								guard context.coordinator.lastItemID != itemID else { return }

								context.coordinator.lastItemID = itemID
								context.coordinator.didLoadReaderHTML = false
								webView.load(URLRequest(url: url))
				}

				final class Coordinator: NSObject, WKNavigationDelegate {
								var parent: ReaderWebView
								var lastItemID = ""
								var didLoadReaderHTML = false

								init(parent: ReaderWebView) {
												self.parent = parent
								}

								func webView(_ webView: WKWebView,
																				 decidePolicyFor navigationAction: WKNavigationAction,
																				 decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
												if EmbeddedWebNavigationPolicy.shouldOpenExternally(navigationAction),
													 let url = navigationAction.request.url {
														UIApplication.shared.open(url)
														decisionHandler(.cancel)
														return
												}
												decisionHandler(.allow)
								}

								func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
												guard !didLoadReaderHTML else { return }

												webView.evaluateJavaScript(Self.extractionScript) { [weak self, weak webView] result, _ in
																guard let self, let webView else { return }

																let extractedBody = (result as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
												let extractedTextLength = Self.plainTextLength(fromHTML: extractedBody)
												let shouldUseExtracted = extractedTextLength >= 450

												self.didLoadReaderHTML = true

												if shouldUseExtracted {
														let readerHTML = Self.readerHTML(body: extractedBody, sourceURL: self.parent.url)
														webView.loadHTMLString(readerHTML, baseURL: self.parent.url.deletingLastPathComponent())
														return
												}

												let fallbackBody = (self.parent.fallbackHTML ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
												if !fallbackBody.isEmpty {
														let readerHTML = Self.readerHTML(body: fallbackBody, sourceURL: self.parent.url)
														webView.loadHTMLString(readerHTML, baseURL: self.parent.url.deletingLastPathComponent())
														return
												}

												return
												}
								}

								private static func plainTextLength(fromHTML html: String) -> Int {
										guard !html.isEmpty else { return 0 }

										let withoutTags = html.replacingOccurrences(
												of: "<[^>]+>",
												with: " ",
												options: .regularExpression
										)
										let normalized = withoutTags.replacingOccurrences(
												of: "\\s+",
												with: " ",
												options: .regularExpression
										)
										return normalized.trimmingCharacters(in: .whitespacesAndNewlines).count
								}

								private static let extractionScript = #"""
								(() => {
										const root = document.cloneNode(true);
										root.querySelectorAll('script,style,noscript,iframe,header,footer,nav,aside,form').forEach(el => el.remove());

										const preferred = [
												root.querySelector('article'),
												root.querySelector('main'),
												root.querySelector('[role="main"]'),
												root.querySelector('.post-content, .article-content, .entry-content, .story-body, .main-content')
										].filter(Boolean);

										const score = (el) => {
												const text = (el.innerText || '').replace(/\s+/g, ' ').trim();
												const pCount = el.querySelectorAll('p').length;
												return text.length + pCount * 120;
										};

										let best = null;
										let bestScore = -1;

										for (const candidate of preferred) {
												const s = score(candidate);
												if (s > bestScore) {
														best = candidate;
														bestScore = s;
												}
										}

										if (!best) {
												const candidates = root.querySelectorAll('article, main, section, div');
												for (const candidate of candidates) {
														if (candidate.querySelectorAll('p').length < 2) continue;
														const s = score(candidate);
														if (s > bestScore) {
																best = candidate;
																bestScore = s;
														}
												}
										}

										if (!best) return '';

										best.querySelectorAll('script,style,noscript,iframe,form,button,input,svg').forEach(el => el.remove());
										return best.innerHTML || '';
								})();
								"""#

								private static func readerHTML(body: String, sourceURL: URL) -> String {
												"""
												<!DOCTYPE html>
												<html>
												<head>
												<meta charset="UTF-8">
												<meta name="viewport" content="width=device-width, initial-scale=1">
												<style>
												:root { color-scheme: light dark; }
												*, *::before, *::after { box-sizing: border-box; }
												body {
																font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Georgia, serif;
																font-size: 18px;
																line-height: 1.8;
																width: 100%;
																max-width: 760px;
																margin: 0 auto;
																padding: 28px 24px 64px;
																color: #1b1b1b;
																background: #ffffff;
												}
												@media (max-width: 820px) {
																body {
																				max-width: none;
																				margin: 0;
																				padding: 22px 16px 48px;
																}
												}
												.source {
																display: inline-block;
																margin-bottom: 18px;
																font-size: 12px;
																color: #6b7280;
																text-decoration: none;
																border: 1px solid #e5e7eb;
																border-radius: 999px;
																padding: 5px 10px;
												}
												h1, h2, h3, h4 { line-height: 1.28; margin-top: 1.45em; }
												img, video, iframe { max-width: 100%; height: auto; border-radius: 8px; }
												pre {
																background: #f5f5f6;
																border-radius: 8px;
																padding: 14px 16px;
																overflow-x: auto;
												}
												blockquote {
																border-left: 3px solid #d5d5d5;
																margin: 1.1em 0;
																padding: 2px 0 2px 14px;
																color: #666;
												}
												@media (prefers-color-scheme: dark) {
																body { color: #e6e6e6; background: #1c1c1e; }
																a { color: #7cb7ff; }
																pre { background: #2d2d31; }
																blockquote { border-color: #4a4a4f; color: #b3b3b8; }
																.source { color: #c0c4ca; border-color: #414247; }
												}
												</style>
												</head>
												<body>
												<a class="source" href="\(sourceURL.absoluteString)">Source</a>
												\(body)
												</body>
												</html>
												"""
								}
				}
}
#endif
