//
//  GitSupport.swift
//  PeteKM
//
//  Git is optional and never required for capture (spec §6.3, §17.4).
//  Everything here degrades quietly: a Git failure must never block opening or
//  saving a Daily Sticky.
//

import Foundation

enum GitSupport {

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

    /// Run a git subcommand, returning trimmed stdout, or nil if git is missing
    /// or exited non-zero.
    @discardableResult
    static func run(_ arguments: [String], in directory: URL) -> String? {
        let process = Process()
        process.executableURL = URL(filePath: "/usr/bin/env")
        process.arguments = ["git"] + arguments
        process.currentDirectoryURL = directory

        let output = Pipe()
        process.standardOutput = output
        process.standardError = Pipe()

        do {
            try process.run()
        } catch {
            return nil
        }

        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { return nil }
        return String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
