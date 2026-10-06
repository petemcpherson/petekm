import AppKit
import Foundation
import Network
import Observation

/// What the user can learn about sync at a glance (sync v2 §8.1).
enum SyncStatus: Equatable, Sendable {
    case off
    case synced(at: Date)
    case syncing
    case pending(since: Date)
    case offline(since: Date, pendingSince: Date?)
    case paused
    case failing(FailReason)

    enum FailReason: Equatable, Sendable {
        case push
        case lock
    }
}

/// One line for the existing transient notice slot (§8.3).
struct AutoSyncNotice: Equatable, Sendable {
    let text: String
    let seconds: Double
}

/// Network reachability, behind a protocol so tests can flip it.
@MainActor
protocol NetworkStatus: AnyObject {
    var isSatisfied: Bool { get }
    func start(onChange: @escaping @MainActor @Sendable (Bool) -> Void)
    func stop()
}

@MainActor
final class PathNetworkStatus: NetworkStatus {
    private(set) var isSatisfied = true
    private var monitor: NWPathMonitor?
    private let queue = DispatchQueue(label: "petekm.network", qos: .utility)

    func start(onChange: @escaping @MainActor @Sendable (Bool) -> Void) {
        stop()
        // A cancelled NWPathMonitor can't be restarted; make a fresh one.
        let monitor = NWPathMonitor()
        let update: @MainActor @Sendable (Bool) -> Void = { [weak self] satisfied in
            self?.isSatisfied = satisfied
            onChange(satisfied)
        }
        monitor.pathUpdateHandler = { path in
            let satisfied = path.status == .satisfied
            Task { @MainActor in update(satisfied) }
        }
        monitor.start(queue: queue)
        self.monitor = monitor
    }

    func stop() {
        monitor?.cancel()
        monitor = nil
    }
}

/// Decides *when* to sync; `GitSupport.run` decides *what* happens (sync v2 §3.1,
/// §10.1). Every trigger goes through `request(_:)`, which keeps at most one run
/// in flight plus one coalesced follow-up, and applies the back-off rules (§6.6).
@MainActor
@Observable
final class AutoSync {

    enum Trigger: Hashable, Sendable {
        case folderReady, wake, summon, networkRegained, presencePoll
        case hide, editIdle, sleep, quit
        case newDay, manual

        /// Brings changes in (§5.1).
        var isArrival: Bool {
            switch self {
            case .folderReady, .wake, .summon, .networkRegained, .presencePoll, .newDay: true
            default: false
            }
        }

        /// Sends changes out, and only when there are local changes (§5.2).
        var isDeparture: Bool {
            switch self {
            case .hide, .editIdle, .sleep, .quit: true
            default: false
            }
        }

        /// May try the network while offline back-off holds (§6.6).
        var probesNetwork: Bool {
            switch self {
            case .folderReady, .wake, .summon, .networkRegained, .newDay, .manual: true
            default: false
            }
        }
    }

    /// Every timing constant from §10.3.
    enum Timing {
        static let summonStaleness: TimeInterval = 5 * 60
        static let presencePoll: Duration = .seconds(5 * 60)
        static let editIdle: Duration = .seconds(60)
        static let hideDebounce: Duration = .seconds(2)
        static let pendingSignalAfter = SyncStatus.pendingSignalAfter
        static let statusTick: Duration = .seconds(30)
        static let newDayBudget: TimeInterval = 2
        static let wakeNetworkWait: Duration = .seconds(20)
        static let sleepBudget: TimeInterval = 5
        static let quitBudget: TimeInterval = 5
        static let networkTimeout = GitSupport.Timeouts.network
        static let localTimeout = GitSupport.Timeouts.local
        static let pushFailedRetry: TimeInterval = 15 * 60
        static let staleLock = GitSupport.Timeouts.staleLock
    }

    static let mergedDailyNotice = "Merged today's Daily Sticky from both Macs. Check the order."

    static func updatedNotice(from device: String?) -> String {
        "Updated from \(device ?? "GitHub")."
    }

    static let earlierNotesNotice = "Notes from earlier on this Mac haven't reached GitHub yet."

    // MARK: Published state

    private(set) var status: SyncStatus = .off {
        didSet {
            statusClock = now()
            if status != .syncing { lastSettled = status }
        }
    }
    /// The status before the current run, so the light keeps its color while it
    /// pulses for a run.
    private(set) var lastSettled: SyncStatus = .off
    /// Advanced every `Timing.statusTick` while the status line is time-sensitive,
    /// so the dot appears at the 2-minute mark without another trigger (§8.1).
    private(set) var statusClock = Date()
    private(set) var lastFetchAt: Date?
    private(set) var lastRunStderr = ""
    private(set) var otherDeviceLast: (name: String, at: Date)?
    /// One-shot; the view takes it with `consumeNotice()`.
    private(set) var lastNotice: AutoSyncNotice?
    /// Set on wake for the earlier-notes notice (§9.2.3).
    private(set) var wokeAt: Date?

    /// Automatic sync is on and watching a folder.
    private(set) var isActive = false

    @ObservationIgnored weak var session: DailySession?

    // MARK: Dependencies

    @ObservationIgnored private let settings: AppSettings
    @ObservationIgnored private let runner: GitRunner
    @ObservationIgnored private let network: NetworkStatus
    @ObservationIgnored private let now: () -> Date
    @ObservationIgnored private let device: String
    @ObservationIgnored private let editorName: () -> String
    @ObservationIgnored private let observesSystem: Bool

    // MARK: Run and back-off state

    @ObservationIgnored private(set) var folder: PeteKMFolder?
    @ObservationIgnored private var isEligible: Bool?
    /// Refreshed after every run, so Pre-New-Day never shells out on the main actor (§6.5).
    @ObservationIgnored private var hasUpstream: Bool?
    @ObservationIgnored private var inFlight = false
    @ObservationIgnored private var runAgain = false
    @ObservationIgnored private var queued: Set<Trigger> = []
    @ObservationIgnored private var waiters: [CheckedContinuation<GitSupport.SyncRun?, Never>] = []

    @ObservationIgnored private var pendingSince: Date?
    @ObservationIgnored private var offlineSince: Date?
    @ObservationIgnored private var pushFailedAt: Date?
    /// HEAD and @{upstream} while paused on a conflict; a change means retry once.
    @ObservationIgnored private var pause: (head: String?, upstream: String?)?

    // MARK: Observers and timers

    @ObservationIgnored private var tokens: [(NotificationCenter, NSObjectProtocol)] = []
    @ObservationIgnored private var lastSatisfied: Bool?
    @ObservationIgnored private var windowVisible = true
    @ObservationIgnored private var hideTask: Task<Void, Never>?
    @ObservationIgnored private var idleTask: Task<Void, Never>?
    @ObservationIgnored private var presenceTask: Task<Void, Never>?
    @ObservationIgnored private var tickTask: Task<Void, Never>?
    @ObservationIgnored private let launchedAt: Date

    init(settings: AppSettings,
         runner: GitRunner = ProcessGitRunner(),
         network: NetworkStatus? = nil,
         now: @escaping () -> Date = Date.init,
         device: String = GitSupport.deviceName,
         editorName: (() -> String)? = nil,
         observesSystem: Bool = true) {
        self.settings = settings
        self.runner = runner
        self.network = network ?? PathNetworkStatus()
        self.now = now
        self.device = device
        self.editorName = editorName ?? { ExternalEditorProvider.current.displayName }
        self.observesSystem = observesSystem
        self.launchedAt = now()
        observeSetting()
    }

    // MARK: Lifecycle

    func register(_ session: DailySession) {
        self.session = session
        session.attach(self)
    }

    /// The §6.5 conditions that belong to sync: automatic sync on and an upstream to ask.
    /// The session checks the other two (today, file missing).
    func canDeferNewDay(in folder: PeteKMFolder) -> Bool {
        guard settings.syncAutomatically else { return false }
        if self.folder == folder {
            if isEligible == false { return false }
            if let hasUpstream { return hasUpstream }
        }
        return GitSupport.hasConfiguredUpstream(folder)
    }

    /// Called when the sticky view appears for a ready folder (§5.1 "Folder becomes ready").
    /// Returns the folder-ready run, for tests to await.
    @discardableResult
    func start(folder: PeteKMFolder) -> Task<Void, Never>? {
        if self.folder != folder {
            self.folder = folder
            resetRunState()
            teardown()
        }
        windowVisible = true
        return activate()
    }

    func stop() {
        teardown()
    }

    // MARK: Visibility (§8.2, §8.4)

    var dotStyle: SyncDotStyle {
        guard settings.syncAutomatically, status != .off else { return .hidden }
        guard status == .syncing else { return status.dot }
        let settled = lastSettled.dot
        return settled == .hidden ? .neutral : settled
    }

    var isSyncing: Bool { status == .syncing }

    /// Drives the menu-bar badge (§8.2).
    var needsAttention: Bool {
        settings.syncAutomatically && status.needsAttention(now: statusClock)
    }

    /// When this Mac last heard from GitHub, so "up to date" is visible.
    var fetchLine: String? {
        guard status != .off else { return nil }
        return SyncTime.fetchLine(lastFetchAt, now: statusClock)
    }

    var statusLine: String? {
        status.line(now: statusClock)
    }

    /// "Last from <other Mac>: <time>." for the popover, menu tooltip, and Settings (§9.3).
    var otherDeviceLine: String? {
        guard status != .off else { return nil }
        return SyncTime.otherDeviceLine(otherDeviceLast, now: statusClock)
    }

    func consumeNotice() -> AutoSyncNotice? {
        defer { lastNotice = nil }
        return lastNotice
    }

    @discardableResult
    private func activate() -> Task<Void, Never>? {
        guard settings.syncAutomatically, folder != nil else {
            status = .off
            return nil
        }
        guard !isActive else { return nil }
        isActive = true
        if case .off = status { status = pendingSince.map { .pending(since: $0) } ?? .syncing }
        installObservers()
        startPresencePoll()
        startStatusTick()
        return fire(.folderReady)
    }

    private func teardown() {
        isActive = false
        for (center, token) in tokens { center.removeObserver(token) }
        tokens = []
        if observesSystem { network.stop() }
        lastSatisfied = nil
        hideTask?.cancel()
        idleTask?.cancel()
        presenceTask?.cancel()
        tickTask?.cancel()
        tickTask = nil
        hideTask = nil
        idleTask = nil
        presenceTask = nil
        status = .off
    }

    private func resetRunState() {
        isEligible = nil
        hasUpstream = nil
        pendingSince = nil
        offlineSince = nil
        pushFailedAt = nil
        pause = nil
        lastFetchAt = nil
        otherDeviceLast = nil
        lastRunStderr = ""
    }

    private func observeSetting() {
        withObservationTracking {
            _ = settings.syncAutomatically
        } onChange: {
            Task { @MainActor [weak self] in
                guard let self else { return }
                if self.settings.syncAutomatically { self.activate() } else { self.teardown() }
                self.observeSetting()
            }
        }
    }

    // MARK: Trigger sources (§5.1–§5.3)

    private func installObservers() {
        guard observesSystem else { return }
        let workspace = NSWorkspace.shared.notificationCenter
        let center = NotificationCenter.default

        observe(workspace, NSWorkspace.didWakeNotification) { $0.systemDidWake() }
        observe(workspace, NSWorkspace.willSleepNotification) { $0.fire(.sleep) }
        observe(center, .peteKMDidSummon) { $0.windowDidSummon() }
        observe(center, .peteKMDidHide) { $0.windowDidHide() }

        network.start { [weak self] satisfied in
            guard let self else { return }
            let regained = self.lastSatisfied == false && satisfied
            self.lastSatisfied = satisfied
            if regained { self.fire(.networkRegained) }
        }
    }

    private func observe(_ center: NotificationCenter, _ name: Notification.Name,
                         _ handler: @escaping @MainActor (AutoSync) -> Void) {
        let token = center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.isActive else { return }
                handler(self)
            }
        }
        tokens.append((center, token))
    }

    @discardableResult
    private func fire(_ trigger: Trigger) -> Task<Void, Never> {
        Task { await request(trigger) }
    }

    private func systemDidWake() {
        wokeAt = now()
        Task {
            // Give Wi-Fi a moment to come back before the arrival run.
            let clock = ContinuousClock()
            let limit = clock.now.advanced(by: Timing.wakeNetworkWait)
            while !network.isSatisfied, clock.now < limit {
                try? await Task.sleep(for: .milliseconds(500))
            }
            await request(.wake)
        }
    }

    private func windowDidSummon() {
        windowVisible = true
        hideTask?.cancel()
        hideTask = nil
        startPresencePoll()
        repeatProblemNotice()
        fire(.summon)
    }

    /// A problem is repeated every time the window comes up until it's fixed, so it
    /// can't be missed by looking away once.
    private func repeatProblemNotice() {
        switch status {
        case .paused, .failing:
            if let line = statusLine { lastNotice = AutoSyncNotice(text: line, seconds: 8) }
        default:
            break
        }
    }

    private func windowDidHide() {
        windowVisible = false
        presenceTask?.cancel()
        presenceTask = nil
        idleTask?.cancel()
        idleTask = nil
        hideTask?.cancel()
        hideTask = Task {
            try? await Task.sleep(for: Timing.hideDebounce)
            guard !Task.isCancelled else { return }
            await request(.hide)
        }
    }

    private func startPresencePoll() {
        guard observesSystem, presenceTask == nil else { return }
        presenceTask = Task {
            while !Task.isCancelled {
                try? await Task.sleep(for: Timing.presencePoll)
                guard !Task.isCancelled else { return }
                await request(.presencePoll)
            }
        }
    }

    private func startStatusTick() {
        guard observesSystem, tickTask == nil else { return }
        tickTask = Task {
            while !Task.isCancelled {
                try? await Task.sleep(for: Timing.statusTick)
                guard !Task.isCancelled else { return }
                if status.isTimeSensitive { statusClock = now() }
            }
        }
    }

    /// A keystroke in the sticky or a Library file (never Scratch, §5.2).
    func noteEdit() {
        guard isActive else { return }
        if pendingSince == nil {
            let since = now()
            pendingSince = since
            if case .synced = status { status = .pending(since: since) }
            if case .synced = lastSettled { lastSettled = .pending(since: since) }
        }
        idleTask?.cancel()
        guard windowVisible else { return }
        idleTask = Task {
            try? await Task.sleep(for: Timing.editIdle)
            guard !Task.isCancelled else { return }
            await request(.editIdle)
        }
    }

    /// The quit departure (§9.2): best effort within the budget, then report
    /// whether anything is still only on this Mac. A run that didn't finish in
    /// time counts as unsent.
    func departBeforeQuit() async -> Bool {
        guard isActive, let folder else { return false }
        let runner = runner
        let once = ResumeOnce()
        return await withCheckedContinuation { (continuation: CheckedContinuation<Bool, Never>) in
            once.continuation = continuation
            Task {
                _ = await self.request(.quit)
                let unsent = await Self.offMain { GitSupport.hasLocalChanges(folder, runner: runner) }
                once.resume(unsent)
            }
            Task {
                // Covers a run already in flight that the quit had to wait behind.
                try? await Task.sleep(for: .seconds(Timing.quitBudget + 3))
                once.resume(true)
            }
        }
    }

    // MARK: Requests (§5, §6.6)

    /// The single entry point. Returns the run that served this request, or nil
    /// when it was skipped. Manual always runs, even with the toggle off.
    @discardableResult
    func request(_ trigger: Trigger) async -> GitSupport.SyncRun? {
        guard folder != nil else { return nil }
        if trigger != .manual {
            guard isActive else { return nil }
            if trigger == .summon, let lastFetchAt,
               now().timeIntervalSince(lastFetchAt) < Timing.summonStaleness {
                return nil
            }
        }
        if inFlight {
            runAgain = true
            queued.insert(trigger)
            return await withCheckedContinuation { waiters.append($0) }
        }
        return await drive([trigger])
    }

    private func drive(_ triggers: Set<Trigger>) async -> GitSupport.SyncRun? {
        inFlight = true
        let run = await perform(triggers)
        if runAgain {
            // Exactly one follow-up for everything that arrived meanwhile.
            runAgain = false
            let next = queued
            let waiting = waiters
            queued = []
            waiters = []
            Task {
                let followUp = await self.drive(next)
                for waiter in waiting { waiter.resume(returning: followUp) }
            }
        } else {
            inFlight = false
        }
        return run
    }

    private func perform(_ triggers: Set<Trigger>) async -> GitSupport.SyncRun? {
        guard let folder else { return nil }
        let runner = runner
        let device = device
        let manual = triggers.contains(.manual)
        let arrival = triggers.contains { $0.isArrival }
        let departure = triggers.contains { $0.isDeparture }

        var localOnly = false
        var allowRebase = true

        if !manual {
            guard isActive else { return nil }

            // No git, no repository, or no remote: automatic sync is inert (§6.6).
            if isEligible != true {
                let eligible = await Self.offMain { Self.isEligible(folder, runner: runner) }
                isEligible = eligible
                guard eligible else {
                    status = .off
                    return nil
                }
            }

            if !arrival {
                session?.flush()
                let hasChanges = await Self.offMain { GitSupport.hasLocalChanges(folder, runner: runner) }
                guard hasChanges else { return nil }
            }

            if offlineSince != nil, !triggers.contains(where: \.probesNetwork) {
                guard departure else { return nil }
                localOnly = true
            }

            if let pushFailedAt, now().timeIntervalSince(pushFailedAt) < Timing.pushFailedRetry {
                guard departure else { return nil }
                localOnly = true
            }

            if let pause {
                let current = await Self.offMain {
                    (GitSupport.revision("HEAD", in: folder, runner: runner),
                     GitSupport.revision("@{upstream}", in: folder, runner: runner))
                }
                allowRebase = current.0 != pause.head || current.1 != pause.upstream
            }
        }

        // Wake/launch with this Mac's own commits still unsent from before (§9.2.3).
        // The run's own notice, if any, replaces this one when it finishes.
        if !manual, let arrivedAt = arrivalTime(for: triggers) {
            let unpushed = await Self.offMain { GitSupport.unpushedCommits(folder, runner: runner) }
            if SyncTime.showsEarlierNotesNotice(ahead: unpushed?.count ?? 0,
                                                oldestUnpushed: unpushed?.oldest,
                                                arrivedAt: arrivedAt) {
                lastNotice = AutoSyncNotice(text: Self.earlierNotesNotice, seconds: 8)
            }
        }

        let previous = status
        if settings.syncAutomatically { status = .syncing }

        let session = session
        let context = GitSupport.SyncContext(
            flush: { [weak session] in session?.flush() },
            reconcile: { [weak session] in session?.document?.reconcileWithDisk() },
            deadline: deadline(for: triggers),
            allowRebase: allowRebase,
            localOnly: localOnly,
            runner: runner,
            now: now(),
            device: device
        )
        let run = await GitSupport.run(folder, context: context)

        let paused = run.outcome == .pullConflict
        let after = await Self.offMain {
            let upstream = GitSupport.revision("@{upstream}", in: folder, runner: runner)
            return AfterRun(hasLocalChanges: GitSupport.hasLocalChanges(folder, runner: runner),
                            hasUpstream: upstream != nil,
                            otherDevice: run.fetchSucceeded
                                ? GitSupport.otherDeviceLastCommit(folder, thisDevice: device, runner: runner).map { OtherDevice(name: $0.name, at: $0.at) }
                                : nil,
                            head: paused ? GitSupport.revision("HEAD", in: folder, runner: runner) : nil,
                            upstream: paused ? upstream : nil)
        }

        apply(run, after: after, previous: previous, manual: manual,
              localOnly: localOnly, attemptedRebase: allowRebase)
        return run
    }

    /// The wake or launch a run arrives from (§9.2.3); nil for other triggers.
    private func arrivalTime(for triggers: Set<Trigger>) -> Date? {
        if triggers.contains(.wake), let wokeAt { return wokeAt }
        if triggers.contains(.folderReady) { return launchedAt }
        return nil
    }

    private func deadline(for triggers: Set<Trigger>) -> Date? {
        guard !triggers.contains(.manual) else { return nil }
        if triggers.contains(.sleep) || triggers.contains(.quit) {
            return Date().addingTimeInterval(Timing.sleepBudget)
        }
        if triggers.contains(.newDay) {
            return Date().addingTimeInterval(Timing.newDayBudget)
        }
        return nil
    }

    // MARK: Results (§8.1, §8.3)

    private func apply(_ run: GitSupport.SyncRun, after: AfterRun, previous: SyncStatus,
                       manual: Bool, localOnly: Bool, attemptedRebase: Bool) {
        let time = now()
        lastRunStderr = run.stderr
        hasUpstream = after.hasUpstream
        if run.fetchSucceeded {
            lastFetchAt = time
            offlineSince = nil
            if let other = after.otherDevice { otherDeviceLast = (other.name, other.at) }
        }
        if run.pushSucceeded { pushFailedAt = nil }
        pendingSince = after.hasLocalChanges ? (pendingSince ?? time) : nil

        var notice: AutoSyncNotice?
        var next: SyncStatus

        switch run.outcome {
        case .gitUnavailable, .notARepository, .noRemote:
            isEligible = false
            next = .off

        case .busy:
            next = previous

        case .stuck:
            next = .failing(.lock)

        case .offline:
            if localOnly, offlineSince == nil {
                // Local-only because of push back-off, not the network.
                next = .failing(.push)
            } else {
                let since = offlineSince ?? time
                offlineSince = since
                next = .offline(since: since, pendingSince: pendingSince)
            }

        case .pushFailed:
            pushFailedAt = time
            next = .failing(.push)

        case .pullConflict:
            if pause == nil, !manual {
                notice = AutoSyncNotice(text: GitSupport.SyncOutcome.pullConflict.notice(editorName: editorName()) ?? "",
                                        seconds: 15)
            }
            // Our own commits move HEAD every paused run; only an outside change
            // (or new upstream commits since the last rebase attempt) retries.
            let upstream = attemptedRebase || pause == nil ? after.upstream : pause?.upstream
            pause = (after.head, upstream)
            next = .paused

        case .synced, .nothingToSync:
            pause = nil
            pushFailedAt = nil
            next = pendingSince.map { .pending(since: $0) } ?? .synced(at: time)
        }

        if !manual, notice == nil {
            if !run.mergedDailyPaths.isEmpty {
                notice = AutoSyncNotice(text: Self.mergedDailyNotice, seconds: 6)
            } else if run.didBringIn {
                notice = AutoSyncNotice(text: Self.updatedNotice(from: run.incomingDevice), seconds: 4)
            }
        }

        status = isActive ? next : .off
        if let notice { lastNotice = notice }
    }

    // MARK: Off-main helpers

    private struct OtherDevice: Sendable {
        let name: String
        let at: Date
    }

    private struct AfterRun: Sendable {
        let hasLocalChanges: Bool
        let hasUpstream: Bool
        let otherDevice: OtherDevice?
        let head: String?
        let upstream: String?
    }

    nonisolated private static func isEligible(_ folder: PeteKMFolder, runner: GitRunner) -> Bool {
        guard runner.run(["--version"], in: folder.root, timeout: GitSupport.Timeouts.local).succeeded,
              GitSupport.isRepository(folder) else { return false }
        let remotes = runner.run(["remote"], in: folder.root, timeout: GitSupport.Timeouts.local)
        return remotes.succeeded && !remotes.output.isEmpty
    }

    nonisolated private static func offMain<T: Sendable>(_ work: @escaping @Sendable () -> T) async -> T {
        await Task.detached(priority: .utility) { work() }.value
    }
}

/// Resumes a continuation at most once, whichever racer gets there first.
@MainActor
private final class ResumeOnce {
    var continuation: CheckedContinuation<Bool, Never>?

    func resume(_ value: Bool) {
        continuation?.resume(returning: value)
        continuation = nil
    }
}
