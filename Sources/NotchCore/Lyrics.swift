import Foundation

public struct LyricLine: Equatable {
    public let time: Double
    public let text: String
    public init(time: Double, text: String) { self.time = time; self.text = text }
}

/// Parses LRC text such as `[01:02.50] words`. A line can carry several timestamps.
public func parseLRC(_ lrc: String) -> [LyricLine] {
    var lines: [LyricLine] = []
    for raw in lrc.split(whereSeparator: \.isNewline) {
        var rest = Substring(raw)
        var times: [Double] = []
        while rest.first == "[", let close = rest.firstIndex(of: "]") {
            let stamp = rest[rest.index(after: rest.startIndex)..<close]
            let parts = stamp.split(separator: ":")
            guard parts.count == 2, let min = Double(parts[0]),
                  let sec = Double(parts[1].replacingOccurrences(of: ",", with: ".")) else { break }
            times.append(min * 60 + sec)
            rest = rest[rest.index(after: close)...]
        }
        let text = rest.trimmingCharacters(in: .whitespaces)
        lines += times.map { LyricLine(time: $0, text: text) }
    }
    return lines.sorted { $0.time < $1.time }
}

