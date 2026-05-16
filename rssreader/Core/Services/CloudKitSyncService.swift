import Foundation
import CloudKit

/// Syncs the set of locally-applied read item IDs through the app's private CloudKit database.
///
/// This is the optimistic read state — item IDs the user has marked read on this device
/// that haven't yet been confirmed by the FreshRSS server. Syncing it means that reads
/// made on one device are immediately visible on other devices, even before the next
/// FreshRSS server sync.
///
/// Data model
/// ----------
/// - Container:  iCloud.com.seferdesign.rssreader  (private database only)
/// - Zone:       ReadStateZone
/// - Record:     ReadState / mainReadState
/// - Field:      pendingReadIDs  ([String])
@MainActor
final class CloudKitSyncService {

    static let containerIdentifier = "iCloud.com.seferdesign.rssreader"

    private static let zoneName       = "ReadStateZone"
    private static let recordType     = "ReadState"
    private static let readIDsField   = "pendingReadIDs"
    private static let recordName     = "mainReadState"

    private let privateDB: CKDatabase
    private let zoneID: CKRecordZone.ID

    private var currentRecord: CKRecord?
    private var zoneReady = false

    init() {
        let container = CKContainer(identifier: Self.containerIdentifier)
        privateDB = container.privateCloudDatabase
        zoneID = CKRecordZone.ID(zoneName: Self.zoneName, ownerName: CKCurrentUserDefaultName)
    }

    // MARK: - Public interface

    /// Fetches the set of pending read IDs stored in CloudKit. Call once on app launch.
    func fetchSyncedReadIDs() async -> Set<String> {
        do {
            try await ensureZoneReady()
            let record = try await fetchOrCreateRecord()
            currentRecord = record
            let ids = record[Self.readIDsField] as? [String] ?? []
            return Set(ids)
        } catch {
            // CloudKit may be unavailable (no iCloud account, airplane mode, etc.).
            // Fall back to an empty set — local state is still preserved.
            return []
        }
    }

    /// Merges the given IDs into the synced record. Fire-and-forget safe to call from
    /// mark-read mutations — silently drops on failure so the user's FreshRSS state
    /// remains the authoritative record.
    func pushReadIDs(_ ids: Set<String>) async {
        guard !ids.isEmpty else { return }
        do {
            try await ensureZoneReady()
            let record: CKRecord
            if let existing = currentRecord {
                record = existing
            } else {
                record = try await fetchOrCreateRecord()
                currentRecord = record
            }

            let existing = Set(record[Self.readIDsField] as? [String] ?? [])
            let merged = existing.union(ids)
            record[Self.readIDsField] = Array(merged)

            currentRecord = try await privateDB.save(record)
        } catch {
            // Silent: the full read state will reconcile on the next FreshRSS server sync.
        }
    }

    /// Clears the synced record. Called after a successful FreshRSS server sync commits
    /// all locally-applied reads, making the pending set stale.
    func clearSyncedReadIDs() async {
        guard let record = currentRecord else { return }
        record[Self.readIDsField] = [String]()
        do {
            currentRecord = try await privateDB.save(record)
        } catch {}
    }

    // MARK: - Helpers

    private func ensureZoneReady() async throws {
        guard !zoneReady else { return }
        let zone = CKRecordZone(zoneID: zoneID)
        _ = try await privateDB.save(zone)
        zoneReady = true
    }

    private func fetchOrCreateRecord() async throws -> CKRecord {
        let recordID = CKRecord.ID(recordName: Self.recordName, zoneID: zoneID)
        do {
            return try await privateDB.record(for: recordID)
        } catch let error as CKError where error.code == .unknownItem {
            return CKRecord(recordType: Self.recordType, recordID: recordID)
        }
    }
}
