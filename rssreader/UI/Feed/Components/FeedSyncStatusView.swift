import SwiftUI

struct FeedSyncStatusView: View {
    @EnvironmentObject private var service: FreshRSSService

    private var statusText: String {
        if service.isLoading {
            return "Syncing feeds…"
        }
        if service.isUpdatingReadStatus {
            return "Saving read updates…"
        }
        if let lastSyncDate = service.lastSyncDate {
            let relativeDate = RelativeDateTimeFormatter().localizedString(for: lastSyncDate, relativeTo: .now)
            return "Last synced \(relativeDate)"
        }
        return "Not synced yet"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                if service.isLoading || service.isUpdatingReadStatus {
                    ProgressView()
                        .controlSize(.small)
                        .accessibilityLabel(service.isLoading ? "Syncing feeds" : "Saving read updates")
                } else {
                    Image(systemName: service.syncErrorMessage == nil ? "checkmark.circle" : "exclamationmark.triangle.fill")
                        .foregroundStyle(service.syncErrorMessage == nil ? Color.secondary : Color.red)
                }

                Text(statusText)
                    .font(.caption)
                    .foregroundStyle(service.syncErrorMessage == nil ? Color.secondary : Color.red)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)

                if service.syncErrorMessage != nil {
                    Button("Retry sync", systemImage: "arrow.clockwise") {
                        Task { await service.syncCurrentMode() }
                    }
                    .buttonStyle(.borderless)
                    .disabled(service.isLoading || service.isUpdatingReadStatus)
                }
            }

            if let errorMessage = service.errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if !service.pendingReadChanges.isEmpty {
                HStack(spacing: 8) {
                    Image(systemName: "arrow.trianglehead.clockwise")
                        .foregroundStyle(.orange)
                    Text("\(service.pendingReadChanges.count) read update(s) pending")
                        .font(.caption)
                        .foregroundStyle(.orange)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Button("Retry updates", systemImage: "arrow.clockwise") {
                        Task { await service.retryPendingReadChanges() }
                    }
                    .buttonStyle(.borderless)
                    .disabled(service.isLoading || service.isUpdatingReadStatus)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .accessibilityElement(children: .contain)
    }
}
