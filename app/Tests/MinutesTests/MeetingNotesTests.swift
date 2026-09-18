import XCTest
@testable import MinutesCore

final class MeetingNotesTests: XCTestCase {
    private func payload(sources: String = "[1]", summary: String? = nil) -> Data {
        let items = summary ?? "[{\"text\":\"Discussed release\",\"sources\":\(sources)}]"
        return Data("""
        {"summary":\(items),"decisions":[],
         "actions":[{"text":"Test release","sources":\(sources),"owner":null,"due":null}],
         "questions":[]}
        """.utf8)
    }

    func testDecodeAndExportCitedNotes() throws {
        let notes = try MeetingNotes.decode(payload(), transcriptCount: 1)
        XCTAssertNil(notes.actions.first?.owner)
        let transcript = [TranscriptLine(timestamp: "00:01 → 00:02", speaker: "SPEAKER_00",
                                         text: "Test release", speakerIndex: 0)]
        let markdown = notes.markdown(transcript: transcript)
        XCTAssertTrue(markdown.contains("## Summary"))
        XCTAssertTrue(markdown.contains("## Decisions\n\nNone identified."))
        XCTAssertTrue(markdown.contains("Owner: Not specified; Due: Not specified"))
        XCTAssertTrue(markdown.contains("[1] [00:01 → 00:02] SPEAKER_00: Test release"))
        XCTAssertEqual(markdown.components(separatedBy: "SPEAKER_00:").count, 2)
    }

    func testRejectsInvalidReferences() {
        for refs in ["[]", "[0]", "[-1]", "[2]", "[1.5]", "[\"1\"]", "[true]"] {
            XCTAssertThrowsError(try MeetingNotes.decode(payload(sources: refs), transcriptCount: 1), refs)
        }
        XCTAssertThrowsError(try MeetingNotes.decode(payload(), transcriptCount: 0))
    }

    func testRejectsMissingSummaryAndMalformedPayload() {
        XCTAssertThrowsError(try MeetingNotes.decode(payload(summary: "[]"), transcriptCount: 1))
        XCTAssertThrowsError(try MeetingNotes.decode(Data("{}".utf8), transcriptCount: 1))
        XCTAssertThrowsError(try MeetingNotes.decode(payload(summary: "[{\"text\":\"  \",\"sources\":[1]}]"), transcriptCount: 1))
    }
}
