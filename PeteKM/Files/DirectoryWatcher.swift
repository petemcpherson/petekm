import Foundation

/// Watches a directory for changes. The directory — not the file — is the watch target because
/// atomic writes (ours, VS Code's, Claude Code's) replace the file, which kills a file-level source.
final class DirectoryWatcher {

    private let queue = DispatchQueue(label: "com.petekm.directory-watcher")
    private var source: DispatchSourceFileSystemObject?
    private var descriptor: CInt = -1
    private var pending: DispatchWorkItem?

    private let debounce: DispatchTimeInterval
    private let onChange: @Sendable () -> Void

    init(url: URL, debounce: DispatchTimeInterval = .milliseconds(200), onChange: @escaping @Sendable () -> Void) {
        self.debounce = debounce
        self.onChange = onChange
        start(url: url)
    }

    deinit {
        stop()
    }

    private func start(url: URL) {
        let fd = open(url.path(percentEncoded: false), O_EVTONLY)
        guard fd >= 0 else { return }
        descriptor = fd

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: [.write, .rename, .delete, .extend, .attrib],
            queue: queue
        )
        source.setEventHandler { [weak self] in self?.scheduleNotification() }
        source.setCancelHandler { close(fd) }
        source.resume()
        self.source = source
    }

    /// Coalesces the burst of events a single save produces into one callback.
    private func scheduleNotification() {
        pending?.cancel()
        let work = DispatchWorkItem { [onChange] in onChange() }
        pending = work
        queue.asyncAfter(deadline: .now() + debounce, execute: work)
    }

    func stop() {
        pending?.cancel()
        pending = nil
        source?.cancel()
        source = nil
        descriptor = -1
    }
}
