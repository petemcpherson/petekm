import Foundation

/// How a brand-new Daily Sticky begins (§7.3).
enum NewDayStart: String, CaseIterable, Identifiable, Sendable {
    case carryForwardHeaders
    case scratch
    case defaultHeaders

    var id: String { rawValue }

    /// Copy stays terse per DESIGN.md §39.
    var title: String {
        switch self {
        case .carryForwardHeaders: return "Carry forward headers"
        case .scratch: return "Start from scratch"
        case .defaultHeaders: return "Use default headers"
        }
    }
}

/// Builds the initial text of a new Daily Sticky. Pure — no file access.
enum NewDayComposer {

    static func content(
        start: NewDayStart,
        date: Date,
        showDateHeading: Bool,
        defaultHeaders: String,
        priorStickyText: String?,
        calendar: Calendar = .current
    ) -> String {
        switch start {
        case .scratch:
            return assemble(date: date, showDateHeading: showDateHeading, body: "", calendar: calendar)

        case .carryForwardHeaders:
            let headings = MarkdownHeadings.carryForward(from: priorStickyText ?? "")
            // No prior sticky, or a prior sticky with nothing to carry: silently scratch (§7.4).
            guard !headings.isEmpty else {
                return assemble(date: date, showDateHeading: showDateHeading, body: "", calendar: calendar)
            }
            let body = headings.map(\.line).joined(separator: "\n\n")
            return assemble(date: date, showDateHeading: showDateHeading, body: body, calendar: calendar)

        case .defaultHeaders:
            let body = defaultHeaders.trimmingCharacters(in: .whitespacesAndNewlines)
            return assemble(date: date, showDateHeading: showDateHeading, body: body, calendar: calendar)
        }
    }

    private static func assemble(date: Date, showDateHeading: Bool, body: String, calendar: Calendar) -> String {
        var pieces: [String] = []
        if showDateHeading {
            pieces.append(DailyDate.heading(for: date, calendar: calendar))
        }
        if !body.isEmpty {
            pieces.append(body)
        }
        guard !pieces.isEmpty else { return "" }
        return pieces.joined(separator: "\n\n") + "\n\n"
    }
}
