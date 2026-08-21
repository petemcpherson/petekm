import Foundation

/// Where the user was last typing in each file (§8.3). Application state, not note data —
/// it lives in UserDefaults and losing it costs nothing but a jump to the end of the document.
struct CursorMemory {

    private static let key = "petekm.cursorPositions"
    private static let limit = 200

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func remember(_ range: NSRange, for url: URL) {
        var stored = positions()
        stored[url.path] = "\(range.location):\(range.length)"
        if stored.count > Self.limit {
            stored = Dictionary(uniqueKeysWithValues: stored.suffix(Self.limit))
        }
        defaults.set(stored, forKey: Self.key)
    }

    func selection(for url: URL) -> NSRange? {
        guard let raw = positions()[url.path] else { return nil }
        let parts = raw.split(separator: ":").compactMap { Int($0) }
        guard parts.count == 2, parts[0] >= 0, parts[1] >= 0 else { return nil }
        return NSRange(location: parts[0], length: parts[1])
    }

    private func positions() -> [String: String] {
        defaults.dictionary(forKey: Self.key) as? [String: String] ?? [:]
    }
}
