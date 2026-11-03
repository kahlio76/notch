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

    func testBadPayloadIsRejected() {
        XCTAssertNil(ClaudeEvent(json: Data("nope".utf8)))
        XCTAssertNil(ClaudeEvent(json: Data("{}".utf8)))
    }

}
