import CInvarSQLite
import Foundation
import VerificationCore

final class SQLiteConnection {
    private var connection: OpaquePointer?
    private var policy: StorePolicy?
    func configure(_ policy: StorePolicy) { self.policy = policy }
    func checkQuota(usingFailureReserve: Bool) throws {
        guard let policy else { return }
        let pages = try scalar("PRAGMA page_count"), size = try scalar("PRAGMA page_size")
        let limit = usingFailureReserve ? policy.maximumDatabaseBytes : policy.maximumDatabaseBytes - policy.failureReserveBytes
        let rows = try scalar("SELECT count(*) FROM records")
        let reserved = usingFailureReserve ? 0 : try scalar("""
            SELECT COALESCE(SUM(CASE
                WHEN kind IN ('demand','execution') AND state IN ('queued','running') THEN 2
                WHEN kind IN ('demand','execution') AND state='cancelling' THEN 1
                WHEN kind='watch' AND state='registering' THEN 1
                WHEN kind='watch' AND state='active' THEN 4
                WHEN kind='watch' AND state='paused' THEN 3
                WHEN kind='watch' AND state='stopping' THEN 1
                WHEN kind='publication' AND state IN ('reserving','reserved','ready') THEN 1
                WHEN kind='providerAction' AND state IN ('preflight','accepted') THEN 2
                WHEN kind='providerAction' AND state IN ('mapped','outcomeUnknown') THEN 1
                WHEN kind='reservation' AND state='active' THEN 1
                ELSE 0 END),0) FROM heads
            """)
        guard size > 0, pages <= limit / size, reserved <= policy.maximumRecords, rows <= policy.maximumRecords - reserved else { throw InvarError("STORE_QUOTA","Database/record policy exhausted; failure headroom is retained",exitCode: 6) }
    }
    init(_ path: String) throws {
        guard sqlite3_open_v2(path, &connection, SQLITE_OPEN_CREATE | SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX, nil) == SQLITE_OK else {
            if let connection { sqlite3_close_v2(connection) }; connection = nil
            throw InvarError("STORE_OPEN_FAILED", "Cannot open the verification database")
        }
        do {
        guard sqlite3_busy_timeout(connection, 5000) == SQLITE_OK else { throw InvarError("STORE_OPEN_FAILED", "Cannot configure database wait budget") }
        let version = try statement("PRAGMA user_version")
        let status = sqlite3_step(version), schema = sqlite3_column_int(version, 0)
        sqlite3_finalize(version)
        guard status == SQLITE_ROW, schema == 0 || schema == 2 else { throw InvarError("UNSUPPORTED_STORE_SCHEMA", "Unknown database schema; no migration was applied") }
        sqlite3_limit(connection, SQLITE_LIMIT_LENGTH, 64 * 1024 * 1024 + 4096)
        try execute("PRAGMA journal_mode=WAL"); try execute("PRAGMA synchronous=FULL")
        if schema == 0 {
            try execute("CREATE TABLE records (namespace TEXT NOT NULL, id TEXT NOT NULL, payload BLOB NOT NULL, createdAt INTEGER NOT NULL DEFAULT (strftime('%s','now')), PRIMARY KEY(namespace,id))")
            try execute("CREATE TABLE heads (kind TEXT NOT NULL,id TEXT NOT NULL,revision INTEGER NOT NULL,recordID TEXT NOT NULL,state TEXT NOT NULL,PRIMARY KEY(kind,id))")
            try execute("CREATE TABLE links (ownerKind TEXT NOT NULL,ownerID TEXT NOT NULL,targetKind TEXT NOT NULL,targetID TEXT NOT NULL,PRIMARY KEY(ownerKind,ownerID,targetKind,targetID))")
            try execute("CREATE INDEX target_links ON links(targetKind,targetID)")
            try execute("PRAGMA user_version=2")
        } else {
            let tables = try scalar("SELECT count(*) FROM sqlite_master WHERE type='table' AND name IN ('records','heads','links')")
            let ageColumn = try scalar("SELECT count(*) FROM pragma_table_info('records') WHERE name='createdAt'")
            guard tables == 3, ageColumn == 1 else { throw InvarError("UNSUPPORTED_STORE_SCHEMA","Incomplete development layout; select an explicit fresh state root") }
        }
        } catch { if let connection { sqlite3_close_v2(connection) }; connection = nil; throw error }
    }
    var inTransaction: Bool { connection.map { sqlite3_get_autocommit($0) == 0 } ?? false }
    func ensureOpen() throws {
        guard connection != nil else { throw InvarError("STORE_CLOSED", "Verification store is closed") }
    }
    deinit { if let connection { sqlite3_close_v2(connection) } }
    func close() throws {
        guard let connection else { return }
        guard sqlite3_close(connection) == SQLITE_OK else { throw InvarError("STORE_CLOSE_FAILED", "SQLite still owns active statements") }
        self.connection = nil
    }
    private func statement(_ sql: String) throws -> OpaquePointer {
        guard let connection else { throw InvarError("STORE_CLOSED", "Verification store is closed") }
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(connection, sql, -1, &statement, nil) == SQLITE_OK, let statement else { throw InvarError("STORE_QUERY_FAILED", "Cannot prepare verification statement") }
        return statement
    }
    func execute(_ sql: String) throws {
        let value = try statement(sql); defer { sqlite3_finalize(value) }
        let code = sqlite3_step(value)
        if code == SQLITE_FULL || code == SQLITE_TOOBIG || code == SQLITE_NOMEM { throw InvarError("STORE_QUOTA","SQLite storage/allocation limit exhausted",exitCode: 6) }
        guard code == SQLITE_DONE || code == SQLITE_ROW else { throw InvarError("STORE_WRITE_FAILED", "SQLite transaction failed") }
    }
    func load(_ namespace: String, id: String) throws -> Data? {
        let value = try statement("SELECT payload FROM records WHERE namespace=? AND id=?")
        defer { sqlite3_finalize(value) }
        guard invar_bind_string(value, 1, namespace) == SQLITE_OK, invar_bind_string(value, 2, id) == SQLITE_OK else { throw InvarError("STORE_QUERY_FAILED", "Cannot bind record identity") }
        let code = sqlite3_step(value)
        if code == SQLITE_DONE { return nil }
        guard code == SQLITE_ROW else { throw InvarError("STORE_QUERY_FAILED", "Cannot read record") }
        let count = Int(sqlite3_column_bytes(value, 0))
        guard count <= 64 * 1024 * 1024, let bytes = sqlite3_column_blob(value, 0) else { throw InvarError("STORE_INTEGRITY", "Invalid record bytes") }
        // The statement owns this initialized buffer through the step/finalize scope.
        // Materialize exactly once at the persistence output boundary; no pointer escapes.
        return Data(bytes: bytes, count: count)
    }

    struct Head { let revision: Int; let recordID: String; let state: String }
    func scalar(_ sql: String,strings: [String] = []) throws -> Int {
        let query = try statement(sql); defer { sqlite3_finalize(query) }
        for (index,value) in strings.enumerated() { guard invar_bind_string(query,Int32(index+1),value) == SQLITE_OK else { throw InvarError("STORE_QUERY_FAILED","Cannot bind scalar") } }
        guard sqlite3_step(query) == SQLITE_ROW else { throw InvarError("STORE_QUERY_FAILED","Missing scalar result") }
        return Int(sqlite3_column_int64(query,0))
    }
    func head(_ kind: String,id: String) throws -> Head? {
        let query = try statement("SELECT revision,recordID,state FROM heads WHERE kind=? AND id=?"); defer { sqlite3_finalize(query) }
        guard invar_bind_string(query,1,kind) == SQLITE_OK, invar_bind_string(query,2,id) == SQLITE_OK else { throw InvarError("STORE_QUERY_FAILED","Cannot bind head identity") }
        let code = sqlite3_step(query)
        if code == SQLITE_DONE { return nil }
        guard code == SQLITE_ROW, let record = sqlite3_column_text(query,1), let state = sqlite3_column_text(query,2) else { throw InvarError("STORE_INTEGRITY","Invalid revision head") }
        return Head(revision: Int(sqlite3_column_int64(query,0)),recordID: String(cString: record),state: String(cString: state))
    }
    func advance(_ kind: String,id: String,expectedRevision: Int,recordID: String,state: String = "") throws {
        let current = try head(kind,id: id)
        guard (current?.revision ?? 0) == expectedRevision, expectedRevision >= 0, expectedRevision < Int.max else { throw InvarError("REVISION_CONFLICT","Record head changed") }
        let sql = current == nil ? "INSERT INTO heads(kind,id,recordID,state,revision) VALUES(?,?,?,?,1)" : "UPDATE heads SET recordID=?,state=?,revision=revision+1 WHERE kind=? AND id=?"
        let args = current == nil ? [kind,id,recordID,state] : [recordID,state,kind,id]
        let query = try statement(sql); defer { sqlite3_finalize(query) }
        for (index,value) in args.enumerated() { guard invar_bind_string(query,Int32(index+1),value) == SQLITE_OK else { throw InvarError("STORE_WRITE_FAILED","Cannot bind revision head") } }
        guard sqlite3_step(query) == SQLITE_DONE, sqlite3_changes(connection) == 1 else { throw InvarError("REVISION_CONFLICT","Concurrent revision update") }
    }
    func current(_ kind: String,states: [String],limit: Int,maximumBytes: Int) throws -> [Data] {
        guard limit > 0, maximumBytes > 0 else { throw InvarError("RESOURCE_LIMIT","Invalid record query bounds",exitCode: 6) }
        let condition = states.isEmpty ? "" : " AND h.state IN (" + Array(repeating: "?",count: states.count).joined(separator: ",") + ")"
        let query = try statement("SELECT r.payload FROM heads h JOIN records r ON r.namespace=h.kind AND r.id=h.recordID WHERE h.kind=?" + condition + " ORDER BY h.id LIMIT " + String(limit+1)); defer { sqlite3_finalize(query) }
        for (index,value) in ([kind]+states).enumerated() { guard invar_bind_string(query,Int32(index+1),value) == SQLITE_OK else { throw InvarError("STORE_QUERY_FAILED","Cannot bind current-record query") } }
        var result: [Data] = [], total = 0
        while true {
            let code = sqlite3_step(query)
            if code == SQLITE_DONE { return result }
            let count = Int(sqlite3_column_bytes(query,0))
            guard code == SQLITE_ROW, count <= maximumBytes - total, result.count < limit, let bytes = sqlite3_column_blob(query,0) else { throw InvarError("RESOURCE_LIMIT","Current-record query exceeds bounded capacity",exitCode: 6) }
            result.append(Data(bytes: bytes,count: count)); total += count
        }
    }
    func headIDs(_ kind: String,states: [String],limit: Int) throws -> [String] {
        guard limit > 0, limit <= 1024, !states.isEmpty, states.count <= 16 else { throw InvarError("RESOURCE_LIMIT","Invalid head query bounds",exitCode: 6) }
        let placeholders = Array(repeating: "?",count: states.count).joined(separator: ",")
        let query = try statement("SELECT id FROM heads WHERE kind=? AND state IN (" + placeholders + ") ORDER BY id LIMIT " + String(limit+1))
        defer { sqlite3_finalize(query) }
        for (index,value) in ([kind]+states).enumerated() {
            guard invar_bind_string(query,Int32(index+1),value) == SQLITE_OK else { throw InvarError("STORE_QUERY_FAILED","Cannot bind head query") }
        }
        var ids: [String] = []
        while true {
            let code = sqlite3_step(query)
            if code == SQLITE_DONE { return ids }
            guard code == SQLITE_ROW, ids.count < limit, let raw = sqlite3_column_text(query,0), sqlite3_column_bytes(query,0) <= 256 else { throw InvarError("RESOURCE_LIMIT","Head query exceeds bounded inventory",exitCode: 6) }
            ids.append(String(cString: raw))
        }
    }
    func removeHead(_ kind: String,id: String) throws {
        let query = try statement("DELETE FROM heads WHERE kind=? AND id=?"); defer { sqlite3_finalize(query) }
        guard invar_bind_string(query,1,kind) == SQLITE_OK, invar_bind_string(query,2,id) == SQLITE_OK, sqlite3_step(query) == SQLITE_DONE else { throw InvarError("STORE_WRITE_FAILED","Cannot release head") }
    }
    func removeRecord(_ namespace: String,id: String) throws {
        let query = try statement("DELETE FROM records WHERE namespace=? AND id=?"); defer { sqlite3_finalize(query) }
        guard invar_bind_string(query,1,namespace) == SQLITE_OK, invar_bind_string(query,2,id) == SQLITE_OK, sqlite3_step(query) == SQLITE_DONE else { throw InvarError("STORE_WRITE_FAILED","Cannot remove retained record") }
    }
    func link(ownerKind: String,ownerID: String,targetKind: String,targetID: String) throws {
        let query = try statement("INSERT OR IGNORE INTO links(ownerKind,ownerID,targetKind,targetID) VALUES(?,?,?,?)"); defer { sqlite3_finalize(query) }
        for (index,value) in [ownerKind,ownerID,targetKind,targetID].enumerated() { guard invar_bind_string(query,Int32(index+1),value) == SQLITE_OK else { throw InvarError("STORE_WRITE_FAILED","Cannot bind reference") } }
        guard sqlite3_step(query) == SQLITE_DONE else { throw InvarError("STORE_WRITE_FAILED","Cannot commit retained reference") }
    }
    struct ObjectKey: Hashable, Sendable { let kind: String; let id: String }
    func recordKeys(_ namespace: String,limit: Int) throws -> [String] {
        let query = try statement("SELECT id FROM records WHERE namespace=? ORDER BY id LIMIT " + String(limit+1)); defer { sqlite3_finalize(query) }
        guard invar_bind_string(query,1,namespace) == SQLITE_OK else { throw InvarError("STORE_QUERY_FAILED","Cannot bind namespace") }
        var result: [String] = []
        while true {
            let code = sqlite3_step(query)
            if code == SQLITE_DONE { return result }
            guard code == SQLITE_ROW, result.count < limit, let id = sqlite3_column_text(query,0) else { throw InvarError("RESOURCE_LIMIT","Record-key query exceeds bound",exitCode: 6) }
            result.append(String(cString: id))
        }
    }
    func objectKeys(newerThan: Double?,olderThan: Double?,limit: Int) throws -> [ObjectKey] {
        let condition = newerThan != nil ? " WHERE createdAt>=CAST(? AS REAL)" : olderThan != nil ? " WHERE createdAt<CAST(? AS REAL)" : ""
        let query = try statement("SELECT namespace,id FROM records" + condition + " ORDER BY namespace,id LIMIT " + String(limit+1)); defer { sqlite3_finalize(query) }
        if let bound = newerThan ?? olderThan { guard invar_bind_string(query,1,String(bound)) == SQLITE_OK else { throw InvarError("STORE_QUERY_FAILED","Cannot bind retention horizon") } }
        var result: [ObjectKey] = []
        while true {
            let code = sqlite3_step(query)
            if code == SQLITE_DONE { return result }
            guard code == SQLITE_ROW, result.count < limit, let kind = sqlite3_column_text(query,0), let id = sqlite3_column_text(query,1) else { throw InvarError("RESOURCE_LIMIT","Retained object query exceeds bound",exitCode: 6) }
            result.append(ObjectKey(kind: String(cString: kind),id: String(cString: id)))
        }
    }
    func targets(_ owner: ObjectKey,limit: Int) throws -> [ObjectKey] {
        let query = try statement("SELECT targetKind,targetID FROM links WHERE ownerKind=? AND ownerID=? LIMIT " + String(limit+1)); defer { sqlite3_finalize(query) }
        guard invar_bind_string(query,1,owner.kind) == SQLITE_OK, invar_bind_string(query,2,owner.id) == SQLITE_OK else { throw InvarError("STORE_QUERY_FAILED","Cannot bind retained reference") }
        var result: [ObjectKey] = []
        while true {
            let code = sqlite3_step(query)
            if code == SQLITE_DONE { return result }
            guard code == SQLITE_ROW, result.count < limit, let kind = sqlite3_column_text(query,0), let id = sqlite3_column_text(query,1) else { throw InvarError("RESOURCE_LIMIT","Reference traversal exceeds bound",exitCode: 6) }
            result.append(ObjectKey(kind: String(cString: kind),id: String(cString: id)))
        }
    }
    func retire(_ key: ObjectKey) throws {
        let query = try statement("SELECT id FROM heads WHERE kind=? AND recordID=?"); defer { sqlite3_finalize(query) }
        guard invar_bind_string(query,1,key.kind) == SQLITE_OK, invar_bind_string(query,2,key.id) == SQLITE_OK else { throw InvarError("STORE_QUERY_FAILED","Cannot bind retired head") }
        var heads: [String] = []
        while sqlite3_step(query) == SQLITE_ROW { guard let id = sqlite3_column_text(query,0) else { throw InvarError("STORE_INTEGRITY","Invalid retired head") }; heads.append(String(cString: id)) }
        for id in heads { try removeHead(key.kind,id: id); try removeOwnerLinks(ObjectKey(kind: key.kind,id: id)) }
        try removeRecord(key.kind,id: key.id); try removeOwnerLinks(key)
    }
    func removeOwnerLinks(_ key: ObjectKey) throws {
        let query = try statement("DELETE FROM links WHERE ownerKind=? AND ownerID=?"); defer { sqlite3_finalize(query) }
        guard invar_bind_string(query,1,key.kind) == SQLITE_OK, invar_bind_string(query,2,key.id) == SQLITE_OK, sqlite3_step(query) == SQLITE_DONE else { throw InvarError("STORE_WRITE_FAILED","Cannot retire object links") }
    }
    func insert(_ namespace: String,id: String,bytes: Data) throws {
        let ownsTransaction = !inTransaction
        if ownsTransaction { try execute("BEGIN IMMEDIATE") }
        do {
            try insertRecord(namespace,id: id,bytes: bytes)
            if ownsTransaction { try checkQuota(usingFailureReserve: false); try execute("COMMIT") }
        } catch {
            if ownsTransaction { do { try execute("ROLLBACK") } catch let cleanup { throw InvarError("STORE_WRITE_FAILED","Insert failed (\(error)); rollback failed (\(cleanup))") } }
            throw error
        }
    }
    private func insertRecord(_ namespace: String, id: String, bytes: Data) throws {
        guard bytes.count <= 64 * 1024 * 1024 else { throw InvarError("RESOURCE_LIMIT", "Stored record exceeds 64 MiB", exitCode: 6) }
        if let existing = try load(namespace, id: id) {
            guard existing == bytes else { throw InvarError("IMMUTABLE_CONFLICT", "An immutable record already exists with different bytes") }
            return
        }
        let value = try statement("INSERT INTO records(namespace,id,payload) VALUES(?,?,?) ON CONFLICT(namespace,id) DO NOTHING")
        defer { sqlite3_finalize(value) }
        guard invar_bind_string(value, 1, namespace) == SQLITE_OK, invar_bind_string(value, 2, id) == SQLITE_OK else { throw InvarError("STORE_WRITE_FAILED", "Cannot bind record identity") }
        let bound = bytes.withUnsafeBytes { invar_bind_bytes(value, 3, $0.baseAddress, $0.count) }
        guard bound == SQLITE_OK, sqlite3_step(value) == SQLITE_DONE else { throw InvarError("STORE_WRITE_FAILED", "Cannot commit immutable record") }
        let committed = try load(namespace, id: id)
        guard committed == bytes else { throw InvarError("IMMUTABLE_CONFLICT", "A concurrent writer committed different immutable bytes") }
    }
}
