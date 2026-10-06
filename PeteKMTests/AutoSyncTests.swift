import Foundation
import Testing
@testable import PeteKM

// Sync v2 coordinator (context/sync-v2/spec.md §5, §6.6, §8.3): a scripted git,
// a fake clock, and a fake network. The last test drives two real clones.

// MARK: - Fakes

/// A tiny in-memory model of one clone, answering just the git calls the run makes.
final class ScriptedGit: GitRunner, @unchecked Sendable {
    private let lock = NSLock()
    private var _calls: [[String]] = []

    var dirty = false
    var ahead = 0
    var behind = 0
    var fetchSucceeds = true
    var pushSucceeds = true
    var rebaseSucceeds = true
    var head = "head-1"
    var upstream = "upstream-1"
    var incomingTrailer = ""
    var changedOnBothSides = ""
    /// When set, every fetch blocks until it is signalled.
    var fetchGate: DispatchSemaphore?

    var calls: [[String]] {
        lock.lock()
        defer { lock.unlock() }
        return _calls
    }

    func count(_ subcommand: String) -> Int {
        calls.filter { $0.first == subcommand && !$0.contains("--abort") }.count
    }

    func run(_ arguments: [String], in directory: URL, timeout: Duration) -> GitResult {
        lock.lock()
        _calls.append(arguments)
        let gate = arguments.first == "fetch" ? fetchGate : nil
        lock.unlock()
        gate?.wait()

        lock.lock()
        defer { lock.unlock() }
        switch arguments.first {
        case "remote": return Self.ok("origin")
        case "status": return Self.ok(dirty ? " M daily/2026-10-05.md" : "")
        case "commit":
            dirty = false
            ahead += 1
            head = UUID().uuidString
            return Self.ok()
        case "fetch": return fetchSucceeds ? Self.ok() : .failed("Could not resolve host")
        case "rev-list": return Self.ok("\(ahead)\t\(behind)")
        case "rev-parse":
            switch arguments.last {
            case "HEAD": return Self.ok(head)
            case "@{upstream}": return Self.ok(upstream)
            default: return Self.ok("main")
            }
        case "merge-base": return Self.ok("base")
        case "-c": return Self.ok(changedOnBothSides)
        case "log": return Self.ok(arguments.contains("1") ? incomingTrailer : "")
        case "rebase":
            if arguments.contains("--abort") { return Self.ok() }
            guard rebaseSucceeds else { return .failed("CONFLICT") }
            behind = 0
            return Self.ok()
        case "push":
            guard pushSucceeds else { return .failed("Permission denied") }
            ahead = 0
            return Self.ok()
        default: return Self.ok()
        }
    }

    private static func ok(_ stdout: String = "") -> GitResult {
        GitResult(status: 0, stdout: stdout, stderr: "", timedOut: false)
    }
}

@MainActor
final class FakeNetwork: NetworkStatus {
    var isSatisfied = true
    func start(onChange: @escaping @MainActor @Sendable (Bool) -> Void) {}
    func stop() {}
}

@MainActor
final class TestClock {
    var now = Date(timeIntervalSince1970: 1_790_000_000)

    func advance(minutes: Double) {
        now = now.addingTimeInterval(minutes * 60)
    }
}

@MainActor
private struct Harness {
    let git = ScriptedGit()
    let clock = TestClock()
    let settings: AppSettings
    let autoSync: AutoSync
    let folder: PeteKMFolder

    init() throws {
        settings = AppSettings(defaults: UserDefaults(suiteName: "petekm.tests.\(UUID().uuidString)")!)
        let root = URL(filePath: NSTemporaryDirectory(), directoryHint: .isDirectory)
            .appending(path: "petekm-autosync-\(UUID().uuidString)", directoryHint: .isDirectory)
        folder = PeteKMFolder(root: root)
        try FileManager.default.createDirectory(at: folder.gitDirectory, withIntermediateDirectories: true)
        let clock = clock
        autoSync = AutoSync(settings: settings, runner: git, network: FakeNetwork(),
                            now: { clock.now }, device: "Mac B", editorName: { "VS Code" },
                            observesSystem: false)
    }

    /// Starts on the folder and waits out the folder-ready run.
    func start() async {
        await autoSync.start(folder: folder)?.value
    }
}

// MARK: - Coalescing (§5)

@Test @MainActor func triggersDuringARunCoalesceIntoOneFollowUp() async throws {
    let h = try Harness()
    await h.start()
    let fetchesBefore = h.git.count("fetch")

    let gate = DispatchSemaphore(value: 0)
    h.git.fetchGate = gate
    let first = Task { await h.autoSync.request(.presencePoll) }
    while h.git.count("fetch") == fetchesBefore { try await Task.sleep(for: .milliseconds(5)) }

    let others = [AutoSync.Trigger.networkRegained, .wake, .presencePoll].map { trigger in
        Task { await h.autoSync.request(trigger) }
    }
    try await Task.sleep(for: .milliseconds(100))
    h.git.fetchGate = nil
    gate.signal()

    _ = await first.value
    for other in others { _ = await other.value }

    #expect(h.git.count("fetch") == fetchesBefore + 2)
}

@Test @MainActor func departureWithNothingLocalDoesNothing() async throws {
    let h = try Harness()
    await h.start()
    let callsBefore = h.git.calls.count

    let run = await h.autoSync.request(.hide)

    #expect(run == nil)
    #expect(h.git.calls.count == callsBefore + 2)    // status --porcelain + rev-list only
    #expect(h.git.count("fetch") == 1)
}

@Test @MainActor func summonOnlyFetchesWhenStale() async throws {
    let h = try Harness()
    await h.start()

    h.clock.advance(minutes: 2)
    #expect(await h.autoSync.request(.summon) == nil)

    h.clock.advance(minutes: 4)
    #expect(await h.autoSync.request(.summon) != nil)
    #expect(h.git.count("fetch") == 2)
}

// MARK: - Back-off (§6.6)

@Test @MainActor func offlineCommitsLocallyUntilTheNetworkReturns() async throws {
    let h = try Harness()
    h.git.fetchSucceeds = false
    await h.start()
    guard case .offline = h.autoSync.status else {
        Issue.record("Expected offline, got \(h.autoSync.status)")
        return
    }

    h.git.dirty = true
    let local = await h.autoSync.request(.hide)
    #expect(local?.didCommit == true)
    #expect(h.git.count("fetch") == 1)
    #expect(h.autoSync.status == .offline(since: h.clock.now, pendingSince: h.clock.now))

    #expect(await h.autoSync.request(.presencePoll) == nil)
    #expect(h.git.count("fetch") == 1)

    h.git.fetchSucceeds = true
    let back = await h.autoSync.request(.networkRegained)
    #expect(back?.pushSucceeded == true)
    #expect(h.autoSync.status == .synced(at: h.clock.now))
}

@Test @MainActor func pushFailureWaitsFifteenMinutes() async throws {
    let h = try Harness()
    await h.start()
    h.git.pushSucceeds = false

    h.git.dirty = true
    await h.autoSync.request(.hide)
    #expect(h.autoSync.status == .failing(.push))
    #expect(h.git.count("push") == 1)

    h.clock.advance(minutes: 5)
    h.git.dirty = true
    let suppressed = await h.autoSync.request(.editIdle)
    #expect(suppressed?.didCommit == true)
    #expect(h.git.count("push") == 1)
    #expect(h.autoSync.status == .failing(.push))
    #expect(await h.autoSync.request(.presencePoll) == nil)

    await h.autoSync.request(.manual)
    #expect(h.git.count("push") == 2)

    h.clock.advance(minutes: 16)
    h.git.pushSucceeds = true
    await h.autoSync.request(.hide)
    #expect(h.git.count("push") == 3)
    #expect(h.autoSync.status == .synced(at: h.clock.now))
}

@Test @MainActor func conflictPausesRebasesUntilSomethingChanges() async throws {
    let h = try Harness()
    await h.start()
    _ = h.autoSync.consumeNotice()

    h.git.behind = 1
    h.git.rebaseSucceeds = false
    await h.autoSync.request(.presencePoll)
    #expect(h.autoSync.status == .paused)
    #expect(h.git.count("rebase") == 1)
    #expect(h.autoSync.consumeNotice()?.seconds == 15)

    // Our own departure commit moves HEAD, but isn't a reason to retry.
    h.git.dirty = true
    await h.autoSync.request(.hide)
    await h.autoSync.request(.presencePoll)
    #expect(h.git.count("rebase") == 1)
    #expect(h.git.count("push") == 0)
    #expect(h.autoSync.status == .paused)

    h.git.upstream = "upstream-2"
    await h.autoSync.request(.presencePoll)
    #expect(h.git.count("rebase") == 2)
    await h.autoSync.request(.presencePoll)
    #expect(h.git.count("rebase") == 2)
    #expect(h.autoSync.consumeNotice() == nil)

    h.git.rebaseSucceeds = true
    h.git.head = "resolved-in-terminal"
    await h.autoSync.request(.presencePoll)
    #expect(h.git.count("rebase") == 3)
    #expect(h.autoSync.status == .synced(at: h.clock.now))
}

@Test @MainActor func toggleOffStopsTriggersButNotManual() async throws {
    let h = try Harness()
    await h.start()

    h.settings.syncAutomatically = false
    try await Task.sleep(for: .milliseconds(50))

    #expect(h.autoSync.status == .off)
    #expect(h.autoSync.isActive == false)
    #expect(await h.autoSync.request(.presencePoll) == nil)
    #expect(await h.autoSync.request(.manual) != nil)
    #expect(h.autoSync.status == .off)

    h.settings.syncAutomatically = true
    try await Task.sleep(for: .milliseconds(50))
    #expect(h.autoSync.isActive)
}

// MARK: - Notices (§8.3)

@Test @MainActor func incomingNoticeNamesTheOtherMac() async throws {
    let h = try Harness()
    h.git.behind = 1
    h.git.incomingTrailer = "Mac A"
    await h.start()
    #expect(h.autoSync.consumeNotice() == AutoSyncNotice(text: "Updated from Mac A.", seconds: 4))

    h.git.behind = 1
    h.git.incomingTrailer = ""
    await h.autoSync.request(.wake)
    #expect(h.autoSync.consumeNotice() == AutoSyncNotice(text: "Updated from GitHub.", seconds: 4))

    h.git.behind = 1
    h.git.changedOnBothSides = "daily/2026-10-05.md"
    await h.autoSync.request(.wake)
    #expect(h.autoSync.consumeNotice() == AutoSyncNotice(text: AutoSync.mergedDailyNotice, seconds: 6))

    // Manual runs answer through their caller, never the automatic notice.
    h.git.behind = 1
    await h.autoSync.request(.manual)
    #expect(h.autoSync.consumeNotice() == nil)
}

@Test @MainActor func noRepositoryMakesAutomaticSyncInert() async throws {
    let h = try Harness()
    try FileManager.default.removeItem(at: h.folder.gitDirectory)
    await h.start()

    #expect(h.autoSync.status == .off)
    #expect(h.git.count("fetch") == 0)
}

// MARK: - Integration with real clones

@Test @MainActor func hideOnOneMacArrivesOnTheOther() async throws {
    // Building the clones runs git synchronously; keep it off the main actor.
    guard let fixture = try await Task.detached(operation: { try GitFixture() }).value else { return }
    let originCount = { await Task.detached { fixture.originCommitCount }.value }
    func autoSync(_ device: String) -> AutoSync {
        let settings = AppSettings(defaults: UserDefaults(suiteName: "petekm.tests.\(UUID().uuidString)")!)
        return AutoSync(settings: settings, network: FakeNetwork(), device: device, observesSystem: false)
    }

    let macA = autoSync("Mac A")
    await macA.start(folder: fixture.a)?.value
    try fixture.write("- from A\n", "daily/2026-10-05.md", in: fixture.a)
    let before = await originCount()
    let sent = await macA.request(.hide)
    #expect(sent?.pushSucceeded == true)
    #expect(await originCount() == before + 1)

    let macB = autoSync("Mac B")
    await macB.start(folder: fixture.b)?.value
    #expect(macB.consumeNotice()?.text == "Updated from Mac A.")
    #expect(try fixture.read("daily/2026-10-05.md", in: fixture.b) == Data("- from A\n".utf8))
    #expect(macB.otherDeviceLast?.name == "Mac A")
    #expect(macB.status == .synced(at: macB.lastFetchAt!))
}
