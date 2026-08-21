//
//  FileWriting.swift
//  PeteKM
//
//  Atomic writes everywhere (spec §19.3). Never truncate a user's file.
//

import Foundation

enum FileWriting {

    /// Write text atomically (temp file, then rename), creating parent
    /// directories as needed.
    static func writeAtomically(_ text: String, to url: URL) throws {
        let directory = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        guard let data = text.data(using: .utf8) else {
            throw CocoaError(.fileWriteInapplicableStringEncoding)
        }
        try data.write(to: url, options: [.atomic])
    }

    static func exists(_ url: URL) -> Bool {
        FileManager.default.fileExists(atPath: url.path(percentEncoded: false))
    }

    static func isDirectory(_ url: URL) -> Bool {
        var isDir: ObjCBool = false
        let found = FileManager.default.fileExists(atPath: url.path(percentEncoded: false), isDirectory: &isDir)
        return found && isDir.boolValue
    }

    static func readText(_ url: URL) -> String? {
        try? String(contentsOf: url, encoding: .utf8)
    }

    /// Move `url` aside as `<name>.bak-YYYY-MM-DD`, disambiguating with a
    /// counter so an existing backup is never clobbered (§6.5, §19.2).
    @discardableResult
    static func backUp(_ url: URL, on date: Date = Date(), calendar: Calendar = .current) throws -> URL {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        let stamp = String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
        let base = url.lastPathComponent
        var candidate = url.deletingLastPathComponent().appending(path: "\(base).bak-\(stamp)")
        var counter = 2
        while exists(candidate) {
            candidate = url.deletingLastPathComponent().appending(path: "\(base).bak-\(stamp)-\(counter)")
            counter += 1
        }
        try FileManager.default.moveItem(at: url, to: candidate)
        return candidate
    }
}
