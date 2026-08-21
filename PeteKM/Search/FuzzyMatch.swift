import Foundation

/// Subsequence fuzzy matching for command titles and Library filenames (§10.1, §10.3).
/// Deterministic and tiny — no ranking model, no AI (§11.5).
enum FuzzyMatch {

    /// Score for `query` against `candidate`, or nil when the query is not a
    /// subsequence of the candidate. Higher is better.
    /// An empty query matches everything with a neutral score.
    static func score(_ query: String, in candidate: String) -> Int? {
        let needle = Array(query.lowercased())
        guard !needle.isEmpty else { return 0 }

        let hay = Array(candidate.lowercased())
        guard needle.count <= hay.count else { return nil }

        var total = 0
        var needleIndex = 0
        var previousMatch = -2

        for (position, character) in hay.enumerated() {
            guard needleIndex < needle.count, character == needle[needleIndex] else { continue }

            var points = 1
            if position == previousMatch + 1 { points += 6 }        // contiguous run
            if position == 0 { points += 10 }                       // matches the start
            else if isBoundary(hay[position - 1]) { points += 6 }   // start of a word or path segment

            total += points
            previousMatch = position
            needleIndex += 1
        }

        guard needleIndex == needle.count else { return nil }

        // Shorter candidates win when the match quality is otherwise equal.
        return total - hay.count / 8
    }

    private static func isBoundary(_ character: Character) -> Bool {
        character == " " || character == "-" || character == "_" || character == "/" || character == "."
    }
}
