//
//  GitSupport.swift
//  PeteKM
//
//  Git is optional and never required for capture (spec §6.3, §17.4).
//  Everything here degrades quietly: a Git failure must never block opening or
//  saving a Daily Sticky.
//
//  Sync v2 (context/sync-v2/spec.md): every git invocation is hardened so it can
//  run unattended — no credential prompts, a timeout, stderr captured (§6.7) —
//  and manual Sync and every automatic trigger share one run sequence (§6.1).
//

import Foundation

/// One git invocation's result (sync v2 §6.7).
nonisolated struct GitResult: Sendable, Equatable {
    var status: Int32
    var stdout: String
    var stderr: String
    var timedOut: Bool

    var succeeded: Bool { status == 0 && !timedOut }

    /// Trimmed stdout, the shape every caller of the v1 `run` expected.
    var output: String { stdout.trimmingCharacters(in: .whitespacesAndNewlines) }

    static func failed(_ message: String = "", timedOut: Bool = false) -> GitResult {
        GitResult(status: -1, stdout: "", stderr: message, timedOut: timedOut)
    }
}

/// The seam between the sync sequence and real processes, so tests can drive
/// the sequence with a fake (sync v2 §11).
nonisolated protocol GitRunner: Sendable {
    func run(_ arguments: [String], in directory: URL, timeout: Duration) -> GitResult
}

nonisolated struct ProcessGitRunner: GitRunner {
    func run(_ arguments: [String], in directory: URL, timeout: Duration) -> GitResult {
        GitSupport.runDetailed(arguments, in: directory, timeout: timeout)
    }
}

nonisolated enum GitSupport {

    static func isRepository(_ folder: PeteKMFolder) -> Bool {
        FileWriting.isDirectory(folder.gitDirectory)
    }

    /// `git init` in the PeteKM folder. Returns false on any failure; the caller
    /// shows a plain notice and carries on.
    @discardableResult
    static func initializeRepository(at folder: PeteKMFolder) -> Bool {
        run(["init"], in: folder.root) != nil
    }

    /// Whether a usable `git` exists at all.
    static var isGitAvailable: Bool {
        run(["--version"], in: URL(filePath: NSHomeDirectory(), directoryHint: .isDirectory)) != nil
    }

    /// Name of the push remote, or nil when none is configured.
    static func remoteName(of folder: PeteKMFolder) -> String? {
        guard let output = run(["remote"], in: folder.root) else { return nil }
        return output.split(separator: "\n").first.map(String.init)
    }

    /// Add a push remote (sync spec §7). No validation, no auth, no repo creation.
    @discardableResult
    static func setRemote(_ url: String, in folder: PeteKMFolder) -> Bool {
        run(["remote", "add", "origin", url], in: folder.root) != nil
    }

    // MARK: - Sync (sync spec §4, §5)

    /// What a sync attempt did. Every case is survivable: capture never depends
    /// on any of this (§17.4, sync spec §6.6).
    enum SyncOutcome: Equatable, Sendable {
        case gitUnavailable
        case notARepository
        case offline
        case noRemote
        case pullConflict
        case pushFailed
        case nothingToSync
        case synced
        /// Another Git tool is mid-operation in the folder (sync v2 §6.4). Internal:
        /// skipped silently and retried on the next trigger.
        case busy
        /// `busy` for longer than `Timeouts.staleLock`. Internal: surfaces through
        /// the status line, never as a notice.
        case stuck

        /// Terse, no-apology notice (DESIGN §32). `editorName` is named, never
        /// hard-coded — only `pullConflict` uses it (sync spec §5.4). Nil for the
        /// internal outcomes, which are never shown as a notice (sync v2 §10.2).
        func notice(editorName: String) -> String? {
            switch self {
            case .gitUnavailable: return "Git isn't available."
            case .notARepository: return "This PeteKM folder isn't a Git repository."
            case .offline: return "Saved locally. Couldn't reach GitHub."
            case .noRemote: return "Saved locally. No GitHub remote is set."
            case .pullConflict:
                return "Sync paused — the same note changed on two devices. Nothing was lost or changed. "
                     + "Ask PeteKM (in a terminal) to help sort it out, or open the folder in \(editorName) yourself."
            case .pushFailed: return "Saved and up to date locally, but couldn't publish to GitHub. Try Sync again."
            case .nothingToSync: return "Already up to date."
            case .synced: return "Synced."
            case .busy, .stuck: return nil
            }
        }

        /// What a manual Sync shows (sync v2 §5.5). A click must always answer,
        /// so the internal outcomes get a line here, and only here.
        func manualNotice(editorName: String) -> String {
            switch self {
            case .busy: return GitSupport.busyLine
            case .stuck: return GitSupport.stuckLine
            default: return notice(editorName: editorName) ?? GitSupport.busyLine
            }
        }
    }

    /// Sync v2 §5.5: manual Sync while another tool briefly holds the folder.
    static let busyLine = "Another Git tool is using this folder. Try Sync again in a moment."

    /// Sync v2 §8.4, failing (lock).
    static let stuckLine = "Sync is stuck — another Git tool is mid-operation in this folder."

    /// Per-invocation budgets (sync v2 §6.7, §10.3).
    enum Timeouts {
        static let network: Duration = .seconds(30)
        static let local: Duration = .seconds(15)
        /// The least a local step gets under a sleep/quit deadline.
        static let localFloor: Duration = .seconds(1)
        /// A guard older than this is reported as `.stuck` (§6.4).
        static let staleLock: TimeInterval = 10 * 60

        /// The v1-style `run` picks a budget from the subcommand.
        static func `for`(_ arguments: [String]) -> Duration {
            ["fetch", "push", "pull", "clone", "ls-remote"].contains(arguments.first ?? "") ? network : local
        }
    }

    /// `PeteKM backup 2026-08-19 20:45` (§17.2).
    static func commitMessage(for date: Date, calendar: Calendar = .current, locale: Locale = Locale(identifier: "en_US_POSIX")) -> String {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = locale
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        return "PeteKM backup \(formatter.string(from: date))"
    }

    /// How far the local branch has diverged from `@{upstream}`, or nil when
    /// there is no upstream to compare against (sync spec §5.1 step 4).
    static func aheadBehind(_ folder: PeteKMFolder) -> (ahead: Int, behind: Int)? {
        aheadBehind(folder, runner: ProcessGitRunner())
    }

    static func aheadBehind(_ folder: PeteKMFolder, runner: GitRunner, timeout: Duration = Timeouts.local) -> (ahead: Int, behind: Int)? {
        let result = runner.run(["rev-list", "--left-right", "--count", "HEAD...@{upstream}"], in: folder.root, timeout: timeout)
        guard result.succeeded else { return nil }
        let parts = result.output.split(whereSeparator: { $0 == "\t" || $0 == " " })
        guard parts.count == 2, let ahead = Int(parts[0]), let behind = Int(parts[1]) else { return nil }
        return (ahead, behind)
    }

    // MARK: - Guards (sync v2 §6.4)

    /// The departure precondition (§5.2): a dirty tree, or commits not yet upstream.
    static func hasLocalChanges(_ folder: PeteKMFolder, runner: GitRunner) -> Bool {
        let status = runner.run(["status", "--porcelain"], in: folder.root, timeout: Timeouts.local)
        if status.succeeded, !status.output.isEmpty { return true }
        return (aheadBehind(folder, runner: runner)?.ahead ?? 0) > 0
    }

    static func revision(_ name: String, in folder: PeteKMFolder, runner: GitRunner) -> String? {
        let result = runner.run(["rev-parse", name], in: folder.root, timeout: Timeouts.local)
        return result.succeeded && !result.output.isEmpty ? result.output : nil
    }

    enum BusyReason: Equatable, Sendable {
        case indexLock
        case rebase
        case merge
        case cherryPick
    }

    /// Written immediately before PeteKM's own rebase and removed immediately
    /// after, so a rebase killed by sleep or a crash is recognisably ours.
    static let rebaseMarkerName = "petekm-rebase"

    static func rebaseMarker(_ folder: PeteKMFolder) -> URL {
        folder.gitDirectory.appending(path: rebaseMarkerName)
    }

    /// Whether another Git operation holds the repository, and since when (the
    /// oldest mtime among the markers found). Never deletes anything.
    static func busyReason(_ folder: PeteKMFolder) -> (reason: BusyReason, since: Date)? {
        let git = folder.gitDirectory
        let checks: [(String, BusyReason)] = [
            ("index.lock", .indexLock),
            ("rebase-merge", .rebase),
            ("rebase-apply", .rebase),
            ("MERGE_HEAD", .merge),
            ("CHERRY_PICK_HEAD", .cherryPick),
        ]
        var found: (reason: BusyReason, since: Date)?
        for (name, reason) in checks {
            let path = git.appending(path: name).path(percentEncoded: false)
            guard let attributes = try? FileManager.default.attributesOfItem(atPath: path) else { continue }
            let modified = attributes[.modificationDate] as? Date ?? Date()
            if found == nil || modified < found!.since {
                found = (reason, modified)
            }
        }
        return found
    }

    /// The step 0 / step 6b guard. A rebase PeteKM itself left behind is aborted
    /// and the run continues; anything else is `.busy`, or `.stuck` once stale.
    private static func guardOutcome(_ folder: PeteKMFolder, now: Date, abortOwnRebase: () -> Bool) -> SyncOutcome? {
        guard var busy = busyReason(folder) else { return nil }
        let marker = rebaseMarker(folder)
        if busy.reason == .rebase, FileManager.default.fileExists(atPath: marker.path(percentEncoded: false)) {
            if abortOwnRebase() {
                try? FileManager.default.removeItem(at: marker)
            }
            guard let still = busyReason(folder) else { return nil }
            busy = still
        }
        return now.timeIntervalSince(busy.since) > Timeouts.staleLock ? .stuck : .busy
    }

    // MARK: - Device trailer (sync v2 §6.3, §9.3)

    static let deviceTrailerKey = "PeteKM-Device"

    /// The Sharing pane's Computer Name, read once per process.
    static let deviceName: String = {
        let name = Host.current().localizedName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return name.isEmpty ? "This Mac" : name
    }()

    /// Commit with the device trailer; retry once without it, so a commit is
    /// never lost to a formatting feature.
    static func commit(_ subject: String, device: String, in folder: PeteKMFolder, runner: GitRunner, timeout: Duration) -> GitResult {
        let withTrailer = runner.run(["commit", "-m", subject, "--trailer", "\(deviceTrailerKey): \(device)"],
                                     in: folder.root, timeout: timeout)
        if withTrailer.succeeded { return withTrailer }
        return runner.run(["commit", "-m", subject], in: folder.root, timeout: timeout)
    }

    private static let trailerFormat = "%(trailers:key=\(deviceTrailerKey),valueonly,separator=)"

    /// The newest upstream commit made by a different, named Mac (§9.3).
    /// Trailer-less commits (agent-made, pre-v2) are skipped.
    static func otherDeviceLastCommit(_ folder: PeteKMFolder, thisDevice: String,
                                      runner: GitRunner = ProcessGitRunner()) -> (name: String, at: Date)? {
        let result = runner.run(["log", "-n", "100", "@{upstream}", "--format=%ct%x09\(trailerFormat)"],
                                in: folder.root, timeout: Timeouts.local)
        guard result.succeeded else { return nil }
        for line in result.stdout.split(separator: "\n") {
            let parts = line.split(separator: "\t", maxSplits: 1)
            guard parts.count == 2, let seconds = TimeInterval(parts[0]) else { continue }
            let device = parts[1].trimmingCharacters(in: .whitespaces)
            guard !device.isEmpty, device != thisDevice else { continue }
            return (device, Date(timeIntervalSince1970: seconds))
        }
        return nil
    }

    /// The device trailer of the newest commit about to come in, or nil when it
    /// has none (§8.3). Call before the rebase.
    static func incomingDeviceName(_ folder: PeteKMFolder, runner: GitRunner = ProcessGitRunner()) -> String? {
        let result = runner.run(["log", "-n", "1", "--format=\(trailerFormat)", "HEAD..@{upstream}"],
                                in: folder.root, timeout: Timeouts.local)
        guard result.succeeded, !result.output.isEmpty else { return nil }
        return result.output
    }

    // MARK: - Merged-daily detector (sync v2 §7.3)

    /// `daily/*.md` paths changed both locally and upstream since the merge base.
    /// Call before the rebase. Matches the `.gitattributes` pattern: direct
    /// children of `daily/` only.
    static func dailyPathsChangedOnBothSides(_ folder: PeteKMFolder, runner: GitRunner = ProcessGitRunner()) -> [String] {
        let base = runner.run(["merge-base", "HEAD", "@{upstream}"], in: folder.root, timeout: Timeouts.local)
        guard base.succeeded, !base.output.isEmpty else { return [] }

        func changed(_ tip: String) -> Set<String>? {
            let diff = runner.run(["-c", "core.quotePath=false", "diff", "--name-only", base.output, tip],
                                  in: folder.root, timeout: Timeouts.local)
            guard diff.succeeded else { return nil }
            return Set(diff.output.split(separator: "\n").map(String.init))
        }
        guard let local = changed("HEAD"), let upstream = changed("@{upstream}") else { return [] }
        return local.intersection(upstream).filter(isDailyStickyPath).sorted()
    }

    static func isDailyStickyPath(_ path: String) -> Bool {
        guard path.hasPrefix("daily/"), path.hasSuffix(".md") else { return false }
        return !path.dropFirst("daily/".count).contains("/")
    }

    // MARK: - The run (sync v2 §6.1)

    /// What the caller supplies. Flush and reconcile are the only steps that hop
    /// to the main actor (§6.7).
    struct SyncContext: Sendable {
        var flush: @MainActor @Sendable () -> Void = {}
        var reconcile: @MainActor @Sendable () -> Void = {}
        /// The sleep/quit budget: every invocation's timeout is capped by it.
        var deadline: Date?
        /// False while paused on a conflict (§6.6): fetch still runs, no rebase.
        var allowRebase = true
        /// Offline back-off (§6.6): commit locally, then stop before the network.
        var localOnly = false
        var runner: GitRunner = ProcessGitRunner()
        var now: Date = Date()
        var calendar: Calendar = .current
        var device: String = GitSupport.deviceName

        init(flush: @escaping @MainActor @Sendable () -> Void = {},
             reconcile: @escaping @MainActor @Sendable () -> Void = {},
             deadline: Date? = nil,
             allowRebase: Bool = true,
             localOnly: Bool = false,
             runner: GitRunner = ProcessGitRunner(),
             now: Date = Date(),
             calendar: Calendar = .current,
             device: String = GitSupport.deviceName) {
            self.flush = flush
            self.reconcile = reconcile
            self.deadline = deadline
            self.allowRebase = allowRebase
            self.localOnly = localOnly
            self.runner = runner
            self.now = now
            self.calendar = calendar
            self.device = device
        }
    }

    /// Everything one run learned. `stderr` is for the "Details…" affordance
    /// (§8.2) and lives in memory only.
    struct SyncRun: Equatable, Sendable {
        var outcome: SyncOutcome
        var didCommit = false
        /// Behind > 0 and the rebase succeeded.
        var didBringIn = false
        var incomingDevice: String?
        var mergedDailyPaths: [String] = []
        var stderr = ""
        var fetchSucceeded = false
        var pushSucceeded = false
        var ahead: Int?
        var behind: Int?
    }

    /// v1-compatible wrapper: the v2 sequence with no flush or reconcile.
    static func sync(_ folder: PeteKMFolder, now: Date = Date(), calendar: Calendar = .current) async -> SyncOutcome {
        await run(folder, context: SyncContext(now: now, calendar: calendar)).outcome
    }

    /// Commit, fetch, rebase onto upstream when behind, push when ahead (§6.1).
    /// Never force-pushes, never resolves a conflict: a conflicting rebase is
    /// aborted and reported. Blocking git work — call it off the main actor.
    @concurrent
    static func run(_ folder: PeteKMFolder, context: SyncContext) async -> SyncRun {
        var result = SyncRun(outcome: .nothingToSync)
        let git = RunInvoker(base: context.runner, deadline: context.deadline)

        func finish(_ outcome: SyncOutcome) -> SyncRun {
            result.outcome = outcome
            result.stderr = git.stderr
            return result
        }

        func recordCounts() {
            if let counts = aheadBehind(folder, runner: git) {
                result.ahead = counts.ahead
                result.behind = counts.behind
            }
        }

        /// Step 2 / 6a. Nil when the commit itself failed.
        func commitIfDirty() -> Bool? {
            git.invoke(["add", "-A"], in: folder.root)
            let status = git.invoke(["status", "--porcelain"], in: folder.root)
            guard status.succeeded, !status.output.isEmpty else { return false }
            let subject = commitMessage(for: context.now, calendar: context.calendar)
            return commit(subject, device: context.device, in: folder, runner: git, timeout: Timeouts.local).succeeded ? true : nil
        }

        /// Cleanup that must happen even past the deadline.
        func abortOwnRebase() -> Bool {
            git.invoke(["rebase", "--abort"], in: folder.root, ignoreDeadline: true).succeeded
        }

        // 0. Availability and guard.
        guard git.invoke(["--version"], in: folder.root).succeeded else { return finish(.gitUnavailable) }
        guard isRepository(folder) else { return finish(.notARepository) }
        if let blocked = guardOutcome(folder, now: context.now, abortOwnRebase: abortOwnRebase) {
            return finish(blocked)
        }

        // 1–2. Flush and commit first, before any network call.
        await context.flush()
        guard let committed = commitIfDirty() else {
            // Deliberate mapping, not an oversight: v1 §5.3 fixes the notices with
            // no `commitFailed`. Stop here rather than take an uncommitted tree
            // into a rebase; "Try Sync again." is the only notice that isn't
            // actively false for a failed commit.
            return finish(.pushFailed)
        }
        result.didCommit = committed

        // 3–4. Network.
        let remotes = git.invoke(["remote"], in: folder.root)
        guard let remote = remotes.output.split(separator: "\n").first.map(String.init) else {
            return finish(.noRemote)
        }
        guard !context.localOnly else { return finish(.offline) }
        guard git.invoke(["fetch"], in: folder.root, timeout: Timeouts.network).succeeded else {
            return finish(.offline)
        }
        result.fetchSucceeded = true

        // 5. Divergence. Nil means no upstream yet.
        var counts = aheadBehind(folder, runner: git)

        // 6. Bring changes in, locally and fast.
        if let divergence = counts, divergence.behind > 0 {
            guard context.allowRebase else {
                // Paused (§6.6): a push would be rejected anyway.
                recordCounts()
                return finish(.pullConflict)
            }

            // a. Catch typing that happened during the fetch.
            await context.flush()
            guard let again = commitIfDirty() else { return finish(.pushFailed) }
            result.didCommit = result.didCommit || again

            // b. Guard again, learn what's coming, then rebase under our marker.
            if let blocked = guardOutcome(folder, now: context.now, abortOwnRebase: abortOwnRebase) {
                return finish(blocked)
            }
            let merged = dailyPathsChangedOnBothSides(folder, runner: git)
            let incoming = incomingDeviceName(folder, runner: git)

            let marker = rebaseMarker(folder)
            FileManager.default.createFile(atPath: marker.path(percentEncoded: false), contents: nil)
            let rebased = git.invoke(["rebase", "--autostash", "@{upstream}"], in: folder.root)
            if !rebased.succeeded {
                // Leave the marker if the abort itself failed: the next run's
                // guard recognises the rebase as ours and retries the abort.
                if abortOwnRebase() {
                    try? FileManager.default.removeItem(at: marker)
                }
                recordCounts()
                return finish(.pullConflict)
            }
            try? FileManager.default.removeItem(at: marker)
            result.didBringIn = true
            result.mergedDailyPaths = merged
            result.incomingDevice = incoming

            // c. Show the new disk state at once.
            await context.reconcile()
            counts = aheadBehind(folder, runner: git)
        }

        // 7. Send changes out, only when there is something to send.
        var push: [String]?
        if let divergence = counts {
            if divergence.ahead > 0 { push = ["push"] }
        } else {
            // No upstream yet on a fresh branch — set it once, as v1 did.
            let branch = git.invoke(["rev-parse", "--abbrev-ref", "HEAD"], in: folder.root)
            if branch.succeeded, !branch.output.isEmpty, branch.output != "HEAD" {
                push = ["push", "--set-upstream", remote, branch.output]
            }
        }
        if let push {
            guard git.invoke(push, in: folder.root, timeout: Timeouts.network).succeeded else {
                recordCounts()
                return finish(.pushFailed)
            }
            result.pushSucceeded = true
        }

        // 8.
        recordCounts()
        let changed = result.didCommit || result.didBringIn || result.pushSucceeded
        return finish(changed ? .synced : .nothingToSync)
    }

    /// One run's view of git: caps every invocation by the run's deadline and
    /// keeps stderr for "Details…". Helpers take it as their `GitRunner`.
    private final class RunInvoker: GitRunner, @unchecked Sendable {
        let base: GitRunner
        let deadline: Date?
        private(set) var stderr = ""

        init(base: GitRunner, deadline: Date?) {
            self.base = base
            self.deadline = deadline
        }

        func run(_ arguments: [String], in directory: URL, timeout: Duration) -> GitResult {
            invoke(arguments, in: directory, timeout: timeout)
        }

        @discardableResult
        func invoke(_ arguments: [String], in directory: URL, timeout: Duration = Timeouts.local,
                    ignoreDeadline: Bool = false) -> GitResult {
            var budget: Duration? = timeout
            if let deadline, !ignoreDeadline {
                // Local steps take milliseconds and always get a short floor, so
                // the local commit completes even past the deadline (§5.3). A
                // network step past the deadline is not attempted at all.
                let isNetwork = timeout >= Timeouts.network
                let remaining = Duration.milliseconds(Int(deadline.timeIntervalSinceNow * 1000))
                if isNetwork {
                    budget = remaining > .zero ? min(timeout, remaining) : nil
                } else {
                    budget = min(timeout, max(remaining, Timeouts.localFloor))
                }
            }
            let outcome = budget.map { base.run(arguments, in: directory, timeout: $0) }
                ?? .failed("Out of time.", timedOut: true)

            let message = outcome.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            if !message.isEmpty || outcome.timedOut {
                stderr += "$ git \(arguments.joined(separator: " "))\n"
                stderr += outcome.timedOut ? "(timed out)\n" : "\(message)\n"
            }
            return outcome
        }
    }

    // MARK: - Process

    /// Every invocation's environment: fail instead of prompting for a
    /// password, passphrase, or host key, but keep HOME and PATH so credential
    /// helpers and the SSH agent still work (§6.7).
    static let environment: [String: String] = {
        var environment = ProcessInfo.processInfo.environment
        environment["GIT_TERMINAL_PROMPT"] = "0"
        environment["GIT_SSH_COMMAND"] = "ssh -o BatchMode=yes -o ConnectTimeout=10"
        return environment
    }()

    /// Run a git subcommand, returning trimmed stdout, or nil if git is missing,
    /// exited non-zero, or timed out.
    @discardableResult
    static func run(_ arguments: [String], in directory: URL) -> String? {
        let result = runDetailed(arguments, in: directory, timeout: Timeouts.for(arguments))
        return result.succeeded ? result.output : nil
    }

    /// Run a git subcommand with the hardened environment and a timeout. Stdout
    /// and stderr drain concurrently so a full pipe can't stall the process.
    /// Blocking — call it off the main actor.
    static func runDetailed(_ arguments: [String], in directory: URL, timeout: Duration) -> GitResult {
        let process = Process()
        process.executableURL = URL(filePath: "/usr/bin/env")
        process.arguments = ["git"] + arguments
        process.currentDirectoryURL = directory
        process.environment = environment
        process.standardInput = FileHandle.nullDevice

        let stdout = PipeDrain()
        let stderr = PipeDrain()
        process.standardOutput = stdout.pipe
        process.standardError = stderr.pipe

        do {
            try process.run()
        } catch {
            return .failed(error.localizedDescription)
        }

        let timedOut = Flag()
        let watchdog = DispatchWorkItem {
            guard process.isRunning else { return }
            timedOut.set()
            process.terminate()
            DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 1) {
                if process.isRunning { kill(process.processIdentifier, SIGKILL) }
            }
        }
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + timeout.seconds, execute: watchdog)

        process.waitUntilExit()
        watchdog.cancel()

        // A helper git spawned (ssh, git-remote-https) may briefly outlive git
        // and hold the pipes; don't wait on it forever.
        let output = stdout.finish(waitingUpTo: 1)
        let errors = stderr.finish(waitingUpTo: 1)

        return GitResult(status: process.terminationStatus,
                         stdout: String(decoding: output, as: UTF8.self),
                         stderr: String(decoding: errors, as: UTF8.self),
                         timedOut: timedOut.isSet)
    }
}

// MARK: - Process plumbing

/// Accumulates one pipe's output on a background handler until EOF.
private nonisolated final class PipeDrain: @unchecked Sendable {
    let pipe = Pipe()
    private let lock = NSLock()
    private var data = Data()
    private let done = DispatchSemaphore(value: 0)

    init() {
        pipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let chunk = handle.availableData
            guard let self else { return }
            if chunk.isEmpty {
                handle.readabilityHandler = nil
                self.done.signal()
            } else {
                self.lock.lock()
                self.data.append(chunk)
                self.lock.unlock()
            }
        }
    }

    func finish(waitingUpTo seconds: Double) -> Data {
        _ = done.wait(timeout: .now() + seconds)
        pipe.fileHandleForReading.readabilityHandler = nil
        lock.lock()
        defer { lock.unlock() }
        return data
    }
}

private nonisolated final class Flag: @unchecked Sendable {
    private let lock = NSLock()
    private var value = false

    func set() {
        lock.lock()
        value = true
        lock.unlock()
    }

    var isSet: Bool {
        lock.lock()
        defer { lock.unlock() }
        return value
    }
}

private nonisolated extension Duration {
    var seconds: Double {
        Double(components.seconds) + Double(components.attoseconds) / 1e18
    }
}
