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

// MARK: - Git Sync (§17.2, §17.4)

@Test func syncReportsMissingRepository() throws {
    let folder = try makeFolder()
    let outcome = GitSupport.sync(folder)
    #expect(outcome == .notARepository || outcome == .gitUnavailable)
}

@Test func syncCommitsLocallyWhenNoRemoteExists() throws {
    guard let folder = try makeRepository() else { return }
    try FileWriting.writeAtomically("# Note", to: folder.root.appending(path: "INDEX.md"))

    #expect(GitSupport.sync(folder) == .committedNotPushed(reason: .noRemote))
    #expect(GitSupport.run(["log", "--oneline"], in: folder.root)?.contains("PeteKM backup") == true)
}

@Test func syncReportsNothingToCommitOnACleanTree() throws {
    guard let folder = try makeRepository() else { return }
    try FileWriting.writeAtomically("# Note", to: folder.root.appending(path: "INDEX.md"))
    _ = GitSupport.sync(folder)

    #expect(GitSupport.sync(folder) == .nothingToCommit)
}

@Test func syncKeepsTheLocalCommitWhenPushFails() throws {
    guard let folder = try makeRepository() else { return }
    // A remote that cannot exist: the commit must still land (§17.4).
    GitSupport.run(["remote", "add", "origin", "/nonexistent/petekm-remote.git"], in: folder.root)
    try FileWriting.writeAtomically("# Note", to: folder.root.appending(path: "INDEX.md"))

    #expect(GitSupport.sync(folder) == .committedNotPushed(reason: .pushFailed))
    #expect(GitSupport.run(["log", "--oneline"], in: folder.root)?.contains("PeteKM backup") == true)
}

@Test func remoteNameIsNilWithoutARemote() throws {
    guard let folder = try makeRepository() else { return }
    #expect(GitSupport.remoteName(of: folder) == nil)

    GitSupport.run(["remote", "add", "origin", "/nonexistent/petekm-remote.git"], in: folder.root)
    #expect(GitSupport.remoteName(of: folder) == "origin")
}

// MARK: - Notice copy (DESIGN §32)

@Test func syncNoticesStayTerseAndBlameless() {
    #expect(GitSupport.SyncOutcome.pushed.notice == "Committed and pushed.")
    #expect(GitSupport.SyncOutcome.committedNotPushed(reason: .pushFailed).notice
            == "Committed locally. Push failed — resolve in a Git tool.")
    for outcome: GitSupport.SyncOutcome in [.gitUnavailable, .notARepository, .nothingToCommit, .commitFailed] {
        #expect(!outcome.notice.contains("Sorry"))
        #expect(!outcome.notice.contains("!"))
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
