import Foundation

/// One Claude Code hook payload, as sent by notch-hook.
public struct ClaudeEvent {
    public let name: String
    public let sessionID: String
    public let cwd: String
    public let toolName: String?
    public let toolInput: [String: Any]

    public init?(json: Data) {
        guard let object = (try? JSONSerialization.jsonObject(with: json)) as? [String: Any],
              let name = object["hook_event_name"] as? String else { return nil }
        self.name = name
        sessionID = object["session_id"] as? String ?? "unknown"
        cwd = object["cwd"] as? String ?? ""
        toolName = object["tool_name"] as? String
        toolInput = object["tool_input"] as? [String: Any] ?? [:]
    }

    public var project: String { (cwd as NSString).lastPathComponent }

}

