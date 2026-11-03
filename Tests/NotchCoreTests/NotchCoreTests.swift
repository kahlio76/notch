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

}
