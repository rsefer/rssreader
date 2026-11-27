import SwiftUI

struct SyncButton: View {
	@EnvironmentObject private var service: FreshRSSService
	@State private var feedback: Feedback?
	@Environment(\.accessibilityReduceMotion) private var reduceMotion
	@State private var rotation = 0.0
	@State private var requestFinished = false

	private enum Feedback: Equatable {
		case syncing
		case succeeded
		case failed
	}

	private var isShowingProgress: Bool {
		service.isLoading || feedback == .syncing
	}

	private var buttonTitle: String {
		switch feedback {
		case .syncing:
			return service.sidebarMode.syncLabel
		case .succeeded:
			return "Synced"
		case .failed:
			return "Sync failed"
		case nil:
			return service.sidebarMode.syncLabel
		}
	}

	var body: some View {
		Button {
			guard !service.isLoading, !service.isUpdatingReadStatus else { return }
			feedback = .syncing
			Task { @MainActor in
				requestFinished = false
				let request = Task { @MainActor in
					await service.syncCurrentMode()
					requestFinished = true
				}
				repeat {
					if reduceMotion {
						try? await Task.sleep(for: .milliseconds(600))
					} else {
						await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
							withAnimation(.linear(duration: 0.6), completionCriteria: .removed) {
								rotation += 360
							} completion: {
								continuation.resume()
							}
						}
					}
				} while !requestFinished
				await request.value

				let result: Feedback = service.syncErrorMessage == nil ? .succeeded : .failed
				feedback = result
				try? await Task.sleep(for: .seconds(1.2))
				if feedback == result {
					feedback = nil
				}
			}
		} label: {
				Label {
						Text(buttonTitle)
				} icon: {
								Image(systemName: !isShowingProgress && feedback == .succeeded
									? "checkmark.circle.fill"
									: !isShowingProgress && feedback == .failed
										? "exclamationmark.triangle.fill"
										: "arrow.trianglehead.2.clockwise.rotate.90")
									.rotationEffect(.degrees(rotation))
									.foregroundStyle(
										!isShowingProgress && feedback == .succeeded ? Color.green
										: !isShowingProgress && feedback == .failed ? Color.red
										: Color.primary
									)
				}
		}
		.help(buttonTitle)
		.keyboardShortcut("r", modifiers: .command)
		.disabled(service.isLoading || service.isUpdatingReadStatus || feedback == .syncing)
	}
}
