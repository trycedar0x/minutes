import Foundation

public struct MeetingNoteItem: Codable, Equatable, Sendable {
    public let text: String
    /// One-based indices into the transcript used for generation.
    public let sources: [Int]
    public let owner: String?
    public let due: String?
}

public struct MeetingNotes: Codable, Equatable, Sendable {
    public let summary: [MeetingNoteItem]
    public let decisions: [MeetingNoteItem]
    public let actions: [MeetingNoteItem]
    public let questions: [MeetingNoteItem]

    public static func decode(_ data: Data, transcriptCount: Int) throws -> MeetingNotes {
        let notes = try JSONDecoder().decode(Self.self, from: data)
        let items = notes.summary + notes.decisions + notes.actions + notes.questions
        guard !notes.summary.isEmpty, items.allSatisfy({
            !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
            !$0.sources.isEmpty && $0.sources.allSatisfy { $0 > 0 && $0 <= transcriptCount }
        }) else {
            throw NSError(domain: "MeetingNotes", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "Meeting notes contain missing or invalid transcript references."])
        }
        return notes
    }

    public func markdown(transcript: [TranscriptLine]) -> String {
        var output = "# Meeting notes\n\nAI-generated locally. Verify important details against the transcript. Long meetings are summarized in sections; later discussion may revise earlier points.\n"
        for (title, items) in [("Summary", summary), ("Decisions", decisions),
                               ("Action items", actions), ("Open questions", questions)] {
            output += "\n## \(title)\n\n"
            if items.isEmpty { output += "None identified.\n" }
            for item in items {
                output += "- \(item.text)"
                if title == "Action items" {
                    output += " — Owner: \(item.owner ?? "Not specified"); Due: \(item.due ?? "Not specified")"
                }
                output += " " + item.sources.map { "[\($0)]" }.joined(separator: " ") + "\n"
            }
        }
        output += "\n## Transcript references\n\n"
        let references = Set((summary + decisions + actions + questions).flatMap(\.sources)).sorted()
        for index in references where index > 0 && index <= transcript.count {
            let line = transcript[index - 1]
            output += "[\(index)] [\(line.timestamp)] \(line.speaker): \(line.text)\n\n"
        }
        return output
    }
}
