import AppKit
import Foundation
import Testing
@testable import PeteKM

// Sync v2 visibility (context/sync-v2/spec.md §8.1, §8.4, §9.2, §9.3): status-line
// copy, the dot and its 2-minute rule, time phrases, and the earlier-notes and
// quit-alert conditions.

private let locale = Locale(identifier: "en_GB")

private var calendar: Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "UTC")!
    return calendar
}

/// 2026-10-05 14:30:00 UTC.
private let now = Date(timeIntervalSince1970: 1_791_210_600)

private func minutesAgo(_ minutes: Double) -> Date {
    now.addingTimeInterval(-minutes * 60)
}

private func line(_ status: SyncStatus) -> String? {
    status.line(now: now, calendar: calendar, locale: locale)
}

// MARK: - Status line (§8.4)

@Test @MainActor func statusLineCopyForEveryState() {
    #expect(line(.off) == nil)
    #expect(line(.synced(at: minutesAgo(2))) == "Synced 2 min ago.")
    #expect(line(.syncing) == "Syncing…")
    #expect(line(.pending(since: minutesAgo(28))) == "Not synced yet — changes from 28 min ago are only on this Mac.")
    #expect(line(.pending(since: minutesAgo(88))) == "Not synced yet — changes from 13:02 are only on this Mac.")
    #expect(line(.offline(since: now, pendingSince: minutesAgo(88))) == "Offline — changes from 13:02 are only on this Mac.")
    #expect(line(.offline(since: now, pendingSince: nil)) == "Offline. Nothing waiting to sync.")
    #expect(line(.paused) == "Sync paused — the same note changed on two Macs. Nothing was lost.")
    #expect(line(.failing(.push)) == "Can't send changes to GitHub. Try Sync Now, or check your Git sign-in.")
    #expect(line(.failing(.lock)) == "Sync is stuck — another Git tool is mid-operation in this folder.")
}

// MARK: - Dot (§8.1)

@Test @MainActor func dotFollowsTheStateTable() {
    #expect(SyncStatus.off.dot(now: now) == .hidden)
    #expect(SyncStatus.synced(at: minutesAgo(30)).dot(now: now) == .hidden)
    #expect(SyncStatus.syncing.dot(now: now) == .hidden)
    #expect(SyncStatus.offline(since: minutesAgo(30), pendingSince: nil).dot(now: now) == .hidden)
    #expect(SyncStatus.paused.dot(now: now) == .orange)
    #expect(SyncStatus.failing(.push).dot(now: now) == .orange)
    #expect(SyncStatus.failing(.lock).dot(now: now) == .orange)
}

@Test @MainActor func pendingDotWaitsTwoMinutes() {
    let since = now
    let pending = SyncStatus.pending(since: since)
    #expect(pending.dot(now: since.addingTimeInterval(119)) == .hidden)
    #expect(pending.dot(now: since.addingTimeInterval(120)) == .secondary)

    let offline = SyncStatus.offline(since: since, pendingSince: since)
    #expect(offline.dot(now: since.addingTimeInterval(119)) == .hidden)
    #expect(offline.dot(now: since.addingTimeInterval(120)) == .secondary)
}

// MARK: - Time phrases (§8.4, §9.3)

@Test @MainActor func timePhraseIsRelativeThenClockThenDate() {
    func phrase(_ date: Date) -> String {
        SyncTime.phrase(for: date, now: now, calendar: calendar, locale: locale)
    }
    #expect(phrase(now.addingTimeInterval(-20)) == "just now")
    #expect(phrase(minutesAgo(2)) == "2 min ago")
    #expect(phrase(minutesAgo(59)) == "59 min ago")
    #expect(phrase(minutesAgo(60)) == "13:30")
    #expect(phrase(minutesAgo(14 * 60)) == "00:30")
    #expect(phrase(minutesAgo(3 * 24 * 60)) == "2 Oct")
    #expect(phrase(minutesAgo(400 * 24 * 60)) == "31 Aug 2025")
}

@Test @MainActor func otherDeviceLineNamesTheOtherMac() {
    let line = SyncTime.otherDeviceLine((name: "Pete's Personal MacBook", at: minutesAgo(315)),
                                        now: now, calendar: calendar, locale: locale)
    #expect(line == "Last from Pete's Personal MacBook: today 09:15.")
    #expect(SyncTime.otherDeviceLine(nil, now: now) == nil)
}

// MARK: - Earlier-notes notice (§9.2.3)

@Test @MainActor func earlierNotesNoticeNeedsUnpushedCommitsFromBeforeTheWake() {
    let wokeAt = minutesAgo(1)
    #expect(SyncTime.showsEarlierNotesNotice(ahead: 2, oldestUnpushed: minutesAgo(30), arrivedAt: wokeAt))
    #expect(!SyncTime.showsEarlierNotesNotice(ahead: 1, oldestUnpushed: now, arrivedAt: wokeAt))
    #expect(!SyncTime.showsEarlierNotesNotice(ahead: 0, oldestUnpushed: minutesAgo(30), arrivedAt: wokeAt))
    #expect(!SyncTime.showsEarlierNotesNotice(ahead: 0, oldestUnpushed: nil, arrivedAt: wokeAt))
}

@Test func unpushedCommitsReportsCountAndOldestDate() throws {
    let folder = PeteKMFolder(root: URL(filePath: NSTemporaryDirectory()))
    let runner = FakeGitRunner { arguments in
        #expect(arguments == ["log", "--format=%ct", "@{upstream}..HEAD"])
        return GitResult(status: 0, stdout: "1791210000\n1791200000\n", stderr: "", timedOut: false)
    }
    let unpushed = try #require(GitSupport.unpushedCommits(folder, runner: runner))
    #expect(unpushed.count == 2)
    #expect(unpushed.oldest == Date(timeIntervalSince1970: 1_791_200_000))

    let none = FakeGitRunner { _ in GitResult(status: 0, stdout: "", stderr: "", timedOut: false) }
    #expect(GitSupport.unpushedCommits(folder, runner: none)?.count == 0)
    let noUpstream = FakeGitRunner { _ in .failed("no upstream") }
    #expect(GitSupport.unpushedCommits(folder, runner: noUpstream) == nil)
}

// MARK: - Quit alert (§9.2.2)

@Test func systemQuitCarriesAQuitReason() {
    func quitEvent() -> NSAppleEventDescriptor {
        NSAppleEventDescriptor(eventClass: AEEventClass(kCoreEventClass),
                               eventID: AEEventID(kAEQuitApplication),
                               targetDescriptor: nil,
                               returnID: AEReturnID(kAutoGenerateReturnID),
                               transactionID: AETransactionID(kAnyTransactionID))
    }
    #expect(!AppDelegate.isSystemQuit(nil))
    #expect(!AppDelegate.isSystemQuit(quitEvent()))

    let logout = quitEvent()
    logout.setParam(NSAppleEventDescriptor(enumCode: OSType(kAEReallyLogOut)), forKeyword: AEKeyword(kAEQuitReason))
    #expect(AppDelegate.isSystemQuit(logout))
}
