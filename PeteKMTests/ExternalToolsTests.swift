import Foundation
import Testing
@testable import PeteKM

// MARK: - Fixtures

private func makeFolder() throws -> PeteKMFolder {
    let root = URL(filePath: NSTemporaryDirectory(), directoryHint: .isDirectory)
        .appending(path: "petekm-external-\(UUID().uuidString)", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    return PeteKMFolder(root: root)
}

private func makeRepository() throws -> PeteKMFolder? {
    guard GitSupport.isGitAvailable else { return nil }
    let folder = try makeFolder()
    GitSupport.initializeRepository(at: folder)
    // Commits need an identity; keep it local to the throwaway repo.
    GitSupport.run(["config", "user.email", "tests@petekm.local"], in: folder.root)
    GitSupport.run(["config", "user.name", "PeteKM Tests"], in: folder.root)
    return folder
}

// MARK: - Commit message (§17.2)

@Test func commitMessageMatchesTheBackupFormat() {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "UTC")!

    var components = DateComponents()
    components.year = 2026
    components.month = 8
    components.day = 19
    components.hour = 20
    components.minute = 45
    let date = calendar.date(from: components)!

    #expect(GitSupport.commitMessage(for: date, calendar: calendar) == "PeteKM backup 2026-08-19 20:45")
}

/// A bare "remote" plus two clones of it — enough to exercise real pull/push
/// with no network (sync spec §5).
private func makeRepositoryPair() throws -> (remote: URL, a: PeteKMFolder, b: PeteKMFolder)? {
    guard GitSupport.isGitAvailable else { return nil }
    let base = URL(filePath: NSTemporaryDirectory(), directoryHint: .isDirectory)
        .appending(path: "petekm-pair-\(UUID().uuidString)", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)

    let remote = base.appending(path: "remote.git", directoryHint: .isDirectory)
    GitSupport.run(["init", "--bare", "--initial-branch", "main", remote.path(percentEncoded: false)], in: base)

    func clone(_ name: String) -> PeteKMFolder {
        GitSupport.run(["clone", remote.path(percentEncoded: false), name], in: base)
        let folder = PeteKMFolder(root: base.appending(path: name, directoryHint: .isDirectory))
        GitSupport.run(["config", "user.email", "tests@petekm.local"], in: folder.root)
        GitSupport.run(["config", "user.name", "PeteKM Tests"], in: folder.root)
        return folder
    }

    // Seed the remote before the second clone, so both clones track `main` the
    // way a real second device would.
    let a = clone("a")
    GitSupport.run(["checkout", "-B", "main"], in: a.root)
    try FileWriting.writeAtomically("# PeteKM", to: a.root.appending(path: "README.md"))
    GitSupport.run(["add", "-A"], in: a.root)
    GitSupport.run(["commit", "-m", "seed"], in: a.root)
    GitSupport.run(["push", "--set-upstream", "origin", "main"], in: a.root)

    return (remote, a, clone("b"))
}

// MARK: - Sync (sync spec §5)

@Test func syncReportsMissingRepository() throws {
    let folder = try makeFolder()
    let outcome = GitSupport.sync(folder)
    #expect(outcome == .notARepository || outcome == .gitUnavailable)
}

@Test func syncCommitsLocallyWhenNoRemoteExists() throws {
    guard let folder = try makeRepository() else { return }
    try FileWriting.writeAtomically("# Note", to: folder.root.appending(path: "INDEX.md"))

    #expect(GitSupport.sync(folder) == .noRemote)
    #expect(GitSupport.run(["log", "--oneline"], in: folder.root)?.contains("PeteKM backup") == true)
}

@Test func syncReportsNothingToSyncOnACleanTree() throws {
    guard let pair = try makeRepositoryPair() else { return }
    try FileWriting.writeAtomically("# Note", to: pair.a.root.appending(path: "INDEX.md"))
    #expect(GitSupport.sync(pair.a) == .synced)

    #expect(GitSupport.sync(pair.a) == .nothingToSync)
}

@Test func syncPushesToTheRemote() throws {
    guard let pair = try makeRepositoryPair() else { return }
    try FileWriting.writeAtomically("# Note", to: pair.a.root.appending(path: "INDEX.md"))

    #expect(GitSupport.sync(pair.a) == .synced)
    #expect(GitSupport.run(["log", "--oneline", "main"], in: pair.remote)?.contains("PeteKM backup") == true)
}

@Test func syncPullsTheOtherDevicesWorkWhileCommittingItsOwn() throws {
    guard let pair = try makeRepositoryPair() else { return }
    try FileWriting.writeAtomically("# From A", to: pair.a.root.appending(path: "a.md"))
    #expect(GitSupport.sync(pair.a) == .synced)

    try FileWriting.writeAtomically("# From B", to: pair.b.root.appending(path: "b.md"))
    #expect(GitSupport.sync(pair.b) == .synced)

    #expect(FileManager.default.fileExists(atPath: pair.b.root.appending(path: "a.md").path(percentEncoded: false)))
    #expect(FileManager.default.fileExists(atPath: pair.b.root.appending(path: "b.md").path(percentEncoded: false)))
}

/// The important one: the same line edited on two devices leaves the working tree
/// byte-identical and no rebase in progress (§5.2, §6.4).
@Test func syncAbortsAndRestoresOnAConflict() throws {
    guard let pair = try makeRepositoryPair() else { return }
    let name = "note.md"
    try FileWriting.writeAtomically("shared", to: pair.a.root.appending(path: name))
    #expect(GitSupport.sync(pair.a) == .synced)
    #expect(GitSupport.sync(pair.b) == .synced)

    try FileWriting.writeAtomically("edited on A", to: pair.a.root.appending(path: name))
    #expect(GitSupport.sync(pair.a) == .synced)

    let bFile = pair.b.root.appending(path: name)
    try FileWriting.writeAtomically("edited on B", to: bFile)
    let before = try Data(contentsOf: bFile)

    #expect(GitSupport.sync(pair.b) == .pullConflict)
    #expect(try Data(contentsOf: bFile) == before)
    #expect(!FileManager.default.fileExists(
        atPath: pair.b.root.appending(path: ".git/rebase-merge", directoryHint: .isDirectory).path(percentEncoded: false)))
    #expect(!FileManager.default.fileExists(
        atPath: pair.b.root.appending(path: ".git/rebase-apply", directoryHint: .isDirectory).path(percentEncoded: false)))
}

/// A vanished remote fails at `fetch`, before push — so the outcome is `.offline`,
/// and either way the local commit stands (§6.5).
@Test func syncKeepsTheLocalCommitWhenTheRemoteIsUnreachable() throws {
    guard let pair = try makeRepositoryPair() else { return }
    try FileWriting.writeAtomically("# Note", to: pair.a.root.appending(path: "INDEX.md"))
    #expect(GitSupport.sync(pair.a) == .synced)

    // The remote disappears; the commit must still land locally (§6.5).
    try FileManager.default.removeItem(at: pair.remote)
    try FileWriting.writeAtomically("# More", to: pair.a.root.appending(path: "INDEX.md"))

    #expect(GitSupport.sync(pair.a) == .offline)
    #expect(GitSupport.run(["log", "--oneline"], in: pair.a.root)?.contains("PeteKM backup") == true)
}

// MARK: - aheadBehind (sync spec §5.1)

@Test func aheadBehindIsNilWithoutAnUpstream() throws {
    guard let folder = try makeRepository() else { return }
    try FileWriting.writeAtomically("# Note", to: folder.root.appending(path: "INDEX.md"))
    _ = GitSupport.sync(folder)

    #expect(GitSupport.aheadBehind(folder) == nil)
}

@Test func aheadBehindCountsDivergence() throws {
    guard let pair = try makeRepositoryPair() else { return }
    try FileWriting.writeAtomically("# Note", to: pair.a.root.appending(path: "INDEX.md"))
    #expect(GitSupport.sync(pair.a) == .synced)
    #expect(GitSupport.aheadBehind(pair.a)! == (ahead: 0, behind: 0))

    try FileWriting.writeAtomically("# Local only", to: pair.a.root.appending(path: "local.md"))
    GitSupport.run(["add", "-A"], in: pair.a.root)
    GitSupport.run(["commit", "-m", "local"], in: pair.a.root)
    #expect(GitSupport.aheadBehind(pair.a)! == (ahead: 1, behind: 0))
}

@Test func remoteNameIsNilWithoutARemote() throws {
    guard let folder = try makeRepository() else { return }
    #expect(GitSupport.remoteName(of: folder) == nil)

    GitSupport.run(["remote", "add", "origin", "/nonexistent/petekm-remote.git"], in: folder.root)
    #expect(GitSupport.remoteName(of: folder) == "origin")
}

// MARK: - Notice copy (DESIGN §32)

@Test func syncNoticesStayTerseAndBlameless() {
    #expect(GitSupport.SyncOutcome.synced.notice(editorName: "Stub Editor") == "Synced.")
    #expect(GitSupport.SyncOutcome.nothingToSync.notice(editorName: "Stub Editor") == "Already up to date.")
    #expect(GitSupport.SyncOutcome.noRemote.notice(editorName: "Stub Editor") == "Saved locally. No GitHub remote is set.")
    // The conflict notice names the configured editor, never a hard-coded one (§5.4).
    #expect(GitSupport.SyncOutcome.pullConflict.notice(editorName: "Stub Editor").contains("Stub Editor"))
    #expect(!GitSupport.SyncOutcome.pullConflict.notice(editorName: "Stub Editor").contains("VS Code"))

    for outcome: GitSupport.SyncOutcome in [.gitUnavailable, .notARepository, .offline, .noRemote,
                                            .pullConflict, .pushFailed, .nothingToSync, .synced] {
        let notice = outcome.notice(editorName: "Stub Editor")
        #expect(!notice.contains("Sorry"))
        #expect(!notice.contains("!"))
    }
}

// MARK: - Palette availability (§10.2)

private struct StubEditor: ExternalEditor {
    let displayName = "Stub Editor"
    let isAvailable: Bool
    func open(folder: URL) -> Bool { isAvailable }
    func open(file: URL, in folder: URL) -> Bool { isAvailable }
}

@MainActor
@Test func gitSyncIsAbsentOutsideARepository() throws {
    let folder = try makeFolder()
    let model = PaletteModel(editor: StubEditor(isAvailable: true))
    model.configure(folder: folder) { _ in }

    #expect(model.isAvailable(.gitSync) == false)
    #expect(model.isAvailable(.openFolderInEditor) == true)
}

@MainActor
@Test func editorCommandsAreAbsentWithoutAnEditor() throws {
    let folder = try makeFolder()
    let model = PaletteModel(editor: StubEditor(isAvailable: false))
    model.configure(folder: folder) { _ in }
    model.present()

    #expect(model.isAvailable(.openLibraryInEditor) == false)
    #expect(model.isAvailable(.openCurrentFileInEditor) == false)
    #expect(model.rows.contains { $0.id == PaletteCommandID.openFolderInEditor.rawValue } == false)
    #expect(model.rows.contains { $0.id == PaletteCommandID.openTerminal.rawValue })
}

@MainActor
@Test func externalCommandsHandOffTheRightOutcome() throws {
    let folder = try makeFolder()
    let model = PaletteModel(editor: StubEditor(isAvailable: true))

    var outcomes: [PaletteOutcome] = []
    model.configure(folder: folder) { outcomes.append($0) }
    model.present()

    model.commit(PaletteRow(id: "x", title: "", subtitle: nil, snippet: nil,
                            kind: .command(.openLibraryInEditor)))
    model.present()
    model.commit(PaletteRow(id: "x", title: "", subtitle: nil, snippet: nil,
                            kind: .command(.openTerminal)))

    #expect(outcomes == [.openInEditor(folder.library), .openTerminalInFolder])
}

// MARK: - VS Code lookup (§18.7)

@Test func vsCodeReportsUnavailabilityWithoutCrashing() {
    let editor = VSCodeEditor()
    // Whether VS Code is installed on this machine is not the app's business;
    // what matters is that the lookup answers and the notice reads plainly.
    _ = editor.isAvailable
    #expect(editor.unavailableNotice == "PeteKM couldn't open VS Code.")
}
