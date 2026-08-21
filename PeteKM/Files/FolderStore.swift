//
//  FolderStore.swift
//  PeteKM
//
//  Holds the active PeteKM folder and persists access to it across launches
//  (spec §19.6, §20.1). The App Sandbox is off, but bookmark discipline stays:
//  access is granted once by the user and re-resolved from a saved bookmark —
//  the app never assumes ambient access to anywhere else.
//

import Foundation
import Observation

@Observable
final class FolderStore {

    enum State: Equatable {
        /// No folder chosen yet — first run.
        case unset
        /// Folder resolved and reachable.
        case ready(PeteKMFolder)
        /// Configured, but unreachable right now (§19.6).
        case missing(lastKnownPath: String)
    }

    private(set) var state: State = .unset

    var folder: PeteKMFolder? {
        if case .ready(let folder) = state { return folder }
        return nil
    }

    var lastKnownPath: String? {
        switch state {
        case .missing(let path): return path
        case .ready(let folder): return folder.root.path(percentEncoded: false)
        case .unset: return defaults.string(forKey: Keys.path)
        }
    }

    private enum Keys {
        static let bookmark = "petekm.folderBookmark"
        static let path = "petekm.folderPath"
    }

    private let defaults: UserDefaults
    private var accessedURL: URL?

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        state = resolveStoredFolder()
    }

    deinit {
        accessedURL?.stopAccessingSecurityScopedResource()
    }

    // MARK: - Selection

    /// Adopt a folder the user just chose, persisting access for next launch.
    func setFolder(_ url: URL) {
        releaseAccess()
        persistBookmark(for: url)
        defaults.set(url.path(percentEncoded: false), forKey: Keys.path)
        state = .ready(PeteKMFolder(root: url.standardizedFileURL))
    }

    /// Forget the configured folder entirely (used by re-onboarding).
    func clear() {
        releaseAccess()
        defaults.removeObject(forKey: Keys.bookmark)
        defaults.removeObject(forKey: Keys.path)
        state = .unset
    }

    /// Re-check reachability — e.g. after a drive is reconnected.
    func revalidate() {
        state = resolveStoredFolder()
    }

    // MARK: - Reachability

    static func isReachable(_ url: URL) -> Bool {
        FileWriting.isDirectory(url) && FileManager.default.isWritableFile(atPath: url.path(percentEncoded: false))
    }

    // MARK: - Private

    private func resolveStoredFolder() -> State {
        let storedPath = defaults.string(forKey: Keys.path)

        if let data = defaults.data(forKey: Keys.bookmark),
           let url = resolveBookmark(data) {
            if FolderStore.isReachable(url) {
                beginAccess(url)
                defaults.set(url.path(percentEncoded: false), forKey: Keys.path)
                return .ready(PeteKMFolder(root: url))
            }
            return .missing(lastKnownPath: url.path(percentEncoded: false))
        }

        // Bookmark gone or unresolvable, but we know where it used to be.
        if let storedPath, !storedPath.isEmpty {
            let url = URL(filePath: storedPath, directoryHint: .isDirectory)
            if FolderStore.isReachable(url) {
                persistBookmark(for: url)
                beginAccess(url)
                return .ready(PeteKMFolder(root: url.standardizedFileURL))
            }
            return .missing(lastKnownPath: storedPath)
        }

        return .unset
    }

    private func resolveBookmark(_ data: Data) -> URL? {
        var stale = false
        if let url = try? URL(
            resolvingBookmarkData: data,
            options: [.withSecurityScope],
            relativeTo: nil,
            bookmarkDataIsStale: &stale
        ) {
            if stale { persistBookmark(for: url) }
            return url.standardizedFileURL
        }
        // Bookmarks made without security scope (or on a system that refused
        // the scoped variant) still resolve fine with the app unsandboxed.
        if let url = try? URL(
            resolvingBookmarkData: data,
            options: [],
            relativeTo: nil,
            bookmarkDataIsStale: &stale
        ) {
            return url.standardizedFileURL
        }
        return nil
    }

    private func persistBookmark(for url: URL) {
        let scoped = try? url.bookmarkData(options: [.withSecurityScope],
                                           includingResourceValuesForKeys: nil,
                                           relativeTo: nil)
        let data = scoped ?? (try? url.bookmarkData(options: [],
                                                    includingResourceValuesForKeys: nil,
                                                    relativeTo: nil))
        if let data {
            defaults.set(data, forKey: Keys.bookmark)
        }
    }

    private func beginAccess(_ url: URL) {
        if url.startAccessingSecurityScopedResource() {
            accessedURL = url
        }
    }

    private func releaseAccess() {
        accessedURL?.stopAccessingSecurityScopedResource()
        accessedURL = nil
    }
}
