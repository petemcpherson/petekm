import Foundation
import Testing
@testable import PeteKM

// Sync v2 engine (context/sync-v2/spec.md §6, §11): real temporary repositories,
// a bare "GitHub" plus two clones standing in for Mac A and Mac B. `file://`
// remotes only — no network.

// MARK: - Fixture

/// `origin.git` (bare) plus clones `a` and `b`, each with a local identity and
/// an initial pushed commit. Removed from disk on deinit.
final class GitFixture {
    let base: URL
    let origin: URL
    let a: PeteKMFolder
    let b: PeteKMFolder

    init?() throws {
        guard GitSupport.isGitAvailable else { return nil }
        base = URL(filePath: NSTemporaryDirectory(), directoryHint: .isDirectory)
            .appending(path: "petekm-gitsync-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)

        origin = base.appending(path: "origin.git", directoryHint: .isDirectory)
        GitSupport.run(["init", "--bare", "--initial-branch", "main", origin.path(percentEncoded: false)], in: base)

        let base = base
        let origin = origin
        func clone(_ name: String) -> PeteKMFolder {
            GitSupport.run(["clone", origin.path(percentEncoded: false), name], in: base)
            let folder = PeteKMFolder(root: base.appending(path: name, directoryHint: .isDirectory))
            GitSupport.run(["config", "user.email", "tests@petekm.local"], in: folder.root)
            GitSupport.run(["config", "user.name", "PeteKM Tests"], in: folder.root)
            return folder
        }

        a = clone("a")
        GitSupport.run(["checkout", "-B", "main"], in: a.root)
        try Self.write("# PeteKM\n", "README.md", in: a)
        GitSupport.run(["add", "-A"], in: a.root)
        GitSupport.run(["commit", "-m", "seed"], in: a.root)
        GitSupport.run(["push", "--set-upstream", "origin", "main"], in: a.root)
        b = clone("b")
    }

    deinit {
        try? FileManager.default.removeItem(at: base)
    }

    static func write(_ text: String, _ path: String, in folder: PeteKMFolder) throws {
        let url = folder.root.appending(path: path)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(text.utf8).write(to: url, options: .atomic)
    }

    func write(_ text: String, _ path: String, in folder: PeteKMFolder) throws {
        try Self.write(text, path, in: folder)
    }

    func read(_ path: String, in folder: PeteKMFolder) throws -> Data {
        try Data(contentsOf: folder.root.appending(path: path))
    }

    @discardableResult
    func git(_ arguments: [String], in folder: PeteKMFolder) -> String? {
        GitSupport.run(arguments, in: folder.root)
    }

    var originCommitCount: Int {
        Int(GitSupport.run(["rev-list", "--count", "main"], in: origin) ?? "") ?? -1
    }

    func head(_ folder: PeteKMFolder) -> String? {
        git(["rev-parse", "HEAD"], in: folder)
    }

    func exists(_ gitPath: String, in folder: PeteKMFolder) -> Bool {
        FileManager.default.fileExists(atPath: folder.gitDirectory.appending(path: gitPath).path(percentEncoded: false))
    }

    /// Ships `.gitattributes` from A and brings it into B, the way a v2 folder looks
    /// once both Macs have synced once.
    func shareDailyUnionMerge() async {
        FolderInitializer.ensureDailyUnionMerge(a)
        _ = await run(a)
        _ = await run(b)
    }

    func run(_ folder: PeteKMFolder, device: String = "Test Mac",
             flush: @escaping @MainActor @Sendable () -> Void = {},
             allowRebase: Bool = true) async -> GitSupport.SyncRun {
        await GitSupport.run(folder, context: GitSupport.SyncContext(flush: flush, allowRebase: allowRebase, device: device))
    }
}

/// Counts flushes on the main actor, the way `DailySession.flush` runs.
@MainActor
final class FlushProbe {
    var calls = 0
}

/// Answers git with canned results, recording every invocation.
final class FakeGitRunner: GitRunner, @unchecked Sendable {
    private let lock = NSLock()
    private var _calls: [[String]] = []
    let respond: ([String]) -> GitResult

    init(respond: @escaping ([String]) -> GitResult) {
        self.respond = respond
    }

    var calls: [[String]] {
        lock.lock()
        defer { lock.unlock() }
        return _calls
    }

    func run(_ arguments: [String], in directory: URL, timeout: Duration) -> GitResult {
        lock.lock()
        _calls.append(arguments)
        lock.unlock()
        return respond(arguments)
    }
}

private let ok = GitResult(status: 0, stdout: "", stderr: "", timedOut: false)

private func okWith(_ stdout: String) -> GitResult {
    GitResult(status: 0, stdout: stdout, stderr: "", timedOut: false)
}

// MARK: - Sequence (§6.1)

@Test func cleanTreeIsNothingToSync() async throws {
    guard let fixture = try GitFixture() else { return }
    let run = await fixture.run(fixture.a)
    #expect(run.outcome == .nothingToSync)
    #expect(!run.didCommit)
    #expect(!run.pushSucceeded)
    #expect(run.fetchSucceeded)
}

@Test func localEditIsCommittedAndPushed() async throws {
    guard let fixture = try GitFixture() else { return }
    try fixture.write("# Note\n", "library/note.md", in: fixture.a)

    let run = await fixture.run(fixture.a)
    #expect(run.outcome == .synced)
    #expect(run.didCommit)
    #expect(run.pushSucceeded)
    #expect(!run.didBringIn)
    #expect(fixture.originCommitCount == 2)
    #expect(run.ahead == 0 && run.behind == 0)
}

@Test func behindOnlyRebasesWithoutPushing() async throws {
    guard let fixture = try GitFixture() else { return }
    try fixture.write("# From A\n", "library/a.md", in: fixture.a)
    #expect(await fixture.run(fixture.a).outcome == .synced)
    let before = fixture.originCommitCount

    let run = await fixture.run(fixture.b)
    #expect(run.outcome == .synced)
    #expect(run.didBringIn)
    #expect(!run.didCommit)
    #expect(!run.pushSucceeded)
    #expect(fixture.originCommitCount == before)
    #expect(try fixture.read("library/a.md", in: fixture.b) == Data("# From A\n".utf8))
}

@Test func divergedNonOverlappingRebasesThenPushes() async throws {
    guard let fixture = try GitFixture() else { return }
    try fixture.write("# From A\n", "library/a.md", in: fixture.a)
    #expect(await fixture.run(fixture.a).outcome == .synced)
    try fixture.write("# From B\n", "library/b.md", in: fixture.b)

    let run = await fixture.run(fixture.b)
    #expect(run.outcome == .synced)
    #expect(run.didCommit)
    #expect(run.didBringIn)
    #expect(run.pushSucceeded)
    #expect(fixture.originCommitCount == 3)
    // Linear history: a rebase, never a merge commit.
    #expect(fixture.git(["rev-list", "--merges", "--count", "HEAD"], in: fixture.b) == "0")
}

/// Step 6a: typing that lands during the fetch is committed before the rebase.
@Test @MainActor func secondFlushIsCommittedBeforeTheRebase() async throws {
    guard let fixture = try GitFixture() else { return }
    try fixture.write("# From A\n", "library/a.md", in: fixture.a)
    #expect(await fixture.run(fixture.a).outcome == .synced)

    let probe = FlushProbe()
    let b = fixture.b
    let run = await fixture.run(b, flush: {
        probe.calls += 1
        if probe.calls == 2 {
            try? GitFixture.write("typed during fetch\n", "library/late.md", in: b)
        }
    })

    #expect(probe.calls == 2)
    #expect(run.outcome == .synced)
    #expect(fixture.git(["status", "--porcelain"], in: b) == "")
    #expect(fixture.git(["log", "--name-only", "--format=", "origin/main"], in: b)?.contains("library/late.md") == true)
}

/// The important one: the same Library line on two Macs leaves the tree
/// byte-identical, no rebase in progress, and no marker (§6.4, §7.4).
@Test func libraryConflictPausesAndRestores() async throws {
    guard let fixture = try GitFixture() else { return }
    try fixture.write("shared\n", "library/note.md", in: fixture.a)
    #expect(await fixture.run(fixture.a).outcome == .synced)
    #expect(await fixture.run(fixture.b).outcome == .synced)

    try fixture.write("edited on A\n", "library/note.md", in: fixture.a)
    #expect(await fixture.run(fixture.a).outcome == .synced)

    try fixture.write("edited on B\n", "library/note.md", in: fixture.b)
    let before = try fixture.read("library/note.md", in: fixture.b)

    let run = await fixture.run(fixture.b)
    #expect(run.outcome == .pullConflict)
    #expect(!run.didBringIn)
    #expect(run.mergedDailyPaths.isEmpty)
    #expect(try fixture.read("library/note.md", in: fixture.b) == before)
    #expect(!fixture.exists("rebase-merge", in: fixture.b))
    #expect(!fixture.exists("rebase-apply", in: fixture.b))
    #expect(!fixture.exists(GitSupport.rebaseMarkerName, in: fixture.b))
    #expect(fixture.git(["status", "--porcelain"], in: fixture.b) == "")
}

@Test func pausedRunFetchesButNeverRebases() async throws {
    guard let fixture = try GitFixture() else { return }
    try fixture.write("# From A\n", "library/a.md", in: fixture.a)
    #expect(await fixture.run(fixture.a).outcome == .synced)
    let headBefore = fixture.head(fixture.b)

    let run = await fixture.run(fixture.b, allowRebase: false)
    #expect(run.outcome == .pullConflict)
    #expect(run.fetchSucceeded)
    #expect(!run.didBringIn)
    #expect(run.behind == 1)
    #expect(fixture.head(fixture.b) == headBefore)
}

@Test func noRemoteStillCommitsLocally() async throws {
    guard let fixture = try GitFixture() else { return }
    fixture.git(["remote", "remove", "origin"], in: fixture.a)
    try fixture.write("# Note\n", "library/note.md", in: fixture.a)

    let run = await fixture.run(fixture.a)
    #expect(run.outcome == .noRemote)
    #expect(run.didCommit)
    #expect(fixture.git(["status", "--porcelain"], in: fixture.a) == "")
}

// MARK: - Guards (§6.4)

@Test func indexLockIsBusyAndTouchesNothing() async throws {
    guard let fixture = try GitFixture() else { return }
    try fixture.write("# Note\n", "library/note.md", in: fixture.a)
    let lock = fixture.a.gitDirectory.appending(path: "index.lock")
    try Data().write(to: lock)
    let headBefore = fixture.head(fixture.a)

    let run = await fixture.run(fixture.a)
    #expect(run.outcome == .busy)
    #expect(fixture.head(fixture.a) == headBefore)
    // Never delete a lock file.
    #expect(FileManager.default.fileExists(atPath: lock.path(percentEncoded: false)))
}

@Test func staleLockIsStuck() async throws {
    guard let fixture = try GitFixture() else { return }
    let lock = fixture.a.gitDirectory.appending(path: "index.lock")
    try Data().write(to: lock)
    try FileManager.default.setAttributes([.modificationDate: Date().addingTimeInterval(-11 * 60)],
                                          ofItemAtPath: lock.path(percentEncoded: false))

    #expect(await fixture.run(fixture.a).outcome == .stuck)
    #expect(FileManager.default.fileExists(atPath: lock.path(percentEncoded: false)))
}

/// Leaves `folder` mid-rebase (stopped by a failing `--exec`, no conflict).
private func strandRebase(_ fixture: GitFixture, _ folder: PeteKMFolder) throws {
    try fixture.write("# Local\n", "library/local.md", in: folder)
    fixture.git(["add", "-A"], in: folder)
    fixture.git(["commit", "-m", "local"], in: folder)
    #expect(fixture.git(["rebase", "--exec", "false", "HEAD~1"], in: folder) == nil)
    #expect(fixture.exists("rebase-merge", in: folder))
}

@Test func ownStrandedRebaseIsAbortedAndTheRunContinues() async throws {
    guard let fixture = try GitFixture() else { return }
    try strandRebase(fixture, fixture.a)
    try Data().write(to: GitSupport.rebaseMarker(fixture.a))

    let run = await fixture.run(fixture.a)
    #expect(run.outcome == .synced)
    #expect(run.pushSucceeded)
    #expect(!fixture.exists("rebase-merge", in: fixture.a))
    #expect(!fixture.exists(GitSupport.rebaseMarkerName, in: fixture.a))
}

@Test func someoneElsesRebaseIsBusy() async throws {
    guard let fixture = try GitFixture() else { return }
    try strandRebase(fixture, fixture.a)

    #expect(await fixture.run(fixture.a).outcome == .busy)
    #expect(fixture.exists("rebase-merge", in: fixture.a))
}

// MARK: - Hardening (§6.7)

@Test func gitNeverPrompts() {
    #expect(GitSupport.environment["GIT_TERMINAL_PROMPT"] == "0")
    #expect(GitSupport.environment["GIT_SSH_COMMAND"]?.contains("BatchMode=yes") == true)
    #expect(GitSupport.environment["HOME"] != nil)
    #expect(GitSupport.environment["PATH"] != nil)

    // The child process really sees it.
    let home = URL(filePath: NSHomeDirectory(), directoryHint: .isDirectory)
    let seen = GitSupport.runDetailed(["-c", "alias.envcheck=!printenv GIT_TERMINAL_PROMPT", "envcheck"],
                                      in: home, timeout: .seconds(10))
    guard seen.status != -1 else { return }  // no git
    #expect(seen.output == "0")
}

@Test func hungGitIsKilledAtTheTimeout() {
    let home = URL(filePath: NSHomeDirectory(), directoryHint: .isDirectory)
    let start = Date()
    let result = GitSupport.runDetailed(["-c", "alias.hang=!sleep 30", "hang"], in: home, timeout: .seconds(1))
    guard result.status != -1 || result.timedOut else { return }  // no git
    #expect(result.timedOut)
    #expect(!result.succeeded)
    #expect(Date().timeIntervalSince(start) < 10)
}

@Test func stderrIsCaptured() {
    let home = URL(filePath: NSHomeDirectory(), directoryHint: .isDirectory)
    let result = GitSupport.runDetailed(["no-such-subcommand"], in: home, timeout: .seconds(10))
    #expect(!result.succeeded)
    #expect(!result.stderr.isEmpty)
}

@Test func unreachableHTTPSRemoteFailsFastAsOffline() async throws {
    guard let fixture = try GitFixture() else { return }
    fixture.git(["remote", "set-url", "origin", "https://example.invalid/x.git"], in: fixture.a)
    try fixture.write("# Note\n", "library/note.md", in: fixture.a)

    let start = Date()
    let run = await fixture.run(fixture.a)
    #expect(run.outcome == .offline)
    #expect(run.didCommit)
    #expect(!run.stderr.isEmpty)
    #expect(Date().timeIntervalSince(start) < 35)
}

/// A repository folder for the fake runner: only `.git/` has to exist.
private func fakeRepository() throws -> PeteKMFolder {
    let root = URL(filePath: NSTemporaryDirectory(), directoryHint: .isDirectory)
        .appending(path: "petekm-fakegit-\(UUID().uuidString)", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: root.appending(path: ".git"), withIntermediateDirectories: true)
    return PeteKMFolder(root: root)
}

@Test func timedOutFetchIsOffline() async throws {
    let folder = try fakeRepository()
    let runner = FakeGitRunner { arguments in
        switch arguments.first {
        case "remote": return okWith("origin\n")
        case "fetch": return GitResult(status: 15, stdout: "", stderr: "", timedOut: true)
        default: return ok
        }
    }
    let run = await GitSupport.run(folder, context: GitSupport.SyncContext(runner: runner))
    #expect(run.outcome == .offline)
    #expect(run.stderr.contains("timed out"))
    #expect(!runner.calls.contains { $0.first == "push" })
}

@Test func timedOutPushIsPushFailed() async throws {
    let folder = try fakeRepository()
    let runner = FakeGitRunner { arguments in
        switch arguments.first {
        case "remote": return okWith("origin\n")
        case "status": return okWith(" M library/note.md\n")
        case "rev-list": return okWith("1\t0\n")
        case "push": return GitResult(status: 15, stdout: "", stderr: "", timedOut: true)
        default: return ok
        }
    }
    let run = await GitSupport.run(folder, context: GitSupport.SyncContext(runner: runner))
    #expect(run.outcome == .pushFailed)
    #expect(run.didCommit)
}

/// Sleep path (§5.3): the local commit always completes; the network is
/// skipped once the deadline has passed.
@Test func passedDeadlineCommitsButSkipsTheNetwork() async throws {
    let folder = try fakeRepository()
    let runner = FakeGitRunner { arguments in
        switch arguments.first {
        case "remote": return okWith("origin\n")
        case "status": return okWith(" M library/note.md\n")
        default: return ok
        }
    }
    let context = GitSupport.SyncContext(deadline: Date().addingTimeInterval(-1), runner: runner)
    let run = await GitSupport.run(folder, context: context)
    #expect(run.outcome == .offline)
    #expect(run.didCommit)
    #expect(!runner.calls.contains { $0.first == "fetch" || $0.first == "push" })
}

// MARK: - Device trailer (§6.3, §9.3)

@Test func commitCarriesTheDeviceTrailer() async throws {
    guard let fixture = try GitFixture() else { return }
    try fixture.write("# Note\n", "library/note.md", in: fixture.a)
    #expect(await fixture.run(fixture.a, device: "Pete's Work MacBook").outcome == .synced)

    let body = fixture.git(["log", "-1", "--format=%B"], in: fixture.a) ?? ""
    #expect(body.hasPrefix("PeteKM backup "))
    #expect(body.contains("PeteKM-Device: Pete's Work MacBook"))
}

@Test func otherDeviceLastCommitSkipsThisMacAndTrailerlessCommits() async throws {
    guard let fixture = try GitFixture() else { return }
    try fixture.write("# A\n", "library/a.md", in: fixture.a)
    #expect(await fixture.run(fixture.a, device: "Mac A").outcome == .synced)

    // An agent commit with no trailer lands after it.
    try fixture.write("# Agent\n", "library/agent.md", in: fixture.a)
    fixture.git(["add", "-A"], in: fixture.a)
    fixture.git(["commit", "-m", "agent"], in: fixture.a)
    fixture.git(["push"], in: fixture.a)

    // B's own commit is newest of all.
    try fixture.write("# B\n", "library/b.md", in: fixture.b)
    #expect(await fixture.run(fixture.b, device: "Mac B").outcome == .synced)

    let last = GitSupport.otherDeviceLastCommit(fixture.b, thisDevice: "Mac B")
    #expect(last?.name == "Mac A")
    #expect(GitSupport.otherDeviceLastCommit(fixture.b, thisDevice: "Mac A")?.name == "Mac B")
}

@Test func otherDeviceLastCommitIsNilWithoutTrailers() throws {
    guard let fixture = try GitFixture() else { return }
    #expect(GitSupport.otherDeviceLastCommit(fixture.a, thisDevice: "Mac A") == nil)
}

@Test func bringingChangesInNamesTheSendingMac() async throws {
    guard let fixture = try GitFixture() else { return }
    try fixture.write("# A\n", "library/a.md", in: fixture.a)
    #expect(await fixture.run(fixture.a, device: "Mac A").outcome == .synced)

    let run = await fixture.run(fixture.b, device: "Mac B")
    #expect(run.didBringIn)
    #expect(run.incomingDevice == "Mac A")

    // A trailer-less incoming commit names no device.
    try fixture.write("# Agent\n", "library/agent.md", in: fixture.a)
    fixture.git(["add", "-A"], in: fixture.a)
    fixture.git(["commit", "-m", "agent"], in: fixture.a)
    fixture.git(["push"], in: fixture.a)
    let second = await fixture.run(fixture.b, device: "Mac B")
    #expect(second.didBringIn)
    #expect(second.incomingDevice == nil)
}

@Test func deviceNameIsNeverEmpty() {
    #expect(!GitSupport.deviceName.isEmpty)
}

// MARK: - Merged-daily detector (§7.3)

@Test func dailyPathsChangedOnBothSidesIntersectsDailyOnly() async throws {
    guard let fixture = try GitFixture() else { return }
    try fixture.write("from A\n", "daily/2026-10-05.md", in: fixture.a)
    try fixture.write("from A\n", "library/shared.md", in: fixture.a)
    try fixture.write("only A\n", "daily/2026-10-04.md", in: fixture.a)
    #expect(await fixture.run(fixture.a).outcome == .synced)

    try fixture.write("from B\n", "daily/2026-10-05.md", in: fixture.b)
    try fixture.write("from B\n", "library/shared.md", in: fixture.b)
    fixture.git(["add", "-A"], in: fixture.b)
    fixture.git(["commit", "-m", "b"], in: fixture.b)
    fixture.git(["fetch"], in: fixture.b)

    #expect(GitSupport.dailyPathsChangedOnBothSides(fixture.b) == ["daily/2026-10-05.md"])
}

@Test func dailyStickyPathMatchesTheAttributePattern() {
    #expect(GitSupport.isDailyStickyPath("daily/2026-10-05.md"))
    #expect(!GitSupport.isDailyStickyPath("daily/sub/2026-10-05.md"))
    #expect(!GitSupport.isDailyStickyPath("library/daily/2026-10-05.md"))
    #expect(!GitSupport.isDailyStickyPath("daily/notes.txt"))
}

// MARK: - Daily union merge (§7.2–§7.5)

private func lines(_ data: Data) -> Set<Substring> {
    Set(String(decoding: data, as: UTF8.self).split(separator: "\n"))
}

@Test func dailyUnionMergeAttributeIsTrackedAndShared() async throws {
    guard let fixture = try GitFixture() else { return }
    await fixture.shareDailyUnionMerge()

    #expect(fixture.git(["ls-files", ".gitattributes"], in: fixture.a) == ".gitattributes")
    #expect(fixture.git(["check-attr", "merge", "daily/2026-10-05.md"], in: fixture.b)
            == "daily/2026-10-05.md: merge: union")
    #expect(fixture.git(["check-attr", "merge", "library/note.md"], in: fixture.b)
            == "library/note.md: merge: unspecified")
}

@Test func sameDayStickyOnTwoMacsKeepsEveryLine() async throws {
    guard let fixture = try GitFixture() else { return }
    await fixture.shareDailyUnionMerge()
    let path = "daily/2026-10-05.md"
    try fixture.write("# 2026-10-05\n\n- start\n", path, in: fixture.a)
    #expect(await fixture.run(fixture.a).outcome == .synced)
    #expect(await fixture.run(fixture.b).outcome == .synced)

    try fixture.write("# 2026-10-05\n\n- start\n- from A\n", path, in: fixture.a)
    #expect(await fixture.run(fixture.a).outcome == .synced)
    try fixture.write("# 2026-10-05\n\n- start\n- from B\n", path, in: fixture.b)

    let run = await fixture.run(fixture.b)
    #expect(run.outcome == .synced)
    #expect(run.didBringIn)
    #expect(run.mergedDailyPaths == [path])
    let merged = lines(try fixture.read(path, in: fixture.b))
    #expect(merged.isSuperset(of: ["# 2026-10-05", "- start", "- from A", "- from B"]))
    #expect(!String(decoding: try fixture.read(path, in: fixture.b), as: UTF8.self).contains("<<<<<<<"))
    #expect(!fixture.exists("rebase-merge", in: fixture.b))
    #expect(fixture.git(["status", "--porcelain"], in: fixture.b) == "")

    // A catches up to the same file.
    #expect(await fixture.run(fixture.a).outcome == .synced)
    #expect(try fixture.read(path, in: fixture.a) == fixture.read(path, in: fixture.b))
}

/// Both Macs started the day independently: an add/add on today's file.
@Test func sameDayStickyCreatedOnBothMacsKeepsEveryLine() async throws {
    guard let fixture = try GitFixture() else { return }
    await fixture.shareDailyUnionMerge()
    let path = "daily/2026-10-05.md"
    try fixture.write("# 2026-10-05\n\n## Work\n- written on A\n", path, in: fixture.a)
    #expect(await fixture.run(fixture.a).outcome == .synced)
    try fixture.write("# 2026-10-05\n\n## Personal\n- written on B\n", path, in: fixture.b)

    let run = await fixture.run(fixture.b)
    #expect(run.outcome == .synced)
    #expect(run.mergedDailyPaths == [path])
    let merged = lines(try fixture.read(path, in: fixture.b))
    #expect(merged.isSuperset(of: ["# 2026-10-05", "## Work", "- written on A",
                                   "## Personal", "- written on B"]))
}

/// The attribute keeps Library conflicts exactly as they were: abort and pause.
@Test func libraryConflictStillPausesWithTheAttribute() async throws {
    guard let fixture = try GitFixture() else { return }
    await fixture.shareDailyUnionMerge()
    try fixture.write("shared\n", "library/note.md", in: fixture.a)
    #expect(await fixture.run(fixture.a).outcome == .synced)
    #expect(await fixture.run(fixture.b).outcome == .synced)

    try fixture.write("edited on A\n", "library/note.md", in: fixture.a)
    #expect(await fixture.run(fixture.a).outcome == .synced)
    try fixture.write("edited on B\n", "library/note.md", in: fixture.b)
    let before = try fixture.read("library/note.md", in: fixture.b)

    #expect(await fixture.run(fixture.b).outcome == .pullConflict)
    #expect(try fixture.read("library/note.md", in: fixture.b) == before)
    #expect(!fixture.exists("rebase-merge", in: fixture.b))
}

/// Rollout (§7.5): the first v2 sync on a Mac commits `.gitattributes` while the
/// remote has none. The rebase checks out the remote's files, so only the
/// repository-local `.git/info/attributes` can make the daily merge by union.
@Test func firstSyncMergesSameDayStickyBeforeTheAttributeIsOnTheRemote() async throws {
    guard let fixture = try GitFixture() else { return }
    let path = "daily/2026-10-05.md"
    try fixture.write("- start\n", path, in: fixture.a)
    #expect(await fixture.run(fixture.a).outcome == .synced)
    #expect(await fixture.run(fixture.b).outcome == .synced)

    try fixture.write("- start\n- from A\n", path, in: fixture.a)
    #expect(await fixture.run(fixture.a).outcome == .synced)
    let localAttributes = fixture.b.gitDirectory.appending(path: "info/attributes")
    try? FileManager.default.removeItem(at: localAttributes)  // B's first v2 sync
    FolderInitializer.ensureDailyUnionMerge(fixture.b)
    try fixture.write("- start\n- from B\n", path, in: fixture.b)

    let run = await fixture.run(fixture.b)
    #expect(run.outcome == .synced)
    #expect(run.mergedDailyPaths == [path])
    #expect(lines(try fixture.read(path, in: fixture.b)).isSuperset(of: ["- start", "- from A", "- from B"]))
    #expect(!fixture.exists("rebase-merge", in: fixture.b))
    #expect(!fixture.exists(GitSupport.rebaseMarkerName, in: fixture.b))
}

@Test func ensureLocalDailyUnionMergeWritesOnceAndSkipsNonRepositories() throws {
    guard let fixture = try GitFixture() else { return }
    let url = fixture.a.gitDirectory.appending(path: "info/attributes")
    try? FileManager.default.removeItem(at: url)

    #expect(FolderInitializer.ensureLocalDailyUnionMerge(fixture.a))
    #expect(FileWriting.readText(url)?.contains(AgentTemplates.dailyUnionLine) == true)
    #expect(!FolderInitializer.ensureLocalDailyUnionMerge(fixture.a))

    let plain = PeteKMFolder(root: FileManager.default.temporaryDirectory
        .appending(path: "petekm-no-git-\(UUID().uuidString)", directoryHint: .isDirectory))
    #expect(!FolderInitializer.ensureLocalDailyUnionMerge(plain))
    #expect(!FileWriting.isDirectory(plain.gitDirectory))
}
