#if os(macOS)
import Combine
import Sparkle

@MainActor
final class SparkleUpdaterController: ObservableObject {
    let objectWillChange = ObservableObjectPublisher()
    private let updaterController: SPUStandardUpdaterController

    init(startingUpdater: Bool = true) {
        updaterController = SPUStandardUpdaterController(
            startingUpdater: startingUpdater,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )
    }

    func checkForUpdates() {
        updaterController.checkForUpdates(nil)
    }
}
#endif
