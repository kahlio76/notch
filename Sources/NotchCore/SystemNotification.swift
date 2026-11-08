import Foundation

/// One notification macOS delivered, as stored in its notification database.
public struct SystemNotification: Equatable {
    public let id: Int64
    public let bundleID: String
    public let title: String
    public let subtitle: String
    public let body: String
    public let date: Date

    /// Reads a row of the `record` table, whose `data` column is a binary plist.
    /// Nil when it can't be read or has nothing to show.
    public init?(id: Int64, plist: Data) {
        guard let object = try? PropertyListSerialization.propertyList(from: plist, format: nil) as? [String: Any],
              let bundleID = object["app"] as? String,
              let request = object["req"] as? [String: Any] else { return nil }
        let title = request["titl"] as? String ?? ""
        let subtitle = request["subt"] as? String ?? ""
        let body = request["body"] as? String ?? ""
        guard !(title + subtitle + body).isEmpty else { return nil }
        self.id = id
        self.bundleID = bundleID
        self.title = title
        self.subtitle = subtitle
        self.body = body
        // Stored as seconds since 2001, like every Core Data date.
        date = Date(timeIntervalSinceReferenceDate: object["date"] as? Double ?? 0)
    }

    /// The bold line: the title, or the subtitle if there's no title.
    public var headline: String { title.isEmpty ? subtitle : title }

    /// The text under it, with the subtitle folded in when the title is already taken.
    public var detail: String {
        let lead = title.isEmpty ? "" : subtitle
        return [lead, body].filter { !$0.isEmpty }.joined(separator: " — ")
    }
}
