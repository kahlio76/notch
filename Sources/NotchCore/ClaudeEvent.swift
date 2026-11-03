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

    /// False for tools whose prompt carries more than a yes or no: a plain Allow
    /// would answer a question with nothing, or wave through an unread plan.
    public var isApprovableFromNotch: Bool {
        !["AskUserQuestion", "ExitPlanMode"].contains(toolName ?? "")
    }

    /// The file a successful tool call changed, if any.
    public var changedFile: String? {
        guard ["Edit", "MultiEdit", "Write", "NotebookEdit"].contains(toolName ?? "") else { return nil }
        return (toolInput["file_path"] ?? toolInput["notebook_path"]) as? String
    }

    /// What is being approved, in full. The card scrolls rather than truncating.
    public var summary: String {
        let tool = toolName ?? "Tool"
        switch tool {
        case "Bash":
            return toolInput["command"] as? String ?? tool
        case "Edit", "MultiEdit", "Write", "Read", "NotebookEdit":
            let path = (toolInput["file_path"] ?? toolInput["notebook_path"]) as? String ?? ""
            return "\(tool) \(relative(path))"
        case "WebFetch":
            return "Fetch \(toolInput["url"] as? String ?? "")"
        case "WebSearch":
            return "Search \(toolInput["query"] as? String ?? "")"
        default:
            guard !toolInput.isEmpty,
                  let data = try? JSONSerialization.data(withJSONObject: toolInput, options: [.sortedKeys]),
                  let text = String(data: data, encoding: .utf8) else { return tool }
            return "\(tool) \(text)"
        }
    }

    private func relative(_ path: String) -> String {
        let prefix = cwd.hasSuffix("/") ? cwd : cwd + "/"
        return !cwd.isEmpty && path.hasPrefix(prefix) ? String(path.dropFirst(prefix.count)) : path
    }
}

/// The single JSON line Claude Code reads from the hook's stdout.
public func permissionDecision(allow: Bool) -> Data {
    var decision: [String: Any] = ["behavior": allow ? "allow" : "deny"]
    if !allow { decision["message"] = "Denied from the notch." }
    let output: [String: Any] = ["hookSpecificOutput": ["hookEventName": "PermissionRequest", "decision": decision]]
    return (try? JSONSerialization.data(withJSONObject: output, options: [.sortedKeys])) ?? Data()
}

public func doneDuration(_ seconds: Double) -> String {
    let s = Int(seconds.rounded())
    if s < 60 { return "Done in \(s) s" }
    if s < 3600 { return "Done in \(s / 60) min" }
    return "Done in \(s / 3600) h \((s % 3600) / 60) min"
}
