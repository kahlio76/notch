import XCTest
@testable import NotchCore

final class NotchCoreTests: XCTestCase {
    func testParsesAndSortsLRC() {
        let lines = parseLRC("[ar:Someone]\n[00:10.50] Second\n[00:01.00][00:20,00] Repeated\n[00:15.00]\n")
        XCTAssertEqual(lines.map(\.text), ["Repeated", "Second", "", "Repeated"])
        XCTAssertEqual(lines[1].time, 10.5)
        XCTAssertEqual(lines[3].time, 20)
    }

    func testLyricIndex() {
        let lines = [LyricLine(time: 1, text: "a"), LyricLine(time: 5, text: "b")]
        XCTAssertNil(lyricIndex(in: lines, at: 0.5))
        XCTAssertEqual(lyricIndex(in: lines, at: 1), 0)
        XCTAssertEqual(lyricIndex(in: lines, at: 4.9), 0)
        XCTAssertEqual(lyricIndex(in: lines, at: 500), 1)
        XCTAssertNil(lyricIndex(in: [], at: 3))
    }

    private func event(_ tool: String, _ input: String) -> ClaudeEvent {
        let json = #"{"hook_event_name":"PermissionRequest","session_id":"s","cwd":"/a/proj","tool_name":"\#(tool)","tool_input":\#(input)}"#
        return ClaudeEvent(json: Data(json.utf8))!
    }

    func testSummaries() {
        let longCommand = String(repeating: "x", count: 5000)
        XCTAssertEqual(event("Bash", #"{"command":"\#(longCommand)"}"#).summary, longCommand)
        XCTAssertEqual(event("Edit", #"{"file_path":"/a/proj/src/x.swift"}"#).summary, "Edit src/x.swift")
        XCTAssertEqual(event("Write", #"{"file_path":"/elsewhere/x"}"#).summary, "Write /elsewhere/x")
        XCTAssertEqual(event("mcp__x__y", #"{"b":1,"a":2}"#).summary, #"mcp__x__y {"a":2,"b":1}"#)
        XCTAssertEqual(event("Bash", "{}").project, "proj")
    }

    func testPromptsWithMoreThanYesOrNoStayInClaude() {
        XCTAssertFalse(event("AskUserQuestion", "{}").isApprovableFromNotch)
        XCTAssertFalse(event("ExitPlanMode", "{}").isApprovableFromNotch)
        XCTAssertTrue(event("Bash", "{}").isApprovableFromNotch)
    }

    func testChangedFileOnlyForEditingTools() {
        XCTAssertEqual(event("Edit", #"{"file_path":"/f"}"#).changedFile, "/f")
        XCTAssertNil(event("Read", #"{"file_path":"/f"}"#).changedFile)
    }

    func testDecisionJSON() throws {
        func behavior(_ data: Data) throws -> [String: Any] {
            let root = try JSONSerialization.jsonObject(with: data) as! [String: Any]
            let specific = root["hookSpecificOutput"] as! [String: Any]
            XCTAssertEqual(specific["hookEventName"] as? String, "PermissionRequest")
            return specific["decision"] as! [String: Any]
        }
        XCTAssertEqual(try behavior(permissionDecision(allow: true))["behavior"] as? String, "allow")
        XCTAssertEqual(try behavior(permissionDecision(allow: false))["behavior"] as? String, "deny")
    }

    func testBadPayloadIsRejected() {
        XCTAssertNil(ClaudeEvent(json: Data("nope".utf8)))
        XCTAssertNil(ClaudeEvent(json: Data("{}".utf8)))
    }

    func testDurations() {
        XCTAssertEqual(doneDuration(10.2), "Done in 10 s")
        XCTAssertEqual(doneDuration(125), "Done in 2 min")
        XCTAssertEqual(doneDuration(3720), "Done in 1 h 2 min")
    }

    func testFocusParsing() {
        let on = #"{"data":[{"storeAssertionRecords":[{"assertionDetails":{"assertionDetailsModeIdentifier":"com.apple.focus.work"}}]}]}"#
        XCTAssertEqual(activeFocusMode(assertions: Data(on.utf8)), "com.apple.focus.work")
        XCTAssertNil(activeFocusMode(assertions: Data(#"{"data":[{"storeAssertionRecords":[]}]}"#.utf8)))
        let names = #"{"data":[{"modeConfigurations":{"a":{"mode":{"name":"Work"}}}}]}"#
        XCTAssertEqual(focusModeNames(configurations: Data(names.utf8)), ["a": "Work"])
    }

    private func sine(_ frequency: Double, amplitude: Float = 1, count: Int = 1024, rate: Double = 48_000) -> [Float] {
        (0..<count).map { amplitude * Float(sin(2 * .pi * frequency * Double($0) / rate)) }
    }

    func testSpectrumPutsToneInItsBand() {
        let spectrum = Spectrum()
        for (frequency, band) in [(80.0, 0), (250.0, 1), (900.0, 2), (3_000.0, 3), (9_000.0, 4)] {
            let decibels = spectrum.decibels(sine(frequency), sampleRate: 48_000)
            XCTAssertEqual(decibels.firstIndex(of: decibels.max()!), band, "\(frequency) Hz")
            XCTAssertEqual(decibels[band], 0, accuracy: 3, "full-scale sine reads about 0 dB")
        }
        XCTAssertTrue(spectrum.decibels([Float](repeating: 0, count: 1024), sampleRate: 48_000).allSatisfy { $0 < -100 })
    }

    func testBandMeterRisesFastAndFallsSlowly() {
        var meter = BandMeter(count: 1)
        let up = meter.update([0])[0]
        XCTAssertGreaterThan(up, 0.6)
        let down = meter.update([-40])[0]
        XCTAssertLessThan(down, up)
        XCTAssertGreaterThan(down, up * 0.7)
        for _ in 0..<40 { _ = meter.update([-40]) }
        XCTAssertLessThan(meter.levels[0], 0.05)
    }
}
