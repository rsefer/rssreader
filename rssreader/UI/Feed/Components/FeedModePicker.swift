import SwiftUI

struct FeedModePicker: View {
    @Binding var sidebarMode: SidebarMode

    // Defer writes to avoid "Publishing changes from within view updates" warning.
    // The Picker fires its selection action synchronously during view render;
    // dispatching async breaks the synchronous publish chain.
    private var deferredBinding: Binding<SidebarMode> {
        Binding(
            get: { sidebarMode },
            set: { newValue in
                DispatchQueue.main.async {
                    sidebarMode = newValue
                }
            }
        )
    }

    var body: some View {
        Picker("", selection: deferredBinding) {
            ForEach(SidebarMode.allCases) { mode in
                Text(mode.rawValue).tag(mode)
            }
        }
        .pickerStyle(.segmented)
    }
}
