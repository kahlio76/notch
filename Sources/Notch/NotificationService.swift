import AppKit
import NotchCore
import SQLite3

/// Mirrors new macOS notifications into the notch by watching the database Notification Center
/// keeps. Turn an app's banners off in System Settings and it only shows up here.
/// Reading the database needs Full Disk Access; without it this asks once, then keeps checking.
final class NotificationService {
    private let store: NotchStore
    private let queue = DispatchQueue(label: "notch.notifications")
    private var timer: DispatchSourceTimer?
    private var watcher: DispatchSourceFileSystemObject?
    // Only touched on `queue`.
    private var lastID: Int64?
    private var askedForAccess = false

    private static let path = NSHomeDirectory() + "/Library/Group Containers/group.com.apple.usernoted/db2/db"
    /// Anything older was delivered while the Mac slept or before launch, and is old news.
    private static let freshness: TimeInterval = 30

    init(store: NotchStore) {
        self.store = store
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now(), repeating: 1, leeway: .milliseconds(200))
        timer.setEventHandler { [weak self] in self?.check() }
        timer.resume()
        self.timer = timer
    }

    /// New notifications land in the write-ahead log first, so reacting to it beats waiting
    /// for the next tick. The timer stays as a fallback for when the log is swapped out.
    private func watchLog() {
        guard watcher == nil else { return }
        let fd = Darwin.open(Self.path + "-wal", O_EVTONLY)
        guard fd >= 0 else { return }
        let source = DispatchSource.makeFileSystemObjectSource(fileDescriptor: fd, eventMask: [.write, .extend, .delete, .rename], queue: queue)
        source.setEventHandler { [weak self, weak source] in
            guard let self else { return }
            if let events = source?.data, !events.isDisjoint(with: [.delete, .rename]) {
                source?.cancel()
                self.watcher = nil
            }
            self.check()
        }
        source.setCancelHandler { close(fd) }
        source.resume()
        watcher = source
    }

    private func check() {
        // A connection kept open stops seeing usernoted's new rows, so each check opens its own.
        guard let db = open() else { return }
        defer { sqlite3_close(db) }
        watchLog()
        guard let lastID else {
            // Start from whatever is newest now, so launch doesn't replay the backlog.
            self.lastID = Self.query(db, "SELECT IFNULL(MAX(rec_id), 0) FROM record") { sqlite3_column_int64($0, 0) }.first ?? 0
            return
        }
        let rows = Self.query(db, "SELECT rec_id, data FROM record WHERE rec_id > \(lastID) ORDER BY rec_id") { row -> (Int64, Data) in
            let bytes = sqlite3_column_blob(row, 1)
            let data = bytes.map { Data(bytes: $0, count: Int(sqlite3_column_bytes(row, 1))) } ?? Data()
            return (sqlite3_column_int64(row, 0), data)
        }
        for (id, data) in rows {
            self.lastID = max(self.lastID ?? 0, id)
            guard let note = SystemNotification(id: id, plist: data),
                  note.bundleID != Bundle.main.bundleIdentifier,
                  Date().timeIntervalSince(note.date) < Self.freshness else { continue }
            let alert = NotchAlert(note)
            DispatchQueue.main.async { self.store.show(alert: alert) }
        }
    }

    private func open() -> OpaquePointer? {
        var handle: OpaquePointer?
        let opened = sqlite3_open_v2(Self.path, &handle, SQLITE_OPEN_READONLY, nil) == SQLITE_OK
        // Opening can succeed without access; the first read is what fails.
        if opened, let handle, sqlite3_exec(handle, "SELECT 1 FROM record LIMIT 1", nil, nil, nil) == SQLITE_OK {
            return handle
        }
        sqlite3_close(handle)
        if !askedForAccess {
            askedForAccess = true
            DispatchQueue.main.async {
                self.store.show(peek: Peek(symbol: "bell.badge", title: "Notifications", detail: "Give Notch Full Disk Access"))
            }
        }
        return nil
    }

    private static func query<T>(_ db: OpaquePointer, _ sql: String, _ read: (OpaquePointer) -> T) -> [T] {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK, let statement else { return [] }
        defer { sqlite3_finalize(statement) }
        var rows: [T] = []
        while sqlite3_step(statement) == SQLITE_ROW { rows.append(read(statement)) }
        return rows
    }
}

struct NotchAlert: Equatable {
    let id: Int64
    let bundleID: String
    let appName: String
    let icon: NSImage?
    let headline: String
    let detail: String

    init(_ note: SystemNotification) {
        id = note.id
        bundleID = note.bundleID
        headline = note.headline
        detail = note.detail
        let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: note.bundleID)
        appName = url.map { FileManager.default.displayName(atPath: $0.path).replacingOccurrences(of: ".app", with: "") } ?? note.bundleID
        icon = url.map { NSWorkspace.shared.icon(forFile: $0.path) }
    }

    static func == (a: NotchAlert, b: NotchAlert) -> Bool { a.id == b.id }
}
