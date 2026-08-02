import Foundation
import Testing
#if canImport(cmux_DEV)
@testable import cmux_DEV
#elseif canImport(cmux)
@testable import cmux
#endif

@Suite(.serialized)
@MainActor
struct NotificationFeedHistoryTests {
    @Test func repeatedSurfaceNotificationsRemainChronologicalAndSupersededEntryBecomesRead() {
        let store = TerminalNotificationStore.shared
        store.replaceNotificationsForTesting([])
        store.configureNotificationDeliveryHandlerForTesting { _, _ in }
        defer {
            store.resetNotificationDeliveryHandlerForTesting()
            store.replaceNotificationsForTesting([])
        }

        let workspaceID = UUID()
        let surfaceID = UUID()
        store.addNotification(
            tabId: workspaceID,
            surfaceId: surfaceID,
            title: "First",
            subtitle: "Agent",
            body: "Needs approval",
            retargetsToLiveSurfaceOwner: false
        )
        store.addNotification(
            tabId: workspaceID,
            surfaceId: surfaceID,
            title: "Second",
            subtitle: "Agent",
            body: "Finished",
            retargetsToLiveSurfaceOwner: false
        )

        #expect(store.notifications.count == 1)
        #expect(store.notifications.first?.title == "Second")
        let history = store.notificationFeedHistory.notifications
        #expect(history.count == 2)
        #expect(history.map(\.title) == ["Second", "First"])
        #expect(history.map(\.isRead) == [false, true])
    }

    @Test func retentionKeepsEveryUnreadRecordAndOnlyNewestReadRecords() {
        let history = NotificationFeedHistoryStore(
            fileURL: nil,
            readRetentionLimit: 3
        )
        let workspaceID = UUID()
        let baseDate = Date(timeIntervalSince1970: 1_000)
        for offset in 0..<5 {
            history.record(
                notification(
                    workspaceID: workspaceID,
                    title: "Read \(offset)",
                    date: baseDate.addingTimeInterval(Double(offset)),
                    isRead: true
                ),
                supersededIDs: []
            )
        }
        for offset in 5..<7 {
            history.record(
                notification(
                    workspaceID: workspaceID,
                    title: "Unread \(offset)",
                    date: baseDate.addingTimeInterval(Double(offset)),
                    isRead: false
                ),
                supersededIDs: []
            )
        }

        #expect(history.notifications.filter { !$0.isRead }.count == 2)
        #expect(history.notifications.filter(\.isRead).map(\.title) == ["Read 4", "Read 3", "Read 2"])
        #expect(history.notifications.count == 5)
    }

    @Test func totalRetentionCapsUnreadHistoryAtNewestRecords() {
        let history = NotificationFeedHistoryStore(
            fileURL: nil,
            readRetentionLimit: 10,
            totalRetentionLimit: 3
        )
        let workspaceID = UUID()
        let baseDate = Date(timeIntervalSince1970: 1_000)
        for offset in 0..<5 {
            history.record(
                notification(
                    workspaceID: workspaceID,
                    title: "Unread \(offset)",
                    date: baseDate.addingTimeInterval(Double(offset)),
                    isRead: false
                ),
                supersededIDs: []
            )
        }

        #expect(history.notifications.count == 3)
        #expect(history.notifications.map(\.title) == ["Unread 4", "Unread 3", "Unread 2"])
        #expect(history.notifications.allSatisfy { !$0.isRead })
    }

    @Test func liveHistoryIngressNormalizesOversizedTextBeforeSnapshot() throws {
        let history = NotificationFeedHistoryStore(
            fileURL: nil,
            readRetentionLimit: 10,
            totalRetentionLimit: 2
        )
        history.record(
            notification(
                workspaceID: UUID(),
                title: String(repeating: "t", count: NotificationFeedHistoryRecord.historyTitleByteLimit * 4),
                body: String(repeating: "b", count: NotificationFeedHistoryRecord.historyBodyByteLimit * 4),
                date: Date(timeIntervalSince1970: 1_260),
                isRead: false
            ),
            supersededIDs: []
        )

        let record = try #require(history.notifications.first)
        #expect(record.title.utf8.count == NotificationFeedHistoryRecord.historyTitleByteLimit)
        #expect(record.body.utf8.count == NotificationFeedHistoryRecord.historyBodyByteLimit)
        #expect(history.snapshot.notifications.first?.body == record.body)
    }

    @Test func oversizedActiveReconcileDoesNotChurnRevisionAfterRetentionTrim() {
        var revisions: [Int] = []
        let history = NotificationFeedHistoryStore(
            fileURL: nil,
            readRetentionLimit: 10,
            totalRetentionLimit: 3
        ) { revision in
            revisions.append(revision)
        }
        let workspaceID = UUID()
        let baseDate = Date(timeIntervalSince1970: 1_200)
        let active = (0..<5).map { offset in
            notification(
                workspaceID: workspaceID,
                title: "Active \(offset)",
                date: baseDate.addingTimeInterval(Double(offset)),
                isRead: false
            )
        }

        history.reconcileActiveNotifications(active)
        let retainedTitles = history.notifications.map(\.title)
        let retainedRevision = history.revision
        history.reconcileActiveNotifications(active)

        #expect(retainedTitles == ["Active 4", "Active 3", "Active 2"])
        #expect(history.notifications.map(\.title) == retainedTitles)
        #expect(history.revision == retainedRevision)
        #expect(revisions == [1])
    }

    @Test func activeReconcileCapsBeforeMaterializingHistoryRecords() {
        let history = NotificationFeedHistoryStore(
            fileURL: nil,
            readRetentionLimit: 10,
            totalRetentionLimit: 2
        )
        let workspaceID = UUID()
        let dropped = notification(
            workspaceID: workspaceID,
            title: "Dropped oversized active",
            body: String(repeating: "x", count: NotificationFeedHistoryRecord.historyBodyByteLimit * 8),
            date: Date(timeIntervalSince1970: 1_250),
            isRead: false
        )
        let retainedOlder = notification(
            workspaceID: workspaceID,
            title: "Retained older",
            date: Date(timeIntervalSince1970: 1_251),
            isRead: false
        )
        let retainedNewer = notification(
            workspaceID: workspaceID,
            title: "Retained newer",
            date: Date(timeIntervalSince1970: 1_252),
            isRead: false
        )

        history.reconcileActiveNotifications([dropped, retainedOlder, retainedNewer])

        #expect(history.notifications.map(\.title) == ["Retained newer", "Retained older"])
        #expect(history.notifications.allSatisfy {
            $0.body.utf8.count <= NotificationFeedHistoryRecord.historyBodyByteLimit
        })
    }

    @Test func loadingOversizedHistoryPersistsCompactedSnapshot() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("notification-feed-compaction-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let fileURL = directory.appendingPathComponent("history.json")
        let workspaceID = UUID()
        let baseDate = Date(timeIntervalSince1970: 1_500)
        let records = (0..<5).map { offset in
            NotificationFeedHistoryRecord(notification: notification(
                workspaceID: workspaceID,
                title: "Persisted unread \(offset)",
                date: baseDate.addingTimeInterval(Double(offset)),
                isRead: false
            ))
        }
        _ = try write(
            NotificationFeedHistorySnapshot(
                revision: 4,
                notifications: records
            ),
            to: fileURL
        )

        let persistence = NotificationFeedHistoryPersistence(
            fileURL: fileURL,
            fileManager: .default,
            readRetentionLimit: 10,
            totalRetentionLimit: 3
        )
        let outcome = await persistence.load()
        guard case .loaded(let loaded) = outcome else {
            Issue.record("Expected compacted persisted notification feed")
            return
        }

        let loadedTitles = loaded.notifications.map(\.title)
        #expect(loaded.revision == 4)
        #expect(loadedTitles == ["Persisted unread 4", "Persisted unread 3", "Persisted unread 2"])

        let persisted = try JSONDecoder().decode(
            NotificationFeedHistorySnapshot.self,
            from: Data(contentsOf: fileURL)
        )
        #expect(persisted.revision == 4)
        #expect(persisted.notifications.map(\.title) == loadedTitles)
    }

    @Test func loadedLegacyHistoryNormalizesOversizedTextBeforeSnapshot() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("notification-feed-legacy-text-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let fileURL = directory.appendingPathComponent("history.json")
        let legacyRecord = NotificationFeedHistoryRecord(notification: notification(
            workspaceID: UUID(),
            title: String(repeating: "l", count: NotificationFeedHistoryRecord.historyTitleByteLimit * 4),
            body: String(repeating: "g", count: NotificationFeedHistoryRecord.historyBodyByteLimit * 4),
            date: Date(timeIntervalSince1970: 1_560),
            isRead: false
        ))
        try write(
            NotificationFeedHistorySnapshot(
                revision: 11,
                notifications: [legacyRecord]
            ),
            to: fileURL
        )
        let history = NotificationFeedHistoryStore(fileURL: fileURL)

        try await waitUntil {
            history.notifications.first?.body.utf8.count == NotificationFeedHistoryRecord.historyBodyByteLimit
        }
        let record = try #require(history.notifications.first)
        #expect(record.title.utf8.count == NotificationFeedHistoryRecord.historyTitleByteLimit)
        #expect(record.body.utf8.count == NotificationFeedHistoryRecord.historyBodyByteLimit)
        #expect(history.snapshot.notifications.first?.title == record.title)
    }

    @Test func oversizedHistoryFileIsQuarantinedWithMonotonicRevisionAndWritesRecover() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("notification-feed-size-limit-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let fileURL = directory.appendingPathComponent("history.json")
        let staleBackupURL = directory.appendingPathComponent(
            "history.json.oversized-stale.quarantine",
            isDirectory: false
        )
        let workspaceID = UUID()
        let baseDate = Date(timeIntervalSince1970: 1_600)
        let records = (0..<5).reversed().map { offset in
            NotificationFeedHistoryRecord(notification: notification(
                workspaceID: workspaceID,
                title: "Recovered \(offset)",
                body: String(repeating: "x", count: 128),
                date: baseDate.addingTimeInterval(Double(offset)),
                isRead: false
            ))
        }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data("stale backup".utf8).write(to: staleBackupURL)
        let data = try write(
            NotificationFeedHistorySnapshot(
                revision: 6,
                notifications: records
            ),
            to: fileURL,
            sortedKeys: true
        )
        let compactEncoder = JSONEncoder()
        compactEncoder.outputFormatting = [.sortedKeys]
        let compactData = try compactEncoder.encode(NotificationFeedHistorySnapshot(
            revision: 6,
            notifications: Array(records.prefix(3))
        ))

        let persistence = NotificationFeedHistoryPersistence(
            fileURL: fileURL,
            fileManager: .default,
            readRetentionLimit: 10,
            totalRetentionLimit: 3,
            maxSnapshotBytes: UInt64(compactData.count)
        )
        #expect(data.count > compactData.count)

        let outcome = await persistence.load()
        guard case .loaded(let loaded) = outcome else {
            Issue.record("Expected oversized current-version notification feed to preserve revision")
            return
        }
        #expect(loaded.revision == 6)
        let loadedTitles = loaded.notifications.map(\.title)
        #expect(loadedTitles == ["Recovered 4", "Recovered 3", "Recovered 2"])
        let replacement = try JSONDecoder().decode(
            NotificationFeedHistorySnapshot.self,
            from: Data(contentsOf: fileURL)
        )
        #expect(replacement.revision == 6)
        #expect(replacement.notifications.map(\.title) == loadedTitles)
        let replacementQuarantines = try FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil
        ).filter {
            $0.lastPathComponent.hasPrefix("history.json.oversized")
        }
        #expect(replacementQuarantines.isEmpty)
        #expect(!FileManager.default.fileExists(atPath: staleBackupURL.path))
        await persistence.persist(NotificationFeedHistorySnapshot(
            revision: 7,
            notifications: loaded.notifications
        ))
        let remainingQuarantines = try FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil
        ).filter {
            $0.lastPathComponent.hasPrefix("history.json.oversized")
        }
        #expect(remainingQuarantines.isEmpty)
        let recovered = try JSONDecoder().decode(
            NotificationFeedHistorySnapshot.self,
            from: Data(contentsOf: fileURL)
        )
        #expect(recovered.revision == 7)
        #expect(recovered.notifications.map(\.title) == loadedTitles)

        try FileManager.default.removeItem(at: fileURL)
        let verifier = NotificationFeedHistoryPersistence(fileURL: fileURL, fileManager: .default)
        #expect(await verifier.load() == .missing)
    }

    @Test func oversizedFutureSnapshotIsPreservedReadOnly() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("notification-feed-oversized-future-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let fileURL = directory.appendingPathComponent("history.json")
        let workspaceID = UUID()
        let futureSnapshot = NotificationFeedHistorySnapshot(
            revision: 14,
            notifications: [
                NotificationFeedHistoryRecord(notification: notification(
                    workspaceID: workspaceID,
                    title: "Future large",
                    body: String(repeating: "f", count: 1_024),
                    date: Date(timeIntervalSince1970: 1_650),
                    isRead: false
                ))
            ],
            version: NotificationFeedHistorySnapshot.currentVersion + 1
        )
        let originalData = try write(futureSnapshot, to: fileURL, sortedKeys: true)
        let persistence = NotificationFeedHistoryPersistence(
            fileURL: fileURL,
            fileManager: .default,
            readRetentionLimit: 10,
            totalRetentionLimit: 3,
            maxSnapshotBytes: UInt64(originalData.count - 1)
        )

        #expect(await persistence.load() == .unsupportedVersion(futureSnapshot.version))
        await persistence.persist(NotificationFeedHistorySnapshot(revision: 15, notifications: []))

        let finalData = try Data(contentsOf: fileURL)
        #expect(finalData == originalData)
        let quarantinedURLs = try FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil
        ).filter {
            $0.lastPathComponent.hasPrefix("history.json.oversized-")
        }
        #expect(quarantinedURLs.isEmpty)
    }

    @Test func oversizedFutureSnapshotIgnoresNestedMetadataInPrefix() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("notification-feed-nested-metadata-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let fileURL = directory.appendingPathComponent("history.json")
        let id = UUID().uuidString
        let workspaceID = UUID().uuidString
        let body = String(repeating: "x", count: 70_000)
        let rawJSON = """
        {"notifications":[{"revision":6,"version":1,"body":"\(body)","createdAt":0,"id":"\(id)","isRead":false,"retargetsToLiveSurfaceOwner":false,"subtitle":"Agent","tabId":"\(workspaceID)","title":"Nested metadata"}],"revision":14,"version":\(NotificationFeedHistorySnapshot.currentVersion + 1)}
        """
        let data = Data(rawJSON.utf8)
        try data.write(to: fileURL, options: .atomic)
        let persistence = NotificationFeedHistoryPersistence(
            fileURL: fileURL,
            fileManager: .default,
            readRetentionLimit: 10,
            totalRetentionLimit: 3,
            maxSnapshotBytes: UInt64(data.count - 1)
        )

        #expect(await persistence.load() == .unsupportedVersion(NotificationFeedHistorySnapshot.currentVersion + 1))
        #expect(try Data(contentsOf: fileURL) == data)
        let quarantinedURLs = try FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil
        ).filter {
            $0.lastPathComponent.hasPrefix("history.json.oversized")
        }
        #expect(quarantinedURLs.isEmpty)
    }

    @Test func oversizedFutureSnapshotIgnoresNestedMetadataInTail() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("notification-feed-tail-metadata-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let fileURL = directory.appendingPathComponent("history.json")
        let id = UUID().uuidString
        let workspaceID = UUID().uuidString
        let body = String(repeating: "x", count: 70_000)
        let rawJSON = """
        {"notifications":[{"body":"\(body)","createdAt":0,"id":"\(id)","isRead":false,"retargetsToLiveSurfaceOwner":false,"subtitle":"Agent","tabId":"\(workspaceID)","title":"Tail metadata"}],"revision":18,"summary":{"version":1},"version":\(NotificationFeedHistorySnapshot.currentVersion + 1)}
        """
        let data = Data(rawJSON.utf8)
        try data.write(to: fileURL, options: .atomic)
        let persistence = NotificationFeedHistoryPersistence(
            fileURL: fileURL,
            fileManager: .default,
            readRetentionLimit: 10,
            totalRetentionLimit: 3,
            maxSnapshotBytes: UInt64(data.count - 1)
        )

        #expect(await persistence.load() == .unsupportedVersion(NotificationFeedHistorySnapshot.currentVersion + 1))
        #expect(try Data(contentsOf: fileURL) == data)
        let quarantinedURLs = try FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil
        ).filter {
            $0.lastPathComponent.hasPrefix("history.json.oversized")
        }
        #expect(quarantinedURLs.isEmpty)
    }

    @Test func oversizedCurrentSnapshotReadsMetadataFromTailAndWritesRecover() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("notification-feed-current-tail-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let fileURL = directory.appendingPathComponent("history.json")
        let id = UUID().uuidString
        let workspaceID = UUID().uuidString
        let body = String(repeating: "x", count: 70_000)
        let rawJSON = """
        {"notifications":[{"body":"\(body)","createdAt":0,"id":"\(id)","isRead":false,"retargetsToLiveSurfaceOwner":false,"subtitle":"Agent","tabId":"\(workspaceID)","title":"Current tail"}],"revision":21,"version":\(NotificationFeedHistorySnapshot.currentVersion)}
        """
        let data = Data(rawJSON.utf8)
        try data.write(to: fileURL, options: .atomic)
        let persistence = NotificationFeedHistoryPersistence(
            fileURL: fileURL,
            fileManager: .default,
            readRetentionLimit: 10,
            totalRetentionLimit: 3,
            maxSnapshotBytes: UInt64(data.count - 1)
        )

        let outcome = await persistence.load()
        guard case .loaded(let loaded) = outcome else {
            Issue.record("Expected oversized current-version history to recover from tail metadata")
            return
        }
        #expect(loaded.revision == 21)
        let loadedRecord = try #require(loaded.notifications.first)
        #expect(loadedRecord.title == "Current tail")
        #expect(loadedRecord.body.utf8.count == NotificationFeedHistoryRecord.historyBodyByteLimit)
        let migrationQuarantines = try FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil
        ).filter {
            $0.lastPathComponent.hasPrefix("history.json.oversized")
        }
        #expect(migrationQuarantines.isEmpty)
        await persistence.persist(NotificationFeedHistorySnapshot(
            revision: 22,
            notifications: loaded.notifications
        ))
        let recovered = try JSONDecoder().decode(
            NotificationFeedHistorySnapshot.self,
            from: Data(contentsOf: fileURL)
        )
        #expect(recovered.revision == 22)
        #expect(recovered.notifications.map(\.title) == ["Current tail"])
    }

    @Test func oversizedCurrentSnapshotMigrationScanBudgetRecoversWritableSnapshot() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("notification-feed-scan-budget-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let fileURL = directory.appendingPathComponent("history.json")
        let id = UUID().uuidString
        let workspaceID = UUID().uuidString
        let body = String(repeating: "x", count: 70_000)
        let rawJSON = """
        {"notifications":[{"body":"\(body)","createdAt":0,"id":"\(id)","isRead":false,"retargetsToLiveSurfaceOwner":false,"subtitle":"Agent","tabId":"\(workspaceID)","title":"Budget"}],"revision":22,"version":\(NotificationFeedHistorySnapshot.currentVersion)}
        """
        let data = Data(rawJSON.utf8)
        try data.write(to: fileURL, options: .atomic)
        let persistence = NotificationFeedHistoryPersistence(
            fileURL: fileURL,
            fileManager: .default,
            readRetentionLimit: 10,
            totalRetentionLimit: 3,
            maxSnapshotBytes: UInt64(data.count - 1),
            oversizedSnapshotMigrationScanByteLimit: 128
        )

        #expect(await persistence.load() == .loaded(NotificationFeedHistorySnapshot(
            revision: 22,
            notifications: []
        )))
        let recovered = try JSONDecoder().decode(
            NotificationFeedHistorySnapshot.self,
            from: Data(contentsOf: fileURL)
        )
        #expect(recovered.revision == 22)
        #expect(recovered.notifications.isEmpty)
        let migrationQuarantines = try FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil
        ).filter {
            $0.lastPathComponent.hasPrefix("history.json.oversized")
        }
        let backupURL = try #require(migrationQuarantines.first)
        #expect(migrationQuarantines.count == 1)
        #expect(try Data(contentsOf: backupURL) == data)

        let persisted = NotificationFeedHistoryRecord(notification: notification(
            workspaceID: UUID(),
            title: "Recovered",
            date: Date(timeIntervalSince1970: 1),
            isRead: false
        ))
        await persistence.persist(NotificationFeedHistorySnapshot(
            revision: 23,
            notifications: [persisted]
        ))
        let verifier = NotificationFeedHistoryPersistence(
            fileURL: fileURL,
            fileManager: .default,
            readRetentionLimit: 10,
            totalRetentionLimit: 3
        )
        let verified = await verifier.load()
        guard case .loaded(let verifiedSnapshot) = verified else {
            Issue.record("Expected recovered persisted snapshot, got \(verified)")
            return
        }
        #expect(verifiedSnapshot.revision == 23)
        #expect(verifiedSnapshot.notifications.map(\.title) == ["Recovered"])
    }

    @Test func oversizedCurrentSnapshotMigrationScanBudgetPreservesRecoveredPrefix() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("notification-feed-scan-prefix-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let fileURL = directory.appendingPathComponent("history.json")
        let firstID = UUID().uuidString
        let secondID = UUID().uuidString
        let firstWorkspaceID = UUID().uuidString
        let secondWorkspaceID = UUID().uuidString
        let largeBody = String(repeating: "x", count: 140_000)
        let rawJSON = """
        {"notifications":[{"body":"Prefix body","createdAt":3,"id":"\(firstID)","isRead":false,"retargetsToLiveSurfaceOwner":false,"subtitle":"Agent","tabId":"\(firstWorkspaceID)","title":"Prefix"},{"body":"\(largeBody)","createdAt":2,"id":"\(secondID)","isRead":false,"retargetsToLiveSurfaceOwner":false,"subtitle":"Agent","tabId":"\(secondWorkspaceID)","title":"Tail"}],"revision":33,"version":\(NotificationFeedHistorySnapshot.currentVersion)}
        """
        let data = Data(rawJSON.utf8)
        try data.write(to: fileURL, options: .atomic)
        let persistence = NotificationFeedHistoryPersistence(
            fileURL: fileURL,
            fileManager: .default,
            readRetentionLimit: 10,
            totalRetentionLimit: 3,
            maxSnapshotBytes: UInt64(data.count - 1),
            oversizedSnapshotMigrationScanByteLimit: 70_000
        )

        let outcome = await persistence.load()
        guard case .loaded(let snapshot) = outcome else {
            Issue.record("Expected recovered prefix snapshot, got \(outcome)")
            return
        }
        #expect(snapshot.revision == 33)
        #expect(snapshot.notifications.map(\.title) == ["Prefix"])
        let recovered = try JSONDecoder().decode(
            NotificationFeedHistorySnapshot.self,
            from: Data(contentsOf: fileURL)
        )
        #expect(recovered.notifications.map(\.title) == ["Prefix"])
        let migrationQuarantines = try FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil
        ).filter {
            $0.lastPathComponent.hasPrefix("history.json.oversized")
        }
        let backupURL = try #require(migrationQuarantines.first)
        #expect(migrationQuarantines.count == 1)
        #expect(try Data(contentsOf: backupURL) == data)
    }
}

private enum NotificationFeedHistoryTestError: Error {
    case missingPayload
    case timeout
}
