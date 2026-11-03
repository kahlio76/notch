import Foundation

/// Lives at ~/.notch/config.json and is written with these defaults on first launch.
struct Config: Codable {
    var city = "Cupertino"
    var latitude = 37.323
    var longitude = -122.032
    var fahrenheit = true
    var pinnedApps = ["com.apple.Safari", "com.spotify.client", "md.obsidian", "com.anthropic.claudefordesktop"]

    static let directory = NSHomeDirectory() + "/.notch"
    static let path = directory + "/config.json"

    static func load() -> Config {
        if let data = FileManager.default.contents(atPath: path),
           let config = try? JSONDecoder().decode(Config.self, from: data) {
            return config
        }
        let config = Config()
        try? FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true,
                                                 attributes: [.posixPermissions: 0o700])
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        if !FileManager.default.fileExists(atPath: path), let data = try? encoder.encode(config) {
            FileManager.default.createFile(atPath: path, contents: data)
        }
        return config
    }
}
