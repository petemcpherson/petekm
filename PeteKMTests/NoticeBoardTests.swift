//
//  NoticeBoardTests.swift
//  PeteKMTests
//

import Foundation
import Testing
@testable import PeteKM

@MainActor
struct NoticeBoardTests {

    @Test func ordinaryNoticeIsReplacedAndGone() async throws {
        let board = NoticeBoard()
        board.show("first", seconds: 0.05)
        board.show("second", seconds: 0.05)
        #expect(board.text == "second")
        try await Task.sleep(for: .milliseconds(150))
        #expect(board.text == nil)
    }

    @Test func mustBeSeenNoticeComesBackAfterItsReplacement() async throws {
        let board = NoticeBoard()
        var seen = false
        board.show("agent files", seconds: 0.1, mustBeSeen: true) { seen = true }
        board.show("Updated from Mac A.", seconds: 0.05)
        #expect(board.text == "Updated from Mac A.")
        #expect(!seen)

        try await Task.sleep(for: .milliseconds(80))
        #expect(board.text == "agent files")
        #expect(!seen)

        try await Task.sleep(for: .milliseconds(150))
        #expect(board.text == nil)
        #expect(seen)
    }

    @Test func clearRecordsNothing() async throws {
        let board = NoticeBoard()
        var seen = false
        board.show("agent files", seconds: 0.05, mustBeSeen: true) { seen = true }
        board.clear()
        try await Task.sleep(for: .milliseconds(120))
        #expect(board.text == nil)
        #expect(!seen)
    }
}
