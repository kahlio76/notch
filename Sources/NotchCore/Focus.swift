import Foundation

/// The active Focus mode identifier in macOS's Assertions.json, or nil when none is on.
public func activeFocusMode(assertions: Data) -> String? {
    guard let root = (try? JSONSerialization.jsonObject(with: assertions)) as? [String: Any],
          let store = (root["data"] as? [[String: Any]])?.first,
          let record = (store["storeAssertionRecords"] as? [[String: Any]])?.first,
          let details = record["assertionDetails"] as? [String: Any] else { return nil }
    return details["assertionDetailsModeIdentifier"] as? String
}

/// Maps mode identifiers to names using ModeConfigurations.json.
public func focusModeNames(configurations: Data) -> [String: String] {
    guard let root = (try? JSONSerialization.jsonObject(with: configurations)) as? [String: Any],
          let store = (root["data"] as? [[String: Any]])?.first,
          let modes = store["modeConfigurations"] as? [String: [String: Any]] else { return [:] }
    return modes.compactMapValues { ($0["mode"] as? [String: Any])?["name"] as? String }
}
