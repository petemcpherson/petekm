//
//  SearchIndex.swift
//  PeteKM
//
//  Disposable full-text index over every `.md` file in the PeteKM folder
//  (spec §11.6, §5.8). It lives in Application Support, keyed by folder — never
//  inside the PeteKM folder itself — and is fully rebuildable from disk.
//  Deleting it costs nothing but a rescan.
//

import CryptoKit
import Foundation
import Observation

/// One indexed Markdown file. A cache of what is on disk, never the canonical copy (§2.2).
nonisolated struct IndexedFile: Codable, Sendable, Equatable {
    var relativePath: String
    var modified: Date
    var size: Int
    var text: String

    var filename: String { (relativePath as NSString).lastPathComponent }
}

nonisolated struct SearchIndexStore: Codable, Sendable {
    var version = 1
    var files: [String: IndexedFile] = [:]
}

/// Walks the folder and reads only what changed. Pure file I/O, safe off the main actor.
nonisolated enum SearchIndexBuilder {

    static func scan(root: URL, previous: SearchIndexStore) -> SearchIndexStore {
        let keys: Set<URLResourceKey> = [.isDirectoryKey, .contentModificationDateKey, .fileSizeKey]
        var next = SearchIndexStore()

        guard let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: Array(keys),
            options: [.skipsPackageDescendants]
        ) else { return next }

        for case let url as URL in enumerator {
            let name = url.lastPathComponent

            // `.claude/`, `.git/` and every other dot-entry stay out of search (§11.1).
            if name.hasPrefix(".") {
                if (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true {
                    enumerator.skipDescendants()
                }
                continue
            }
            guard url.pathExtension.lowercased() == "md" else { continue }

            let values = try? url.resourceValues(forKeys: keys)
            let modified = values?.contentModificationDate ?? .distantPast
            let size = values?.fileSize ?? 0
            let relative = relativePath(of: url, in: root)

            if let cached = previous.files[relative], cached.modified == modified, cached.size == size {
                next.files[relative] = cached
                continue
            }
            guard let text = try? String(contentsOf: url, encoding: .utf8) else { continue }
            next.files[relative] = IndexedFile(relativePath: relative, modified: modified, size: size, text: text)
        }

        return next
    }

    static func relativePath(of url: URL, in root: URL) -> String {
        let rootPath = root.standardizedFileURL.path(percentEncoded: false)
        let filePath = url.standardizedFileURL.path(percentEncoded: false)
        guard filePath.hasPrefix(rootPath) else { return url.lastPathComponent }
        return String(filePath.dropFirst(rootPath.count)).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    }
}

@MainActor
@Observable
final class SearchIndex {

    private(set) var isRefreshing = false
    private(set) var fileCount = 0

    private let folder: PeteKMFolder
    private let cacheURL: URL
    private var store = SearchIndexStore()
    private var isStale = true
    private var lastScan = Date.distantPast
    private var watchers: [DirectoryWatcher] = []

    /// Watchers cover the directories that exist at launch; this catches folders
    /// created afterwards without paying for a recursive rescan on every keystroke.
    private static let freshnessWindow: TimeInterval = 3

    init(folder: PeteKMFolder) {
        self.folder = folder
        self.cacheURL = SearchIndex.indexFileURL(for: folder)
        loadFromDisk()
        startWatching()
    }

    /// Every indexed Markdown path, relative to the folder root.
    var markdownPaths: [String] {
        store.files.keys.sorted()
    }

    /// Library paths only, for the palette's file fuzzy-open (§10.3).
    var libraryPaths: [String] {
        markdownPaths.filter { $0.hasPrefix("library/") }
    }

    func url(forRelativePath path: String) -> URL {
        folder.root.appending(path: path)
    }

    // MARK: - Refreshing

    /// Rescans when a watcher reported activity, or when the last scan is old enough
    /// that a change in an unwatched subfolder could have been missed.
    func refreshIfNeeded(now: Date = Date()) async {
        guard isStale || now.timeIntervalSince(lastScan) > SearchIndex.freshnessWindow else { return }
        await refresh(now: now)
    }

    func refresh(now: Date = Date()) async {
        guard !isRefreshing else { return }
        isRefreshing = true
        isStale = false
        lastScan = now
        defer { isRefreshing = false }

        let root = folder.root
        let previous = store
        let next = await Task.detached(priority: .utility) {
            SearchIndexBuilder.scan(root: root, previous: previous)
        }.value

        store = next
        fileCount = next.files.count
        save(next)
    }

    // MARK: - Querying

    func search(_ query: String, limit: Int = 60, calendar: Calendar = .current) -> [SearchResult] {
        SearchQuery.run(query, over: Array(store.files.values), calendar: calendar, limit: limit)
    }

    func text(forRelativePath path: String) -> String? {
        store.files[path]?.text
    }

    // MARK: - Persistence

    /// `~/Library/Application Support/PeteKM/SearchIndex/<digest>.json` — outside the
    /// PeteKM folder, so a user's notes folder never carries app state (§5.8).
    nonisolated static func indexFileURL(for folder: PeteKMFolder) -> URL {
        let support = (try? FileManager.default.url(for: .applicationSupportDirectory,
                                                    in: .userDomainMask,
                                                    appropriateFor: nil,
                                                    create: false))
            ?? URL(filePath: NSTemporaryDirectory(), directoryHint: .isDirectory)

        let digest = SHA256.hash(data: Data(folder.root.path(percentEncoded: false).utf8))
        let name = digest.map { String(format: "%02x", $0) }.joined().prefix(16)

        return support
            .appending(path: "PeteKM", directoryHint: .isDirectory)
            .appending(path: "SearchIndex", directoryHint: .isDirectory)
            .appending(path: "\(name).json")
    }

    private func loadFromDisk() {
        guard let data = try? Data(contentsOf: cacheURL),
              let decoded = try? JSONDecoder().decode(SearchIndexStore.self, from: data)
        else { return }
        store = decoded
        fileCount = decoded.files.count
    }

    private func save(_ store: SearchIndexStore) {
        let url = cacheURL
        Task.detached(priority: .utility) {
            guard let data = try? JSONEncoder().encode(store) else { return }
            try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                     withIntermediateDirectories: true)
            try? data.write(to: url, options: [.atomic])
        }
    }

    // MARK: - Watching

    /// Anything the app, VS Code, or an agent writes marks the index stale; the next
    /// search picks the change up (§8.5).
    private func startWatching() {
        let targets = [folder.root, folder.daily, folder.library]
        watchers = targets.compactMap { url in
            guard FileWriting.isDirectory(url) else { return nil }
            return DirectoryWatcher(url: url) { [weak self] in
                Task { @MainActor [weak self] in self?.isStale = true }
            }
        }
    }
}
