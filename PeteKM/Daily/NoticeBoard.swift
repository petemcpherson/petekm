import Foundation
import Observation

/// The one-line notice at the bottom of the window. One notice shows at a time and a
/// newer one replaces it — except a notice that must be seen: if something replaces
/// it, it waits and comes back once the replacement times out. The launch sync notice
/// arrives a second after the window opens, so without this the agent-files notice
/// could lose to it on every launch and never be read.
@MainActor
@Observable
final class NoticeBoard {

    private(set) var text: String?

    private struct Entry {
        let text: String
        let seconds: Double
        let mustBeSeen: Bool
        let onShownFully: (() -> Void)?
    }

    @ObservationIgnored private var current: Entry?
    @ObservationIgnored private var waiting: Entry?
    @ObservationIgnored private var timer: Task<Void, Never>?

    /// `onShownFully` runs only once the notice has stayed up its full time.
    func show(_ text: String, seconds: Double = 6, mustBeSeen: Bool = false,
              onShownFully: (() -> Void)? = nil) {
        if let current, current.mustBeSeen, waiting == nil {
            waiting = current
        }
        present(Entry(text: text, seconds: seconds, mustBeSeen: mustBeSeen, onShownFully: onShownFully))
    }

    /// The window went away. Nothing is recorded as seen; a must-be-seen notice
    /// is asked for again the next time the window appears.
    func clear() {
        timer?.cancel()
        timer = nil
        current = nil
        waiting = nil
        text = nil
    }

    private func present(_ entry: Entry) {
        timer?.cancel()
        current = entry
        text = entry.text
        timer = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(entry.seconds))
            guard !Task.isCancelled, let self else { return }
            self.current = nil
            self.text = nil
            entry.onShownFully?()
            if let next = self.waiting {
                self.waiting = nil
                self.present(next)
            }
        }
    }
}
