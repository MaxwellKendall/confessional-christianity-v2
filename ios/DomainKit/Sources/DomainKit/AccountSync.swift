// Cognito-authorized AppSync transport and bidirectional DomainKit <-> AppSync
// field mapping for children, catechism progress, and Lord's Day notes/cards
// (TKL-1068, TKL-818, TKL-820, TKL-1069, TKL-866).
//
// Contract: infra/SYNC.md and infra/schema/sync.graphql.
//
// Field mapping (also documented in infra/SYNC.md):
//   - `children` (row_id == child_id == LocalChild.id.uuidString.lowercased()):
//       name               <-> LocalChild.name
//       age                <-> LocalChild.age (omitted when nil)
//       created_at         <-> LocalChild.createdAt (UTC ISO 8601 ms)
//       active_catechism_id <-> LocalChild.activeCatechismId (ContentId rawValue, e.g. "WSC")
//       (envelope updated_at <-> LocalChild.updatedAt)
//   - `catechism_assignments` (row_id: persisted SyncRowMeta.rowId or UUIDv5):
//       catechism_slug     <-> programForContentId(track.catechismId)?.slug ?? track.catechismId
//       started_at         <-> ChildCatechismTrack.startedAt (UTC ISO 8601 ms)
//       started_at_question <-> ChildCatechismTrack.startedAtQuestion
//   - `catechism_pacing` (row_id: persisted SyncRowMeta.rowId or UUIDv5):
//       catechism_slug     <-> track.catechismId (via PROGRAMS)
//       current_question   <-> ChildCatechismTrack.currentQuestion
//   - `catechism_milestones` (row_id: persisted SyncRowMeta.rowId or UUIDv5):
//       catechism_slug     <-> track.catechismId (via PROGRAMS)
//       question           <-> Int key in ChildCatechismTrack.milestones
//       state              <-> MilestoneRecord.state ("introduced" | "reviewing" | "mastered")
//       introduced_at      <-> MilestoneRecord.introducedAt (UTC ISO 8601 ms)
//       review_count       <-> MilestoneRecord.reviewCount
//   - `lords_day_notes` (row_id == note_id == LordsDayNote.id.uuidString.lowercased()):
//       service_date       <-> LordsDayNote.serviceDate (UTC ISO 8601 ms)
//       passage_ref        <-> LordsDayNote.passageRef
//       sermon_title       <-> LordsDayNote.sermonTitle
//       preacher           <-> LordsDayNote.preacher
//       church             <-> LordsDayNote.church
//       extracted_text     <-> LordsDayNote.extractedText
//       created_at         <-> LordsDayNote.createdAt (UTC ISO 8601 ms)
//       (envelope updated_at/deleted_at <-> LordsDayNote.updatedAt/deletedAt; photos never sync)
//   - `note_cards` (row_id == NoteCard.id, envelope note_id == NoteCard.noteId):
//       kind               <-> NoteCard.kind.rawValue ("key_point" | "quote" | "verse")
//       body               <-> NoteCard.body ("" for verse)
//       verse_ref          <-> NoteCard.verseRef
//       attribution        <-> NoteCard.attribution
//       palette            <-> NoteCard.palette
//       position           <-> NoteCard.position (order)
//       edited_by_user     <-> NoteCard.editedByUser
//       created_at         <-> NoteCard.createdAt (UTC ISO 8601 ms)
//       (envelope updated_at/deleted_at <-> NoteCard.updatedAt/deletedAt)
import CryptoKit
import Foundation
import SwiftData

// MARK: - Config

public enum AccountSyncConfig {
    private struct OutputsFile: Decodable {
        struct Custom: Decodable {
            let account_sync_url: String?
        }
        let custom: Custom?
    }

    /// Reads `custom.account_sync_url` from an `amplify_outputs.{stage}.json` blob.
    public static func syncURL(fromAmplifyOutputsData data: Data) -> URL? {
        guard let decoded = try? JSONDecoder().decode(OutputsFile.self, from: data),
              let raw = decoded.custom?.account_sync_url?.trimmingCharacters(in: .whitespacesAndNewlines),
              !raw.isEmpty,
              let components = URLComponents(string: raw),
              let scheme = components.scheme?.lowercased(),
              (scheme == "https" || scheme == "http"),
              let host = components.host, !host.isEmpty else {
            return nil
        }
        return components.url
    }

    public static func syncURL(in bundle: Bundle, resourceName: String) -> URL? {
        guard let url = bundle.url(forResource: resourceName, withExtension: "json"),
              let data = try? Data(contentsOf: url) else {
            return nil
        }
        return syncURL(fromAmplifyOutputsData: data)
    }
}

// MARK: - Timestamps

public enum SyncTimestamp {
    /// Truncates a Date to millisecond precision so local timestamps match
    /// AppSync/DynamoDB's ISO 8601 millisecond precision during LWW comparisons.
    public static func truncate(_ date: Date) -> Date {
        Date(timeIntervalSince1970: floor(date.timeIntervalSince1970 * 1000.0) / 1000.0)
    }

    /// UTC ISO 8601 with exact millisecond precision (`YYYY-MM-DDTHH:mm:ss.SSSZ`),
    /// matching `infra/lambda/sync/service.mjs`'s `parseTimestamp`.
    public static func format(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: truncate(date))
    }

    /// Parses UTC ISO 8601 instants with or without fractional seconds.
    public static func parse(_ string: String) -> Date? {
        let withFrac = ISO8601DateFormatter()
        withFrac.timeZone = TimeZone(secondsFromGMT: 0)
        withFrac.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = withFrac.date(from: string) {
            return truncate(date)
        }
        let plain = ISO8601DateFormatter()
        plain.timeZone = TimeZone(secondsFromGMT: 0)
        plain.formatOptions = [.withInternetDateTime]
        return plain.date(from: string).map(truncate)
    }
}

// MARK: - Stable deterministic UUIDv5

public enum SyncUUID {
    /// Fixed namespace UUID for Confessional Christianity deterministic sync row IDs.
    private static let namespace = UUID(uuidString: "7e53f24a-94b1-4b9c-8b64-5d0a1a2c3e4f")!

    /// RFC 4122 UUIDv5 (SHA-1) returned as lowercase string.
    public static func v5(_ name: String) -> String {
        var nsBytes = withUnsafeBytes(of: namespace.uuid) { Array($0) }
        nsBytes.append(contentsOf: name.utf8)
        let digest = Array(Insecure.SHA1.hash(data: nsBytes))
        var bytes = Array(digest.prefix(16))
        bytes[6] = (bytes[6] & 0x0F) | 0x50 // version 5
        bytes[8] = (bytes[8] & 0x3F) | 0x80 // RFC 4122 variant
        let uuid = UUID(uuid: (
            bytes[0], bytes[1], bytes[2], bytes[3],
            bytes[4], bytes[5], bytes[6], bytes[7],
            bytes[8], bytes[9], bytes[10], bytes[11],
            bytes[12], bytes[13], bytes[14], bytes[15]
        ))
        return uuid.uuidString.lowercased()
    }
}

// MARK: - AppSync Transport

public enum AppSyncTransportError: Error, Equatable, Sendable {
    case offline
    case unauthenticated
    case httpStatus(Int)
    case graphQL([String])
    case invalidResponse
}

public final class AppSyncTransport: SyncTransport {
    public static let maxPushBatchSize = 20
    public static let maxPullPageSize = 100

    public typealias TokenProvider = @Sendable (_ forceRefresh: Bool) async -> String?
    public typealias OnlineCheck = @Sendable () async -> Bool
    public typealias HTTPFetch = @Sendable (URLRequest) async throws -> (Data, URLResponse)
    public typealias RejectionHandler = @Sendable (_ id: UUID, _ reason: String?) -> Void

    private let endpoint: URL
    private let tokenProvider: TokenProvider
    private let isOnline: OnlineCheck
    private let fetch: HTTPFetch
    private let onRejected: RejectionHandler?

    public init(
        endpoint: URL,
        tokenProvider: @escaping TokenProvider,
        isOnline: @escaping OnlineCheck = { true },
        fetch: @escaping HTTPFetch = { try await URLSession.shared.data(for: $0) },
        onRejected: RejectionHandler? = nil
    ) {
        self.endpoint = endpoint
        self.tokenProvider = tokenProvider
        self.isOnline = isOnline
        self.fetch = fetch
        self.onRejected = onRejected
    }

    private static let pushMutation = """
    mutation PushSync($changes: [SyncChangeInput!]!) {
      pushSync(changes: $changes) {
        id
        status
        reason
      }
    }
    """

    private static let pullQuery = """
    query PullSync($table: String!, $after: String!, $limit: Int!) {
      pullSync(table: $table, after: $after, limit: $limit) {
        table
        id
        child_id
        note_id
        updated_at
        deleted_at
        payload
        change_id
      }
    }
    """

    public func push(_ changes: [SyncChange]) async throws -> Set<UUID> {
        guard !changes.isEmpty else { return [] }
        var acknowledged = Set<UUID>()
        var offset = 0
        while offset < changes.count {
            try Task.checkCancellation()
            let end = min(offset + Self.maxPushBatchSize, changes.count)
            let slice = Array(changes[offset..<end])
            let input: [[String: Any]] = slice.map { change in
                let rowId = change.rowId.lowercased()
                var item: [String: Any] = [
                    "id": change.id.uuidString.lowercased(),
                    "table": change.table,
                    "row_id": rowId,
                    "updated_at": SyncTimestamp.format(change.updatedAt),
                ]
                if SyncTable.isNoteTable(change.table) {
                    let noteId = (change.noteId ?? (change.table == SyncTable.lordsDayNotes ? rowId : "")).lowercased()
                    item["note_id"] = noteId
                } else {
                    let childId = (change.childId ?? (change.table == SyncTable.children ? rowId : "")).lowercased()
                    item["child_id"] = childId
                }
                if let deletedAt = change.deletedAt {
                    item["deleted_at"] = SyncTimestamp.format(deletedAt)
                } else if let payload = change.payload, let payloadString = String(data: payload, encoding: .utf8) {
                    item["payload"] = payloadString
                }
                return item
            }

            let data = try await executeGraphQL(query: Self.pushMutation, variables: ["changes": input])
            let response = try JSONDecoder().decode(GraphQLResponse<PushData>.self, from: data)
            if let errors = response.errors, !errors.isEmpty {
                throw AppSyncTransportError.graphQL(errors.map(\.message))
            }
            guard let results = response.data?.pushSync else {
                throw AppSyncTransportError.invalidResponse
            }

            var sliceAcked = 0
            var sawRetry = false
            for result in results {
                guard let id = UUID(uuidString: result.id) else { continue }
                switch result.status {
                case "ACCEPTED":
                    acknowledged.insert(id)
                    sliceAcked += 1
                case "REJECTED":
                    // Permanent rejection (UNAUTHORIZED / INVALID_INPUT / CLOCK_SKEW):
                    // drop from outbox so it cannot block later writes.
                    acknowledged.insert(id)
                    sliceAcked += 1
                    onRejected?(id, result.reason)
                case "RETRY":
                    sawRetry = true
                default:
                    sawRetry = true
                }
            }

            if sawRetry || sliceAcked < slice.count {
                break
            }
            offset = end
        }
        return acknowledged
    }

    public func pull(table: String, after cursor: SyncCursor?, limit: Int) async throws -> [SyncRecord] {
        try Task.checkCancellation()
        let clampedLimit = min(max(1, limit), Self.maxPullPageSize)
        let variables: [String: Any] = [
            "table": table,
            "after": String(cursor?.changeId ?? 0),
            "limit": clampedLimit,
        ]
        let data = try await executeGraphQL(query: Self.pullQuery, variables: variables)
        let response = try JSONDecoder().decode(GraphQLResponse<PullData>.self, from: data)
        if let errors = response.errors, !errors.isEmpty {
            throw AppSyncTransportError.graphQL(errors.map(\.message))
        }
        guard let wireRecords = response.data?.pullSync else {
            throw AppSyncTransportError.invalidResponse
        }

        var records: [SyncRecord] = []
        records.reserveCapacity(wireRecords.count)
        for item in wireRecords {
            guard let updatedAt = SyncTimestamp.parse(item.updated_at),
                  let changeId = Int64(item.change_id) else {
                throw AppSyncTransportError.invalidResponse
            }
            let deletedAt: Date?
            if let rawDeleted = item.deleted_at {
                guard let parsed = SyncTimestamp.parse(rawDeleted) else {
                    throw AppSyncTransportError.invalidResponse
                }
                deletedAt = parsed
            } else {
                deletedAt = nil
            }
            records.append(SyncRecord(
                table: item.table,
                id: item.id.lowercased(),
                childId: item.child_id?.lowercased(),
                noteId: item.note_id?.lowercased(),
                payload: item.payload.map { Data($0.utf8) },
                updatedAt: updatedAt,
                deletedAt: deletedAt,
                changeId: changeId
            ))
        }
        return records
    }

    private func executeGraphQL(query: String, variables: [String: Any]) async throws -> Data {
        guard await isOnline() else { throw AppSyncTransportError.offline }
        let body = try JSONSerialization.data(withJSONObject: [
            "query": query,
            "variables": variables,
        ])

        var forceRefresh = false
        for attempt in 0..<2 {
            try Task.checkCancellation()
            guard let token = await tokenProvider(forceRefresh), !token.isEmpty else {
                throw AppSyncTransportError.unauthenticated
            }
            var request = URLRequest(url: endpoint)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue(token, forHTTPHeaderField: "Authorization")
            request.httpBody = body

            let (data, response) = try await fetch(request)
            guard let http = response as? HTTPURLResponse else {
                throw AppSyncTransportError.invalidResponse
            }
            if http.statusCode == 401 && attempt == 0 {
                forceRefresh = true
                continue
            }
            guard (200..<300).contains(http.statusCode) else {
                throw AppSyncTransportError.httpStatus(http.statusCode)
            }
            if attempt == 0, isUnauthorizedGraphQLError(data) {
                forceRefresh = true
                continue
            }
            return data
        }
        throw AppSyncTransportError.unauthenticated
    }

    private func isUnauthorizedGraphQLError(_ data: Data) -> Bool {
        struct ErrorEnvelope: Decodable {
            struct Entry: Decodable {
                let errorType: String?
            }
            let errors: [Entry]?
        }
        guard let envelope = try? JSONDecoder().decode(ErrorEnvelope.self, from: data),
              let errors = envelope.errors else { return false }
        return errors.contains { $0.errorType == "UnauthorizedException" }
    }

    private struct GraphQLResponse<T: Decodable>: Decodable {
        struct ErrorItem: Decodable {
            let message: String
            let errorType: String?
        }
        let data: T?
        let errors: [ErrorItem]?
    }

    private struct PushData: Decodable {
        struct Result: Decodable {
            let id: String
            let status: String
            let reason: String?
        }
        let pushSync: [Result]?
    }

    private struct PullData: Decodable {
        struct Record: Decodable {
            let table: String
            let id: String
            let child_id: String?
            let note_id: String?
            let updated_at: String
            let deleted_at: String?
            let payload: String?
            let change_id: String
        }
        let pullSync: [Record]?
    }
}

// MARK: - Table names & payloads

public enum SyncTable {
    public static let children = "children"
    public static let catechismAssignments = "catechism_assignments"
    public static let catechismPacing = "catechism_pacing"
    public static let catechismMilestones = "catechism_milestones"
    public static let lordsDayNotes = "lords_day_notes"
    public static let noteCards = "note_cards"

    public static func isNoteTable(_ table: String) -> Bool {
        table == lordsDayNotes || table == noteCards
    }

    public static func catechismSlug(forContentId contentId: String) -> String {
        programForContentId(contentId)?.slug ?? contentId
    }

    public static func contentId(forCatechismSlug slug: String) -> String {
        getProgram(slug)?.contentId.rawValue ?? slug
    }

    static func assignmentNaturalKey(childId: UUID, catechismId: String) -> String {
        "\(childId.uuidString.lowercased()):\(catechismSlug(forContentId: catechismId))"
    }

    static func pacingNaturalKey(childId: UUID, catechismId: String) -> String {
        "\(childId.uuidString.lowercased()):\(catechismSlug(forContentId: catechismId))"
    }

    static func milestoneNaturalKey(childId: UUID, catechismId: String, question: Int) -> String {
        "\(childId.uuidString.lowercased()):\(catechismSlug(forContentId: catechismId)):\(question)"
    }

    static func defaultRowId(table: String, naturalKey: String) -> String {
        SyncUUID.v5("\(table):\(naturalKey)")
    }
}

struct ChildSyncPayload: Codable {
    let name: String
    let age: Int?
    let created_at: String
    let active_catechism_id: String?
}

struct CatechismAssignmentSyncPayload: Codable {
    let catechism_slug: String
    let started_at: String
    let started_at_question: Int
}

struct CatechismPacingSyncPayload: Codable {
    let catechism_slug: String
    let current_question: Int
}

struct CatechismMilestoneSyncPayload: Codable {
    let catechism_slug: String
    let question: Int
    let state: String
    let introduced_at: String
    let review_count: Int
}

struct LordsDayNoteSyncPayload: Codable {
    let service_date: String
    let passage_ref: String?
    let sermon_title: String?
    let preacher: String?
    let church: String?
    let extracted_text: String?
    let created_at: String
}

struct NoteCardSyncPayload: Codable {
    let kind: String
    let body: String
    let verse_ref: String?
    let attribution: String?
    let palette: String?
    let position: Int
    let edited_by_user: Bool
    let created_at: String
}

// MARK: - SyncRowMeta helpers & outbox recording

@MainActor
enum SyncMetaStore {
    static func meta(table: String, rowId: String, in context: ModelContext) throws -> SyncRowMeta? {
        let key = "\(table):\(rowId.lowercased())"
        let predicate = #Predicate<SyncRowMeta> { $0.lookupKey == key }
        return try context.fetch(FetchDescriptor(predicate: predicate)).first
    }

    static func meta(table: String, naturalKey: String, in context: ModelContext) throws -> SyncRowMeta? {
        let predicate = #Predicate<SyncRowMeta> { $0.table == table && $0.naturalKey == naturalKey }
        return try context.fetch(FetchDescriptor(predicate: predicate)).first
    }

    static func allMeta(forChildId childId: UUID, in context: ModelContext) throws -> [SyncRowMeta] {
        let cid = childId.uuidString.lowercased()
        let predicate = #Predicate<SyncRowMeta> { $0.childId == cid }
        return try context.fetch(FetchDescriptor(predicate: predicate))
    }

    @discardableResult
    static func upsert(
        table: String,
        rowId: String,
        childId: String,
        naturalKey: String,
        updatedAt: Date,
        in context: ModelContext
    ) throws -> SyncRowMeta {
        let lowerRow = rowId.lowercased()
        let lowerChild = childId.lowercased()
        if let existing = try meta(table: table, rowId: lowerRow, in: context) {
            existing.naturalKey = naturalKey
            existing.childId = lowerChild
            existing.updatedAt = updatedAt
            return existing
        }
        let created = SyncRowMeta(
            table: table, rowId: lowerRow, childId: lowerChild, naturalKey: naturalKey, updatedAt: updatedAt
        )
        context.insert(created)
        return created
    }

    static func resolvedRowId(table: String, naturalKey: String, in context: ModelContext) throws -> String {
        if let existing = try meta(table: table, naturalKey: naturalKey, in: context) {
            return existing.rowId
        }
        return SyncTable.defaultRowId(table: table, naturalKey: naturalKey)
    }

    static func enqueueOutbox(
        subject: String,
        table: String,
        rowId: String,
        childId: String? = nil,
        noteId: String? = nil,
        payload: Data?,
        updatedAt: Date,
        deletedAt: Date? = nil,
        in context: ModelContext
    ) throws {
        var descriptor = FetchDescriptor<SyncOutboxEntry>(sortBy: [SortDescriptor(\.sequence, order: .reverse)])
        descriptor.fetchLimit = 1
        let nextSeq = (try context.fetch(descriptor).first?.sequence ?? 0) + 1
        context.insert(SyncOutboxEntry(
            sequence: nextSeq,
            subject: subject,
            table: table,
            rowId: rowId.lowercased(),
            childId: childId?.lowercased(),
            noteId: noteId?.lowercased(),
            payload: payload,
            updatedAt: updatedAt,
            deletedAt: deletedAt
        ))
    }
}

// MARK: - Adapters

@MainActor
public enum ChildProgressSyncAdapters {
    /// All four child & catechism progress adapters, in dependency order:
    /// `children`, `catechism_assignments`, `catechism_pacing`, `catechism_milestones`.
    public static func all(subject: String? = nil) -> [any SyncTableAdapter] {
        [
            ChildrenSyncAdapter(),
            CatechismAssignmentsSyncAdapter(),
            CatechismPacingSyncAdapter(),
            CatechismMilestonesSyncAdapter(subject: subject),
        ]
    }
}

@MainActor
public enum LordsDaySyncAdapters {
    /// Both Lord's Day adapters in dependency order: parent notes before cards.
    public static func all() -> [any SyncTableAdapter] {
        [
            LordsDayNotesSyncAdapter(),
            NoteCardsSyncAdapter(),
        ]
    }
}

@MainActor
public enum AccountSyncAdapters {
    /// Every synced table in dependency order.
    public static func all(subject: String? = nil) -> [any SyncTableAdapter] {
        ChildProgressSyncAdapters.all(subject: subject) + LordsDaySyncAdapters.all()
    }
}

@MainActor
final class LordsDayNotesSyncAdapter: SyncTableAdapter {
    let table = SyncTable.lordsDayNotes

    func localUpdatedAt(id: String, in context: ModelContext) throws -> Date? {
        if let uuid = UUID(uuidString: id) {
            let predicate = #Predicate<LordsDayNote> { $0.id == uuid }
            if let note = try context.fetch(FetchDescriptor(predicate: predicate)).first {
                return note.updatedAt
            }
        }
        return try SyncMetaStore.meta(table: table, rowId: id, in: context)?.updatedAt
    }

    func apply(_ record: SyncRecord, in context: ModelContext) throws {
        guard let uuid = UUID(uuidString: record.id),
              let data = record.payload,
              let payload = try? JSONDecoder().decode(LordsDayNoteSyncPayload.self, from: data),
              let serviceDate = SyncTimestamp.parse(payload.service_date) else {
            return
        }
        let createdAt = SyncTimestamp.parse(payload.created_at) ?? record.updatedAt
        let predicate = #Predicate<LordsDayNote> { $0.id == uuid }
        if let existing = try context.fetch(FetchDescriptor(predicate: predicate)).first {
            existing.applySynced(
                serviceDate: serviceDate,
                passageRef: payload.passage_ref,
                sermonTitle: payload.sermon_title,
                preacher: payload.preacher,
                church: payload.church,
                extractedText: payload.extracted_text,
                createdAt: createdAt,
                updatedAt: record.updatedAt,
                deletedAt: nil
            )
        } else {
            let note = LordsDayNote(
                id: uuid,
                serviceDate: serviceDate,
                passageRef: payload.passage_ref,
                sermonTitle: payload.sermon_title,
                preacher: payload.preacher,
                church: payload.church,
                extractedText: payload.extracted_text,
                createdAt: createdAt,
                updatedAt: record.updatedAt,
                deletedAt: nil
            )
            context.insert(note)
        }
        let lowerId = uuid.uuidString.lowercased()
        try SyncMetaStore.upsert(
            table: table, rowId: lowerId, childId: "", naturalKey: lowerId,
            updatedAt: record.updatedAt, in: context
        )
    }

    func remove(id: String, in context: ModelContext) throws {
        try softDelete(id: id, updatedAt: SyncTimestamp.truncate(Date()), deletedAt: SyncTimestamp.truncate(Date()), in: context)
    }

    func remove(_ record: SyncRecord, in context: ModelContext) throws {
        try softDelete(id: record.id, updatedAt: record.updatedAt, deletedAt: record.deletedAt ?? record.updatedAt, in: context)
    }

    private func softDelete(id: String, updatedAt: Date, deletedAt: Date, in context: ModelContext) throws {
        guard let uuid = UUID(uuidString: id) else { return }
        let predicate = #Predicate<LordsDayNote> { $0.id == uuid }
        if let existing = try context.fetch(FetchDescriptor(predicate: predicate)).first {
            existing.deletedAt = deletedAt
            existing.updatedAt = updatedAt
        }
        let lowerId = uuid.uuidString.lowercased()
        try SyncMetaStore.upsert(
            table: table, rowId: lowerId, childId: "", naturalKey: lowerId,
            updatedAt: updatedAt, in: context
        )
    }
}

@MainActor
final class NoteCardsSyncAdapter: SyncTableAdapter {
    let table = SyncTable.noteCards

    func localUpdatedAt(id: String, in context: ModelContext) throws -> Date? {
        if let uuid = UUID(uuidString: id) {
            let predicate = #Predicate<NoteCard> { $0.id == uuid }
            if let card = try context.fetch(FetchDescriptor(predicate: predicate)).first {
                return card.updatedAt
            }
        }
        return try SyncMetaStore.meta(table: table, rowId: id, in: context)?.updatedAt
    }

    func apply(_ record: SyncRecord, in context: ModelContext) throws {
        guard let uuid = UUID(uuidString: record.id),
              let rawNoteId = record.noteId,
              let noteId = UUID(uuidString: rawNoteId),
              let data = record.payload,
              let payload = try? JSONDecoder().decode(NoteCardSyncPayload.self, from: data),
              let kind = CardKind(rawValue: payload.kind) else {
            return
        }
        let body = kind == .verse ? "" : payload.body
        if kind == .verse, (payload.verse_ref?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true) {
            return
        }
        let createdAt = SyncTimestamp.parse(payload.created_at) ?? record.updatedAt
        let predicate = #Predicate<NoteCard> { $0.id == uuid }
        if let existing = try context.fetch(FetchDescriptor(predicate: predicate)).first {
            existing.applySynced(
                noteId: noteId,
                kind: kind,
                body: body,
                verseRef: payload.verse_ref,
                attribution: payload.attribution,
                palette: payload.palette,
                position: max(0, payload.position),
                editedByUser: payload.edited_by_user,
                createdAt: createdAt,
                updatedAt: record.updatedAt,
                deletedAt: nil
            )
        } else {
            let card = NoteCard(
                id: uuid,
                noteId: noteId,
                kind: kind,
                body: body,
                verseRef: payload.verse_ref,
                attribution: payload.attribution,
                palette: payload.palette,
                position: max(0, payload.position),
                editedByUser: payload.edited_by_user,
                createdAt: createdAt,
                updatedAt: record.updatedAt,
                deletedAt: nil
            )
            context.insert(card)
        }
        let lowerId = uuid.uuidString.lowercased()
        try SyncMetaStore.upsert(
            table: table, rowId: lowerId, childId: "", naturalKey: rawNoteId.lowercased(),
            updatedAt: record.updatedAt, in: context
        )
    }

    func remove(id: String, in context: ModelContext) throws {
        try softDelete(id: id, noteId: nil, updatedAt: SyncTimestamp.truncate(Date()), deletedAt: SyncTimestamp.truncate(Date()), in: context)
    }

    func remove(_ record: SyncRecord, in context: ModelContext) throws {
        try softDelete(id: record.id, noteId: record.noteId, updatedAt: record.updatedAt, deletedAt: record.deletedAt ?? record.updatedAt, in: context)
    }

    private func softDelete(id: String, noteId: String?, updatedAt: Date, deletedAt: Date, in context: ModelContext) throws {
        guard let uuid = UUID(uuidString: id) else { return }
        let predicate = #Predicate<NoteCard> { $0.id == uuid }
        var resolvedNoteId = noteId?.lowercased() ?? ""
        if let existing = try context.fetch(FetchDescriptor(predicate: predicate)).first {
            existing.deletedAt = deletedAt
            existing.updatedAt = updatedAt
            if resolvedNoteId.isEmpty { resolvedNoteId = existing.noteId.uuidString.lowercased() }
        }
        let lowerId = uuid.uuidString.lowercased()
        try SyncMetaStore.upsert(
            table: table, rowId: lowerId, childId: "", naturalKey: resolvedNoteId,
            updatedAt: updatedAt, in: context
        )
    }
}

@MainActor
final class ChildrenSyncAdapter: SyncTableAdapter {
    let table = SyncTable.children

    func localUpdatedAt(id: String, in context: ModelContext) throws -> Date? {
        if let meta = try SyncMetaStore.meta(table: table, rowId: id, in: context) {
            return meta.updatedAt
        }
        guard let uuid = UUID(uuidString: id) else { return nil }
        let predicate = #Predicate<LocalChild> { $0.id == uuid }
        return try context.fetch(FetchDescriptor(predicate: predicate)).first?.updatedAt
    }

    func apply(_ record: SyncRecord, in context: ModelContext) throws {
        guard let uuid = UUID(uuidString: record.id),
              let data = record.payload,
              let payload = try? JSONDecoder().decode(ChildSyncPayload.self, from: data) else {
            return
        }
        let createdAt = SyncTimestamp.parse(payload.created_at) ?? record.updatedAt
        let predicate = #Predicate<LocalChild> { $0.id == uuid }
        if let existing = try context.fetch(FetchDescriptor(predicate: predicate)).first {
            existing.applySynced(
                name: payload.name,
                age: payload.age,
                createdAt: createdAt,
                updatedAt: record.updatedAt,
                activeCatechismId: payload.active_catechism_id
            )
        } else {
            let child = LocalChild(
                id: uuid,
                name: payload.name,
                age: payload.age,
                createdAt: createdAt,
                updatedAt: record.updatedAt,
                activeCatechismId: payload.active_catechism_id
            )
            context.insert(child)
            let settings: ProgressSettings
            if let existingSettings = try context.fetch(FetchDescriptor<ProgressSettings>()).first {
                settings = existingSettings
            } else {
                settings = ProgressSettings()
                context.insert(settings)
            }
            if settings.activeChildId == nil {
                settings.activeChildId = uuid
            }
        }
        let lowerId = uuid.uuidString.lowercased()
        try SyncMetaStore.upsert(
            table: table, rowId: lowerId, childId: lowerId, naturalKey: lowerId,
            updatedAt: record.updatedAt, in: context
        )
    }

    func remove(id: String, in context: ModelContext) throws {
        guard let uuid = UUID(uuidString: id) else { return }
        let childPredicate = #Predicate<LocalChild> { $0.id == uuid }
        if let child = try context.fetch(FetchDescriptor(predicate: childPredicate)).first {
            let tracksPredicate = #Predicate<ChildCatechismTrack> { $0.childId == uuid }
            for track in try context.fetch(FetchDescriptor(predicate: tracksPredicate)) {
                context.delete(track)
            }
            if let settings = try context.fetch(FetchDescriptor<ProgressSettings>()).first,
               settings.activeChildId == uuid {
                let others = try context.fetch(FetchDescriptor<LocalChild>(sortBy: [SortDescriptor(\.createdAt)]))
                settings.activeChildId = others.first(where: { $0.id != uuid })?.id
            }
            context.delete(child)
        }
        for meta in try SyncMetaStore.allMeta(forChildId: uuid, in: context) {
            context.delete(meta)
        }
    }
}

@MainActor
final class CatechismAssignmentsSyncAdapter: SyncTableAdapter {
    let table = SyncTable.catechismAssignments

    func localUpdatedAt(id: String, in context: ModelContext) throws -> Date? {
        try SyncMetaStore.meta(table: table, rowId: id, in: context)?.updatedAt
    }

    func apply(_ record: SyncRecord, in context: ModelContext) throws {
        guard let rawChildId = record.childId,
              let childId = UUID(uuidString: rawChildId),
              let data = record.payload,
              let payload = try? JSONDecoder().decode(CatechismAssignmentSyncPayload.self, from: data) else {
            return
        }
        let catechismId = SyncTable.contentId(forCatechismSlug: payload.catechism_slug)
        let startedAt = SyncTimestamp.parse(payload.started_at) ?? record.updatedAt
        let track = try findOrCreateTrack(
            childId: childId,
            catechismId: catechismId,
            defaultCurrentQuestion: payload.started_at_question,
            defaultStartedAtQuestion: payload.started_at_question,
            defaultStartedAt: startedAt,
            updatedAt: record.updatedAt,
            in: context
        )
        track.startedAt = startedAt
        track.startedAtQuestion = payload.started_at_question
        track.updatedAt = max(track.updatedAt, record.updatedAt)

        let naturalKey = SyncTable.assignmentNaturalKey(childId: childId, catechismId: catechismId)
        try SyncMetaStore.upsert(
            table: table, rowId: record.id, childId: rawChildId, naturalKey: naturalKey,
            updatedAt: record.updatedAt, in: context
        )
    }

    func remove(id: String, in context: ModelContext) throws {
        guard let meta = try SyncMetaStore.meta(table: table, rowId: id, in: context) else { return }
        context.delete(meta)
        try deleteTrackIfOrphaned(naturalKey: meta.naturalKey, in: context)
    }
}

@MainActor
final class CatechismPacingSyncAdapter: SyncTableAdapter {
    let table = SyncTable.catechismPacing

    func localUpdatedAt(id: String, in context: ModelContext) throws -> Date? {
        try SyncMetaStore.meta(table: table, rowId: id, in: context)?.updatedAt
    }

    func apply(_ record: SyncRecord, in context: ModelContext) throws {
        guard let rawChildId = record.childId,
              let childId = UUID(uuidString: rawChildId),
              let data = record.payload,
              let payload = try? JSONDecoder().decode(CatechismPacingSyncPayload.self, from: data) else {
            return
        }
        let catechismId = SyncTable.contentId(forCatechismSlug: payload.catechism_slug)
        let track = try findOrCreateTrack(
            childId: childId,
            catechismId: catechismId,
            defaultCurrentQuestion: payload.current_question,
            defaultStartedAtQuestion: 1,
            defaultStartedAt: record.updatedAt,
            updatedAt: record.updatedAt,
            in: context
        )
        track.currentQuestion = payload.current_question
        track.updatedAt = max(track.updatedAt, record.updatedAt)

        let naturalKey = SyncTable.pacingNaturalKey(childId: childId, catechismId: catechismId)
        try SyncMetaStore.upsert(
            table: table, rowId: record.id, childId: rawChildId, naturalKey: naturalKey,
            updatedAt: record.updatedAt, in: context
        )
    }

    func remove(id: String, in context: ModelContext) throws {
        guard let meta = try SyncMetaStore.meta(table: table, rowId: id, in: context) else { return }
        context.delete(meta)
        try deleteTrackIfOrphaned(naturalKey: meta.naturalKey, in: context)
    }
}

@MainActor
final class CatechismMilestonesSyncAdapter: SyncTableAdapter {
    let table = SyncTable.catechismMilestones
    let mergesLiveRecords = true
    private let subject: String?

    init(subject: String? = nil) {
        self.subject = subject
    }

    func localUpdatedAt(id: String, in context: ModelContext) throws -> Date? {
        try SyncMetaStore.meta(table: table, rowId: id, in: context)?.updatedAt
    }

    func apply(_ record: SyncRecord, in context: ModelContext) throws {
        guard let rawChildId = record.childId,
              let childId = UUID(uuidString: rawChildId),
              let data = record.payload,
              let payload = try? JSONDecoder().decode(CatechismMilestoneSyncPayload.self, from: data) else {
            return
        }
        let catechismId = SyncTable.contentId(forCatechismSlug: payload.catechism_slug)
        let introducedAt = SyncTimestamp.parse(payload.introduced_at) ?? record.updatedAt
        let track = try findOrCreateTrack(
            childId: childId,
            catechismId: catechismId,
            defaultCurrentQuestion: max(1, payload.question),
            defaultStartedAtQuestion: 1,
            defaultStartedAt: introducedAt,
            updatedAt: record.updatedAt,
            in: context
        )
        let incoming = MilestoneRecord(
            state: payload.state,
            introducedAt: introducedAt,
            reviewCount: payload.review_count
        )
        var milestones = track.milestones
        let key = String(payload.question)
        let existingMeta = try SyncMetaStore.meta(table: table, rowId: record.id, in: context)
        let finalMilestone: MilestoneRecord
        let needsUpgradePush: Bool
        let resolvedUpdatedAt: Date
        if let existing = milestones[key] {
            let localUpdatedAt = existingMeta?.updatedAt ?? track.updatedAt
            finalMilestone = MilestoneRecord.merged(
                local: existing,
                remote: incoming,
                localUpdatedAt: localUpdatedAt,
                remoteUpdatedAt: record.updatedAt
            )
            needsUpgradePush = finalMilestone != incoming
            if needsUpgradePush {
                resolvedUpdatedAt = localUpdatedAt > record.updatedAt
                    ? localUpdatedAt
                    : SyncTimestamp.truncate(record.updatedAt.addingTimeInterval(0.001))
            } else {
                resolvedUpdatedAt = max(localUpdatedAt, record.updatedAt)
            }
        } else {
            finalMilestone = incoming
            needsUpgradePush = false
            resolvedUpdatedAt = record.updatedAt
        }
        milestones[key] = finalMilestone
        track.milestones = milestones
        track.updatedAt = max(track.updatedAt, resolvedUpdatedAt)

        let naturalKey = SyncTable.milestoneNaturalKey(
            childId: childId, catechismId: catechismId, question: payload.question
        )
        try SyncMetaStore.upsert(
            table: table, rowId: record.id, childId: rawChildId, naturalKey: naturalKey,
            updatedAt: resolvedUpdatedAt, in: context
        )
        if needsUpgradePush, let subject {
            let upgradedPayload = try JSONEncoder().encode(CatechismMilestoneSyncPayload(
                catechism_slug: payload.catechism_slug,
                question: payload.question,
                state: finalMilestone.state,
                introduced_at: SyncTimestamp.format(finalMilestone.introducedAt),
                review_count: finalMilestone.reviewCount
            ))
            try SyncMetaStore.enqueueOutbox(
                subject: subject,
                table: table,
                rowId: record.id,
                childId: rawChildId,
                payload: upgradedPayload,
                updatedAt: resolvedUpdatedAt,
                in: context
            )
        }
    }

    func remove(id: String, in context: ModelContext) throws {
        guard let meta = try SyncMetaStore.meta(table: table, rowId: id, in: context) else { return }
        let parts = meta.naturalKey.split(separator: ":", maxSplits: 2).map(String.init)
        if parts.count == 3, let childId = UUID(uuidString: parts[0]) {
            let catechismId = SyncTable.contentId(forCatechismSlug: parts[1])
            let questionKey = parts[2]
            let predicate = #Predicate<ChildCatechismTrack> {
                $0.childId == childId && $0.catechismId == catechismId
            }
            if let track = try context.fetch(FetchDescriptor(predicate: predicate)).first {
                var milestones = track.milestones
                milestones.removeValue(forKey: questionKey)
                track.milestones = milestones
                track.updatedAt = Date()
            }
        }
        context.delete(meta)
    }
}

@MainActor
private func findOrCreateTrack(
    childId: UUID,
    catechismId: String,
    defaultCurrentQuestion: Int,
    defaultStartedAtQuestion: Int,
    defaultStartedAt: Date,
    updatedAt: Date,
    in context: ModelContext
) throws -> ChildCatechismTrack {
    let predicate = #Predicate<ChildCatechismTrack> {
        $0.childId == childId && $0.catechismId == catechismId
    }
    if let existing = try context.fetch(FetchDescriptor(predicate: predicate)).first {
        return existing
    }
    let created = ChildCatechismTrack(
        childId: childId,
        catechismId: catechismId,
        currentQuestion: defaultCurrentQuestion,
        startedAtQuestion: defaultStartedAtQuestion,
        startedAt: defaultStartedAt,
        updatedAt: updatedAt
    )
    context.insert(created)
    return created
}

@MainActor
private func deleteTrackIfOrphaned(naturalKey: String, in context: ModelContext) throws {
    let parts = naturalKey.split(separator: ":", maxSplits: 1).map(String.init)
    guard parts.count == 2, let childId = UUID(uuidString: parts[0]) else { return }
    let catechismId = SyncTable.contentId(forCatechismSlug: parts[1])
    let hasAssignment = try SyncMetaStore.meta(
        table: SyncTable.catechismAssignments, naturalKey: naturalKey, in: context
    ) != nil
    let hasPacing = try SyncMetaStore.meta(
        table: SyncTable.catechismPacing, naturalKey: naturalKey, in: context
    ) != nil
    guard !hasAssignment && !hasPacing else { return }
    let predicate = #Predicate<ChildCatechismTrack> {
        $0.childId == childId && $0.catechismId == catechismId
    }
    if let track = try context.fetch(FetchDescriptor(predicate: predicate)).first,
       track.milestones.isEmpty {
        context.delete(track)
    }
}

// MARK: - Guest data union merge & sign-out clear (TKL-1070)

/// Summary of local guest data on this device, shown on the "Keep what's on
/// this phone in your account" confirmation screen (TKL-833 / TKL-1070).
public struct GuestDataSummary: Equatable, Sendable {
    public struct Row: Equatable, Identifiable, Sendable {
        public let id: String
        public let label: String
        public let value: String

        public init(id: String, label: String, value: String) {
            self.id = id
            self.label = label
            self.value = value
        }
    }

    public struct TrackHighlight: Equatable, Sendable {
        public let currentQuestion: Int
        public let totalQuestions: Int

        public init(currentQuestion: Int, totalQuestions: Int) {
            self.currentQuestion = currentQuestion
            self.totalQuestions = totalQuestions
        }
    }

    public let childCount: Int
    public let trackCount: Int
    public let milestoneCount: Int
    public let singleTrack: TrackHighlight?
    public let noteCount: Int
    public let cardCount: Int

    public static let empty = GuestDataSummary(
        childCount: 0, trackCount: 0, milestoneCount: 0, singleTrack: nil, noteCount: 0, cardCount: 0
    )

    public init(
        childCount: Int,
        trackCount: Int,
        milestoneCount: Int,
        singleTrack: TrackHighlight? = nil,
        noteCount: Int,
        cardCount: Int
    ) {
        self.childCount = childCount
        self.trackCount = trackCount
        self.milestoneCount = milestoneCount
        self.singleTrack = singleTrack
        self.noteCount = noteCount
        self.cardCount = cardCount
    }

    public var hasData: Bool {
        childCount > 0 || trackCount > 0 || noteCount > 0 || cardCount > 0
    }

    public var rows: [Row] {
        var out: [Row] = []
        if childCount > 0 {
            out.append(Row(id: "children", label: "Children", value: "\(childCount)"))
        }
        if trackCount > 0 {
            let value: String
            if let single = singleTrack {
                value = "Q. \(single.currentQuestion) of \(single.totalQuestions)"
            } else {
                value = "\(trackCount) \(trackCount == 1 ? "track" : "tracks")"
            }
            out.append(Row(id: "catechism", label: "Catechism progress", value: value))
        }
        if noteCount > 0 {
            let value: String
            if cardCount > 0 {
                value = "\(noteCount) \(noteCount == 1 ? "sermon" : "sermons") · \(cardCount) \(cardCount == 1 ? "card" : "cards")"
            } else {
                value = "\(noteCount) \(noteCount == 1 ? "sermon" : "sermons")"
            }
            out.append(Row(id: "lords_day", label: "Lord’s Day notes", value: value))
        }
        return out
    }
}

/// First sign-in merge for local guest data (TKL-1070 / TKL-824).
/// Enqueues every local guest row (children, catechism assignments, pacing and
/// milestones, live Lord's Day notes and cards) into the signed-in subject's
/// outbox in parent-before-child order. Photos stay strictly local.
@MainActor
public enum GuestDataMerge {
    public static func summary(in context: ModelContext) throws -> GuestDataSummary {
        let children = try context.fetch(FetchDescriptor<LocalChild>())
        let childIds = Set(children.map(\.id))
        let tracks = try context.fetch(FetchDescriptor<ChildCatechismTrack>())
            .filter { childIds.contains($0.childId) }
        let milestoneCount = tracks.reduce(0) { $0 + $1.milestones.count }
        let singleTrack: GuestDataSummary.TrackHighlight?
        if tracks.count == 1, let track = tracks.first {
            let total = programForContentId(track.catechismId)?.totalQuestions ?? PROGRAMS[0].totalQuestions
            let clamped = min(max(track.currentQuestion, 1), total)
            singleTrack = GuestDataSummary.TrackHighlight(currentQuestion: clamped, totalQuestions: total)
        } else {
            singleTrack = nil
        }

        let liveNotes = try context.fetch(FetchDescriptor<LordsDayNote>())
            .filter { $0.deletedAt == nil }
        let liveNoteIds = Set(liveNotes.map(\.id))
        let liveCards = try context.fetch(FetchDescriptor<NoteCard>())
            .filter { $0.deletedAt == nil && liveNoteIds.contains($0.noteId) }

        return GuestDataSummary(
            childCount: children.count,
            trackCount: tracks.count,
            milestoneCount: milestoneCount,
            singleTrack: singleTrack,
            noteCount: liveNotes.count,
            cardCount: liveCards.count
        )
    }

    /// Atomically enqueues every local guest row into `subject`'s outbox and
    /// records its `SyncRowMeta`. Idempotent: skips any `(table, rowId)` already
    /// queued for `subject`. Returns the number of newly queued outbox entries.
    @discardableResult
    public static func enqueueGuestData(for subject: String, in context: ModelContext) throws -> Int {
        do {
            let existingOutbox = try context.fetch(FetchDescriptor<SyncOutboxEntry>())
                .filter { $0.subject == subject }
            var alreadyQueued = Set(existingOutbox.map { "\($0.table):\($0.rowId.lowercased())" })
            var enqueued = 0

            func enqueueIfNeeded(
                table: String,
                rowId: String,
                childId: String? = nil,
                noteId: String? = nil,
                payload: Data,
                updatedAt: Date
            ) throws {
                let key = "\(table):\(rowId.lowercased())"
                guard !alreadyQueued.contains(key) else { return }
                try SyncMetaStore.enqueueOutbox(
                    subject: subject,
                    table: table,
                    rowId: rowId,
                    childId: childId,
                    noteId: noteId,
                    payload: payload,
                    updatedAt: updatedAt,
                    in: context
                )
                alreadyQueued.insert(key)
                enqueued += 1
            }

            // 1. Children (parent rows first).
            let children = try context.fetch(FetchDescriptor<LocalChild>(
                sortBy: [SortDescriptor(\.createdAt)]
            )).sorted { ($0.createdAt, $0.id.uuidString) < ($1.createdAt, $1.id.uuidString) }
            let childIds = Set(children.map(\.id))

            for child in children {
                let cid = child.id.uuidString.lowercased()
                let updatedAt = SyncTimestamp.truncate(child.updatedAt)
                let createdAt = SyncTimestamp.truncate(child.createdAt)
                let payload = try JSONEncoder().encode(ChildSyncPayload(
                    name: child.name,
                    age: child.age,
                    created_at: SyncTimestamp.format(createdAt),
                    active_catechism_id: child.activeCatechismId
                ))
                try SyncMetaStore.upsert(
                    table: SyncTable.children, rowId: cid, childId: cid, naturalKey: cid,
                    updatedAt: updatedAt, in: context
                )
                try enqueueIfNeeded(
                    table: SyncTable.children, rowId: cid, childId: cid,
                    payload: payload, updatedAt: updatedAt
                )
            }

            // 2. Catechism assignments, pacing, and milestones (for existing children).
            let tracks = try context.fetch(FetchDescriptor<ChildCatechismTrack>())
                .filter { childIds.contains($0.childId) }
                .sorted { ($0.childId.uuidString, $0.catechismId) < ($1.childId.uuidString, $1.catechismId) }

            for track in tracks {
                let cid = track.childId.uuidString.lowercased()
                let slug = SyncTable.catechismSlug(forContentId: track.catechismId)
                let trackUpdatedAt = SyncTimestamp.truncate(track.updatedAt)
                let startedAt = SyncTimestamp.truncate(track.startedAt)

                let assignNat = SyncTable.assignmentNaturalKey(childId: track.childId, catechismId: track.catechismId)
                let assignRowId = try SyncMetaStore.resolvedRowId(
                    table: SyncTable.catechismAssignments, naturalKey: assignNat, in: context
                )
                let assignPayload = try JSONEncoder().encode(CatechismAssignmentSyncPayload(
                    catechism_slug: slug,
                    started_at: SyncTimestamp.format(startedAt),
                    started_at_question: track.startedAtQuestion
                ))
                try SyncMetaStore.upsert(
                    table: SyncTable.catechismAssignments, rowId: assignRowId, childId: cid,
                    naturalKey: assignNat, updatedAt: trackUpdatedAt, in: context
                )
                try enqueueIfNeeded(
                    table: SyncTable.catechismAssignments, rowId: assignRowId, childId: cid,
                    payload: assignPayload, updatedAt: trackUpdatedAt
                )

                let pacingNat = SyncTable.pacingNaturalKey(childId: track.childId, catechismId: track.catechismId)
                let pacingRowId = try SyncMetaStore.resolvedRowId(
                    table: SyncTable.catechismPacing, naturalKey: pacingNat, in: context
                )
                let pacingPayload = try JSONEncoder().encode(CatechismPacingSyncPayload(
                    catechism_slug: slug,
                    current_question: track.currentQuestion
                ))
                try SyncMetaStore.upsert(
                    table: SyncTable.catechismPacing, rowId: pacingRowId, childId: cid,
                    naturalKey: pacingNat, updatedAt: trackUpdatedAt, in: context
                )
                try enqueueIfNeeded(
                    table: SyncTable.catechismPacing, rowId: pacingRowId, childId: cid,
                    payload: pacingPayload, updatedAt: trackUpdatedAt
                )

                let milestones = track.milestones
                for question in milestones.keys.compactMap(Int.init).sorted() {
                    guard let record = milestones[String(question)] else { continue }
                    let msNat = SyncTable.milestoneNaturalKey(
                        childId: track.childId, catechismId: track.catechismId, question: question
                    )
                    let msRowId = try SyncMetaStore.resolvedRowId(
                        table: SyncTable.catechismMilestones, naturalKey: msNat, in: context
                    )
                    let introAt = SyncTimestamp.truncate(record.introducedAt)
                    let msUpdatedAt = max(trackUpdatedAt, introAt)
                    let msPayload = try JSONEncoder().encode(CatechismMilestoneSyncPayload(
                        catechism_slug: slug,
                        question: question,
                        state: record.state,
                        introduced_at: SyncTimestamp.format(introAt),
                        review_count: record.reviewCount
                    ))
                    try SyncMetaStore.upsert(
                        table: SyncTable.catechismMilestones, rowId: msRowId, childId: cid,
                        naturalKey: msNat, updatedAt: msUpdatedAt, in: context
                    )
                    try enqueueIfNeeded(
                        table: SyncTable.catechismMilestones, rowId: msRowId, childId: cid,
                        payload: msPayload, updatedAt: msUpdatedAt
                    )
                }
            }

            // 3. Live Lord's Day notes (parent rows before cards; photos stay local).
            let notes = try context.fetch(FetchDescriptor<LordsDayNote>())
                .filter { $0.deletedAt == nil }
                .sorted { ($0.createdAt, $0.id.uuidString) < ($1.createdAt, $1.id.uuidString) }
            let liveNoteIds = Set(notes.map(\.id))

            for note in notes {
                let nid = note.id.uuidString.lowercased()
                let updatedAt = SyncTimestamp.truncate(note.updatedAt)
                let serviceDate = SyncTimestamp.truncate(note.serviceDate)
                let createdAt = SyncTimestamp.truncate(note.createdAt)
                let payload = try JSONEncoder().encode(LordsDayNoteSyncPayload(
                    service_date: SyncTimestamp.format(serviceDate),
                    passage_ref: note.passageRef,
                    sermon_title: note.sermonTitle,
                    preacher: note.preacher,
                    church: note.church,
                    extracted_text: note.extractedText,
                    created_at: SyncTimestamp.format(createdAt)
                ))
                try SyncMetaStore.upsert(
                    table: SyncTable.lordsDayNotes, rowId: nid, childId: "", naturalKey: nid,
                    updatedAt: updatedAt, in: context
                )
                try enqueueIfNeeded(
                    table: SyncTable.lordsDayNotes, rowId: nid, noteId: nid,
                    payload: payload, updatedAt: updatedAt
                )
            }

            // 4. Live NoteCards for live notes, preserving exact IDs and order.
            let cards = try context.fetch(FetchDescriptor<NoteCard>())
                .filter { $0.deletedAt == nil && liveNoteIds.contains($0.noteId) }
                .sorted(by: NoteCard.ordered)

            for card in cards {
                if card.kind == .verse, (card.verseRef?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true) {
                    continue
                }
                let cid = card.id.uuidString.lowercased()
                let nid = card.noteId.uuidString.lowercased()
                let updatedAt = SyncTimestamp.truncate(card.updatedAt)
                let createdAt = SyncTimestamp.truncate(card.createdAt)
                let body = card.kind == .verse ? "" : card.body
                let payload = try JSONEncoder().encode(NoteCardSyncPayload(
                    kind: card.kind.rawValue,
                    body: body,
                    verse_ref: card.verseRef,
                    attribution: card.attribution,
                    palette: card.palette,
                    position: max(0, card.position),
                    edited_by_user: card.editedByUser,
                    created_at: SyncTimestamp.format(createdAt)
                ))
                try SyncMetaStore.upsert(
                    table: SyncTable.noteCards, rowId: cid, childId: "", naturalKey: nid,
                    updatedAt: updatedAt, in: context
                )
                try enqueueIfNeeded(
                    table: SyncTable.noteCards, rowId: cid, noteId: nid,
                    payload: payload, updatedAt: updatedAt
                )
            }

            try context.save()
            return enqueued
        } catch {
            context.rollback()
            throw error
        }
    }
}

/// Sign-out cleanup (TKL-1070 / TKL-833): clears all synced account data and
/// sync bookkeeping from the local SwiftData store back to a clean empty guest
/// state so signing into a different account never uploads the prior account's
/// data.
@MainActor
public enum AccountDataCleanup {
    public static func clearSyncedData(for subject: String? = nil, in context: ModelContext) throws {
        do {
            for child in try context.fetch(FetchDescriptor<LocalChild>()) {
                context.delete(child)
            }
            for track in try context.fetch(FetchDescriptor<ChildCatechismTrack>()) {
                context.delete(track)
            }
            for legacy in try context.fetch(FetchDescriptor<LocalCatechismTrack>()) {
                context.delete(legacy)
            }
            for settings in try context.fetch(FetchDescriptor<ProgressSettings>()) {
                settings.activeChildId = nil
                settings.activeCatechismId = nil
            }
            for note in try context.fetch(FetchDescriptor<LordsDayNote>()) {
                context.delete(note)
            }
            for card in try context.fetch(FetchDescriptor<NoteCard>()) {
                context.delete(card)
            }
            for entry in try context.fetch(FetchDescriptor<SyncOutboxEntry>()) {
                context.delete(entry)
            }
            for cursor in try context.fetch(FetchDescriptor<SyncCursorRecord>()) {
                context.delete(cursor)
            }
            for meta in try context.fetch(FetchDescriptor<SyncRowMeta>()) {
                context.delete(meta)
            }
            _ = subject
            try context.save()
        } catch {
            context.rollback()
            throw error
        }
    }
}

/// What a sign-in does to local sync state (TKL-1081). A session expiry is not a
/// sign-out: the app only stops syncing and keeps the outbox, cursors and
/// `SyncRowMeta`, so the same account signing in again resumes and pushes what
/// was queued. Only an explicit sign-out (`AccountDataCleanup`) clears them.
@MainActor
public enum AccountSession {
    public enum SignIn: Equatable, Sendable {
        /// This device already synced as this subject: keep everything and resume.
        case resume
        /// First sign-in for this subject here: local data is guest data (offer the merge).
        case firstOnDevice
    }

    /// Prepares local state for `subject` signing in, given the subject that last
    /// synced on this device. A different previous owner (left behind by a session
    /// expiry) has its synced data, outbox, cursors and metadata cleared so none of
    /// it reaches the new account. On a first sign-in any leftover `SyncRowMeta`
    /// (written only by signed-in stores, so never guest state) is dropped, so
    /// every subject starts with no metadata.
    public static func signIn(subject: String, lastSyncedSubject: String?, in context: ModelContext) throws -> SignIn {
        if let previous = lastSyncedSubject, previous != subject {
            try AccountDataCleanup.clearSyncedData(for: previous, in: context)
            return .firstOnDevice
        }
        if lastSyncedSubject == subject { return .resume }
        if try SyncEngine.hasSyncedState(for: subject, in: context) { return .resume }
        do {
            for meta in try context.fetch(FetchDescriptor<SyncRowMeta>()) {
                context.delete(meta)
            }
            try context.save()
        } catch {
            context.rollback()
            throw error
        }
        return .firstOnDevice
    }
}
