# Implementation Plan: PeteKM on iPhone

Source: `context/ios/spec.md` (cited below as §N). Sync v2 references are written
`v2 §N` and point at `context/sync-v2/spec.md`.

## Progress

- [x] **Phase 0** — Mac only: baseline snapshot + push-race retry (§13.2). Ships as a Mac release before any phone code
- [ ] **Phase 1** — Shared code + iOS target skeleton (Mac unchanged, tests green)
- [ ] **Phase 2** — Sync core, pure: hashing, scope, manifest, line diff, union merge, merge planner
- [ ] **Phase 3** — GitHub client + `PhoneSyncEngine`, with fake and git-backed test remotes
- [ ] **Phase 4** — iOS connect flow, Keychain, `PhoneSync` coordinator, first download
- [ ] **Phase 5** — Today screen: editor port, Daily Sticky, New Day, status light, notices
- [ ] **Phase 6** — Library browser, read-only/Edit, search
- [ ] **Phase 7** — Settings, Mac copy changes, background refresh, docs, TestFlight

Each phase leaves both apps building and every existing test passing. The Mac app's only
behavior change is the push-race fix in Phase 0 (§13.2). The copy changes in §13.3 are
opt-in and happen only if Pete says yes.

---

## Mac regression gate (run at the end of every phase)

The Mac app is the product. A phase is not done until all of this passes. Record results
in the phase's PR or commit message.

1. **Tests:** `xcodebuild -scheme PeteKM test` green. The count of passing tests is at
   least the Phase 0 baseline plus the tests the phase added. No existing test was edited,
   except those named in the phase.
2. **Source compatibility:** `git diff` of `PeteKMTests/` shows no changes to existing
   tests (only additions), except named ones.
3. **Build output:** `scripts/release.sh`-style Release archive (no notarization:
   `xcodebuild -scheme PeteKM -configuration Release archive`) and compare with the Phase 0
   baseline:
   - the `.app` file list (`find PeteKM.app -type f | sort`), ignoring the executable's
     bytes,
   - `Info.plist` (`plutil -p`), entitlements (`codesign -d --entitlements -`),
   - linked libraries (`otool -L`), Sparkle still embedded.
   Any difference must be explained by the phase.
4. **Scheme isolation:** `xcodebuild -scheme PeteKM -showBuildSettings | grep SDKROOT` is
   `macosx` only; the `PeteKM` scheme's build list contains only `PeteKM` (+ tests).
5. **Defaults:** a Mac with existing `UserDefaults` (`com.petekm.PeteKM`) launches with the
   same settings: start behavior, headers, fonts, colors, shortcut, sync toggle.
6. **Smoke (manual, 5 min):** launch, today's sticky opens, type, autosave, ⌘K palette,
   search, open a Library file, Scratch pane, Sync Now, hide/summon, menu bar status.
7. **From Phase 3 on:** the sync v2 two-Mac checklist items 1–3 (`context/sync-v2/plan.md`)
   pass, plus the Mac-side items in this plan's manual checklist.

---

## Ground rules for every phase

- **Mac first, always green.** The gate above passes at the end of every phase. Moving a
  file to `Shared/` must not change Mac behavior, type names, signatures, or defaults.
- **No Mac file edits outside the list.** Each phase names the Mac files it may touch.
  Anything else needs a reason written in the commit.
- **Capture never blocks** (§3.3). No path may delay opening, typing into, or saving a
  Daily Sticky beyond the 3s Pre-New-Day budget.
- **Never force.** Every ref update uses `force: false`. No code path anywhere sends
  `force: true`. Add a test that inspects every request the engine sends.
- **No disk write before the network is done.** Downloads first, then one synchronous
  main-actor apply right after a flush (§8.1 step 5).
- **Content hashes, not timestamps,** decide every sync action (§6.3).
- **Tokens never in logs.** `URLSessionGitHubAPI` redacts `Authorization` from any
  error text kept for Details….
- Copy is verbatim from the spec. Vocabulary per DESIGN §2 (Daily Sticky, Library, PeteKM).
- Tests: Swift Testing (`@Test`, `#expect`). Engine tests use fakes; no live GitHub in CI.
  One optional live test is gated behind `PETEKM_LIVE_GITHUB_TOKEN` + `PETEKM_LIVE_REPO`
  and skipped by default.

---

## Phase 0 — Mac baseline + push-race retry

**Goal:** lock down what "unchanged" means for the Mac, then fix the one Mac behavior the
phone would make worse. Mac-only; no iOS code.

**Mac files touched:** `PeteKM/Files/GitSupport.swift`, `PeteKMTests/GitSyncTests.swift`
(additions only), `PeteKM.xcodeproj` (scheme sharing only).

### 0.1 Baseline

- Share the existing `PeteKM` scheme (Xcode → Manage Schemes → Shared), so it lives in
  `PeteKM.xcodeproj/xcshareddata/xcschemes/PeteKM.xcscheme` and can't be regenerated
  differently once a second target exists. Verify the shared scheme builds the same
  targets as the auto-created one.
- Run the full test suite and record the passing test count in `context/ios/baseline.md`.
- Release-archive the Mac app and record, in the same file: the `.app` file list,
  `plutil -p Info.plist`, entitlements, `otool -L`. Keep the archive outside the repo.
- Record a snapshot of `MarkdownSyntaxHighlighter` output (attribute runs: range, font
  name, point size, traits, color) for a fixture sticky covering every style, as a new test
  fixture `PeteKMTests/Fixtures/highlighter-baseline.json` with a test that compares
  against it. This guards Phase 1.5.

### 0.2 Push-race retry (§13.2)

- In `GitSupport`'s v2 sequence, step 7: if the push fails and `RunInvoker.stderr` for
  that push contains `[rejected]` together with `(fetch first)` or `(non-fast-forward)`,
  run once more: guard → fetch → (if behind) flush + commit → rebase under the marker with
  the union attribute → reconcile → push. Reuse the existing step-6 code by extracting it
  into a function, so there is one rebase path, not two.
- Respect the deadline: if the sleep/quit deadline has passed, don't start the retry; end
  `.pushFailed` as today.
- No change to any other outcome, notice, or `AutoSync` timing.

### 0.3 Tests (additions to `GitSyncTests`)

- Race: clone C pushes after clone A's fetch and before A's push (runner hook) → A ends
  `.synced`, history contains both, no `--force` in any invocation, union applied when the
  same day changed.
- Auth-style failure (remote URL made unwritable) → `.pushFailed`, exactly one push attempt.
- Deadline passed → no retry.
- Existing `GitSyncTests` / `AutoSyncTests` unchanged and green.

### 0.4 Done when

Regression gate passes. Ship as a normal Mac release (1.1.2) through `scripts/release.sh`
and run on both Macs for a few days before Phase 1 starts.

---

## Phase 1 — Shared code + iOS target skeleton

**Goal:** a `Shared/` folder compiled into both apps, the seams that let `DailySession`
run on iOS, and an empty iOS app that launches. No sync, no features.

**Mac files touched:** the moved files (path only), `DailySession.swift` (seams),
`AutoSync.swift` (conformance; `SyncStatus` moved out), `AppSettings.swift` (conformance;
`DailyStartBehavior` moved out), `MarkdownSyntaxHighlighter.swift` (typealiases),
`SyncStatusCopy.swift` (`deviceNoun` with default), `SearchIndex.swift` (base-directory
parameter with default), `project.pbxproj`.

### 1.1 Project structure

- Do the pbxproj work in Xcode, not by hand, then review the diff: the Mac target's build
  settings, build phases, package dependencies (Sparkle), and entitlements must not change.
- **`Shared/` must not be a member of `PeteKMTests`.** Tests see it through
  `@testable import PeteKM`. Making it a test-target member would compile every shared type
  twice and break the build with ambiguous types.
- The iOS target has its own `MARKETING_VERSION` / `CURRENT_PROJECT_VERSION`. Mac version
  bumps (the "Bump Debug version" commits) edit only the `PeteKM` target's configurations.
  Add that note to `context/DISTRIBUTION.md`.
- Create `Shared/` at the repo root as a file-system-synchronized group (same mechanism as
  the existing `PeteKM/` group in `project.pbxproj`). Member of `PeteKM`, `PeteKMiOS`.
  `PeteKMTests` keeps `@testable import PeteKM`, which sees `Shared/` through the Mac target.
- Add target `PeteKMiOS`: iOS app, SwiftUI lifecycle, deployment iOS 26.0, iPhone + iPad,
  product name `PeteKM`, bundle id `com.petekm.PeteKM.ios`, team `A2T9Q78M27`,
  `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`, `SWIFT_APPROACHABLE_CONCURRENCY = YES`,
  `SWIFT_VERSION` matching the Mac target. Its own synced folder `PeteKMiOS/`.
- Add target `PeteKMiOSTests` (Swift Testing, iOS simulator), host app `PeteKMiOS`.
- Add scheme `PeteKMiOS`. Keep scheme `PeteKM` unchanged.
- App icon: reuse the pixel mark source from `context/design-system/` in an iOS
  `AppIcon` set. No new branding.

### 1.2 Move files to `Shared/` (no edits beyond the seams below)

Move with `git mv` so history follows:

- `Files/PeteKMFolder.swift`, `Files/FileWriting.swift`, `Files/DirectoryWatcher.swift`
- `Daily/DailyDate.swift`, `Daily/DailyFiles.swift`, `Daily/DailySession.swift`,
  `Daily/StickyDocument.swift`, `Daily/NewDayComposer.swift`,
  `Daily/MarkdownHeadings.swift`, `Daily/NoticeBoard.swift`
- `Editor/EditorEdits.swift`, `Editor/MarkdownOutline.swift`, `Editor/CursorMemory.swift`,
  `Editor/MarkdownSyntaxHighlighter.swift`
- `Search/SearchIndex.swift`, `Search/SearchQuery.swift`, `Search/FuzzyMatch.swift`
- `Files/SyncStatusCopy.swift`, and `SyncStatus` moved out of `Files/AutoSync.swift` into
  `Shared/SyncStatus.swift`

Check every moved file builds for iOS. Known blockers and their fixes are 1.3–1.6.

### 1.3 `NewDaySyncing` seam (§12.2)

```swift
@MainActor protocol NewDaySyncing: AnyObject {
    func canDeferNewDay(in folder: PeteKMFolder) -> Bool
    /// Runs an arrival sync. True when it brought changes in.
    func requestNewDay() async -> Bool
    var newDayBudget: Duration { get }
}
```

- `AutoSync` conforms: `requestNewDay()` is exactly `await request(.newDay)?.didBringIn == true`;
  `newDayBudget` is `.seconds(Timing.newDayBudget)`. `request(.newDay)` itself is untouched.
- `DailySession.init` keeps its labels: `init(folder:settings:autoSync:newDayBudget:calendar:now:)`
  with `autoSync: (any NewDaySyncing)? = nil` and `newDayBudget: Duration? = nil`. The
  effective budget is `newDayBudget ?? autoSync?.newDayBudget ?? .seconds(2)`. The
  existing calls in `DailyStickyTests` (lines ~768–846, which pass `autoSync:` and
  sometimes `newDayBudget:`) compile and behave as written.
- `attach(_:)` takes `any NewDaySyncing`; `AutoSync`'s `session.attach(self)` is unchanged.
- `finishDeferral` reads the `Bool` where it read `run?.didBringIn`.
- Add `canPrune: (URL) -> Bool = { _ in true }` to the init (last parameter, defaulted).
  `pruneIfBlank` adds `canPrune(document.url)` to its guard. The Mac passes nothing.
- New test: a `DailySession` built with no `canPrune` prunes exactly as before (existing
  prune tests cover it); one built with `{ _ in false }` never deletes.

### 1.4 `DailyPreferences` seam

- Move the `DailyStartBehavior` enum (with its titles and captions) from `AppSettings.swift`
  to `Shared/DailyPreferences.swift`, plus:
  ```swift
  @MainActor protocol DailyPreferences: AnyObject {
      var dailyStartBehavior: DailyStartBehavior { get }
      var defaultHeaders: String { get }
      var showDateHeading: Bool { get }
  }
  ```
- `AppSettings: DailyPreferences`. `DailySession` takes `any DailyPreferences`.

### 1.5 Cross-platform highlighter (§12.3)

- `Shared/Platform.swift`: `typealias PlatformFont = NSFont` / `UIFont`,
  `PlatformColor = NSColor` / `UIColor`, label color accessors, and
  `PlatformFont.adding(_ trait:)`.
- **macOS branch of `adding(_:)` is literally `NSFontManager.shared.convert(self, toHaveTrait:)`**
  with the same trait masks as today. The font-descriptor code exists only under
  `#if canImport(UIKit) && !os(macOS)`. Mac fonts are therefore produced by the same API
  calls as 1.1.1.
- `MarkdownStyle.textColor` is `PlatformColor?`, which is `NSColor?` on the Mac, so
  `AppSettings` and `SettingsTests` compile unchanged.
- **Check:** `EditorTests` pass unchanged, and the Phase 0 highlighter snapshot test passes
  byte-for-byte. Visually compare a Mac sticky with headings, bold, italic, code, list, quote
  before and after.

### 1.6 Device noun in copy

- `SyncStatusCopy` gains `deviceNoun: String` (default `"Mac"`) used in "only on this
  <noun>". Mac call sites pass nothing. `SyncStatusTests` unchanged and green.
- `SearchIndex` cache location: take a base directory parameter (Mac: Application Support,
  as today; iOS: Caches). Default keeps today's Mac path.

### 1.7 Skeleton iOS app

- `PeteKMiOS/PhoneApp.swift` showing a placeholder "PeteKM" view with the pixel mark.

### 1.8 Done when

- Mac regression gate passes. Build-output comparison shows **no** differences from the
  Phase 0 baseline apart from the executable's bytes.
- `git diff --stat PeteKMTests/` shows only additions.
- `xcodebuild -scheme PeteKM test` green.
- `xcodebuild -scheme PeteKMiOS -destination 'platform=iOS Simulator,name=iPhone 17' build` succeeds.
- `CLAUDE.md` build section lists the iOS commands.

---

## Phase 2 — Sync core (pure)

**Goal:** every decision the engine makes, as pure tested functions in `Shared/Sync/`. No
networking.

### 2.1 `GitBlobHash`

- `static func sha(of data: Data) -> String` = hex SHA-1 of `"blob \(data.count)\0" + data`
  (CryptoKit `Insecure.SHA1`).
- Tests compare against `git hash-object --stdin` for: empty, ASCII, multi-byte UTF-8,
  CRLF, no trailing newline, 1 MB random bytes.

### 2.2 `MirrorScope` (§6.1)

- `static func includes(path: String, mode: String, size: Int?) -> Bool`.
- `static func isDaily(_ path: String) -> Bool` (used by the planner for union vs copy).
- Tests: `daily/2026/11/2026-11-26.md` ✓, flat `daily/2026-11-26.md` ✓,
  `library/a/b.md` ✓, `INDEX.md` ✓, `library/x.png` ✗, `CLAUDE.md` ✗,
  `.claude/skills/x/SKILL.md` ✗, `library/.hidden/a.md` ✗, `100755` ✓, `120000` ✗,
  `160000` ✗, size 2 MB + 1 ✗.

### 2.3 `SyncManifest` (§6.2)

- `Codable` struct; `load(from:)` returns `nil` on missing/corrupt/version-mismatch;
  `save(to:)` uses `FileWriting.writeAtomically`.
- `LocalSnapshot.scan(folder:) -> [String: String]` hashing every in-scope file on disk
  (relative path → blob sha), skipping hidden components and files over the size limit.

### 2.4 `LineDiff` + `UnionMerge` (§8.3)

- Lines split keeping their terminators (`"\n"`, `"\r\n"`, or none on the last line), so
  output bytes reproduce input endings exactly.
- `LineDiff.diff(_ a: [Line], _ b: [Line]) -> [Hunk]`: Myers O(ND).
- `UnionMerge.merge(base:remote:local:) -> String`: diff3 walk over base→remote and
  base→local hunks. Non-overlapping hunks apply. Overlapping hunks with identical
  replacement apply once. Overlapping different hunks emit **remote lines, then local
  lines**.
- If a side's last line lacks a newline and more lines follow it in the output, add `"\n"`
  so lines never fuse.
- Tests:
  - fixtures (append both sides; edit same line both sides; one side deletes a line the
    other edits; add/add with empty base; identical edits; whitespace-only change),
  - **parity** with `git merge-file --union -p <remote> <base> <local>` (current = remote,
    so remote lines come first) on every fixture,
  - **property:** 500 seeded random edit scripts, assert every line of remote and local
    survives except removals both sides agree on.

### 2.5 `MergePlanner` (§8.2, §8.6)

- Input: `base: [String: String]`, `local: [String: String]`, `remote: [String: String]`
  (path → sha), `downloaded: Set<String>`.
- Output: `[PlanStep]` with cases `.adopt`, `.writeRemote(path)`, `.deleteLocal(path)`,
  `.download(path)`, `.keepLocal(path)`, `.union(path, baseSha?)`,
  `.conflictCopy(path)`, `.restoreRemote(path)`.
- `blobsNeeded(for:)` lists remote and base blobs to fetch.
- One test per table row in §8.2, plus manifest-lost (all base absent) behaving per §8.6.

### 2.6 Done when

All Phase 2 tests green in `PeteKMTests`; nothing in the apps calls this code yet.

---

## Phase 3 — GitHub client + `PhoneSyncEngine`

**Goal:** a complete, tested sync engine that runs on macOS in tests against fake and
real-git remotes. Still no iOS UI.

### 3.1 `GitHubAPI` protocol (`Shared/Sync/GitHubAPI.swift`)

```swift
protocol GitHubAPI: Sendable {
    func repository() async throws -> RepoInfo                       // permissions.push, default_branch
    func headRef(etag: String?) async throws -> RefResult            // .notModified | .head(sha, etag)
    func commit(_ sha: String) async throws -> CommitInfo            // tree, parents
    func tree(_ sha: String) async throws -> [TreeEntry]             // handles truncated (§7.3)
    func blob(_ sha: String) async throws -> Data
    func createTree(base: String, entries: [TreeChange]) async throws -> String
    func createCommit(message: String, tree: String, parent: String) async throws -> String
    func moveBranch(to sha: String) async throws -> MoveResult       // .moved | .notFastForward
    func recentCommitDevices(limit: Int) async throws -> [(device: String, at: Date)]
}
enum GitHubError: Error { case offline, authFailed, rateLimited(until: Date), failed(String) }
```

- `TreeChange`: `.text(path, String, mode)`, `.binary(path, blobSha, mode)`. There is
  deliberately **no delete case**, so the type system enforces §8.8.
  UTF-8-decodable files use inline `content`; anything else uploads a blob first.

### 3.2 `URLSessionGitHubAPI`

- Headers per §7.1. 15s request timeout. Ephemeral `URLSession` configuration (no disk
  cache; ETag is handled by the manifest).
- Status mapping per §7.4. Rate-limit detection reads `x-ratelimit-remaining`,
  `x-ratelimit-reset`, and `retry-after`.
- `moveBranch` maps `422` to `.notFastForward`.
- Truncated tree fallback: walk `daily/` and `library/` subtrees.
- Unit-tested with a `URLProtocol` stub: header presence, token redaction in errors, each
  status mapping, ETag round-trip, truncated fallback.

### 3.3 `FakeGitHub` (test-only)

In-memory object store with real semantics: blobs/trees/commits keyed by their git SHA
(compute real tree SHAs so tests catch encoding mistakes), a branch ref with fast-forward
check, request counting, and fault injection (offline on call N, 401, rate limit, 422 race
where another "device" pushes between `createCommit` and `moveBranch`).

### 3.4 `LocalGitHub` (test-only, macOS)

`GitHubAPI` backed by a local bare repo through git plumbing:
`rev-parse`, `cat-file -p`, `ls-tree -r -l`, `hash-object -w --stdin`, `mktree`,
`commit-tree -p`, and `update-ref refs/heads/main <new> <old>` (atomic compare-and-swap,
like `force: false`). Device trailers read with `git log --format`. This lets a real Mac
clone (`GitSupport` sync v2 engine) and the phone engine share one remote in tests.

### 3.5 `PhoneSyncEngine` (§8.1)

- `actor PhoneSyncEngine` holding `api`, `folder`, manifest path, device name, clock.
- `func run(flush: @MainActor () -> Void, apply: @MainActor ([AppliedChange]) -> Void) async -> PhoneSyncRun`
  - `flush` saves the open document; `apply` lets the host reconcile the open document
    and post notices. Both closures are injected so the sequence stays testable (same
    pattern as `GitSupport`'s v2 sequence).
  - Disk writes in step 5e happen inside a `@MainActor` hop, after a second flush, in one
    synchronous pass.
- `PhoneSyncRun`: `outcome` (`.synced`, `.pending`, `.offline`, `.authFailed`,
  `.rateLimited(until:)`, `.failed(String)`), `didBringIn`, `incomingDevice`,
  `unionMerged: [String]`, `conflictCopies: [(original, copy)]`, `pushed: Bool`.
- Push retry: up to 3 non-fast-forward attempts per run.
- Commit message per §8.7. Subject formatter shared with `GitSupport` (extract
  `GitSupport.commitSubject(for:)` to `Shared/` if it isn't already pure).
- First-download mode (§9.3): when many `.download` steps exist, order them, cap
  parallelism at 6, save the manifest every 25 files, and report progress through an
  `AsyncStream<DownloadProgress>`.

### 3.6 Engine tests (against `FakeGitHub`)

- Fresh connect → every in-scope file downloaded, out-of-scope never requested.
- No changes → exactly one request (the ref, `304`).
- Local edit → one commit whose tree differs from base only at that path; out-of-scope
  files preserved; trailer present; `force` never sent.
- Remote edit → file written, manifest advanced, open-document `apply` called.
- Both edit today's sticky → union merge written and pushed; notice data populated.
- Both edit a Library note → conflict copy + original = remote, both pushed.
- 422 race → re-merge, second push succeeds, no lost lines.
- Crash after `moveBranch` before manifest save → next run converges with zero writes.
- Crash mid-apply (inject a throw after k writes) → next run converges.
- Offline at each step → no local file touched, outcome `.offline`.
- 401 → `.authFailed`; rate limit → `.rateLimited(until:)`, no further requests.
- Manifest deleted → §8.6 recovery, nothing lost.
- **Never deletes:** across every test, assert no `createTree` request contains a deletion
  entry and no request carries `force`.
- In-manifest file missing on disk → restored from remote, nothing pushed for it.
- Never-synced blank sticky pruned locally → nothing pushed, nothing restored.
- Mode preserved: editing a `100755` file keeps `100755` in the new tree.
- Out-of-scope paths (agent files, image, `.gitattributes`) are byte-identical in the new
  tree after every push.
- NFD-named Library file on disk → matched to its NFC tree path, not pushed as new.
- Bytes round-trip: CRLF file, no-trailing-newline file, and BOM file come back from a
  download → edit-free push unchanged (no commit at all, since hashes match).

### 3.7 Mac ↔ phone end-to-end (against `LocalGitHub` + a real Mac clone)

Using the existing `GitSyncTests` helpers (bare origin + clones):

1. Phone writes today → Mac `GitSupport` sync → Mac's file equals phone's.
2. Mac writes and pushes → phone run → phone file equals Mac's, `incomingDevice` = Mac name.
3. Both append to the same day "offline", phone pushes first → Mac rebases with union →
   phone pulls → **both folders byte-identical**, all lines present.
4. Same, Mac pushes first → phone union-merges → Mac pulls → identical.
5. Both edit the same Library line → phone makes a conflict copy; Mac pulls without
   pausing; both folders identical.
6. Mac `DailyFiles.organize` moves a flat sticky → phone follows the move.
7. Agent-file and image changes on the Mac → phone never downloads them; phone pushes never
   delete them.
8. **Mac open document:** a Mac `DailySession` has today's sticky open (clean) while the
   phone pushes an edit to it → Mac sync reconciles silently, no conflict alert, text equals
   the phone's. Same with the Mac document dirty → the existing Keep Mine / Keep Disk /
   Keep Both conflict appears, nothing lost (today's behavior).
9. **Race (needs Phase 0):** the phone pushes between the Mac's fetch and push → the Mac
   run still ends `.synced`, not `.pushFailed`.
10. **Phone blank sticky:** the Mac pushed a blank today's sticky; the phone opens and leaves
    it → the phone pushes nothing, and the Mac's file is never deleted under it.
11. After every scenario: `git -C <mac clone> status --porcelain` is empty, no rebase in
    progress, no `.git/petekm-rebase` marker left behind, and `git fsck` on the bare repo is
    clean.

### 3.8 Done when

All Phase 3 tests green. The engine is complete; only the iOS host is missing.

---

## Phase 4 — Connect flow, Keychain, coordinator, first download

**Goal:** on a real iPhone, connect to the repo and download it. Today's sticky shows as
plain text (the editor comes in Phase 5).

### 4.1 `KeychainTokenStore`

- `save(token:for:)`, `token(for:)`, `delete(for:)`; attributes per §11.2.
- `PeteKMiOSTests`: round-trip, overwrite, delete, missing → nil.

### 4.2 `PhoneSettings`

- `@Observable`, `UserDefaults`-backed, keys `petekm.ios.*`: `owner`, `repo`, `branch`,
  `deviceName`, `dailyStartBehavior`, `defaultHeaders`, `showDateHeading`, `fontSize`,
  `autoClosePairs`, `continueListMarkers`, `hasConnected`.
- Conforms to `DailyPreferences`.

### 4.3 Connect flow (§11.1)

- Views: Welcome → Repository → Token (with how-to and link) → validation → Device name +
  Daily start → done.
- Validation per §11.1 step 4, with the exact error copy.
- On success: create the local folder (§5), set `isExcludedFromBackup`, save settings,
  store the token, start the first download.

### 4.4 `PhoneSync` coordinator

`@MainActor @Observable final class PhoneSync: NewDaySyncing`:

- Owns `status: SyncStatus` (shared enum, plus phone states), `lastFetchAt`,
  `otherDeviceLast`, `lastError`, `downloadProgress`, one-shot `lastNotice`.
- `request(_ trigger:)` with coalescing (one run in flight + "run again"), back-off per
  §9.5, departure precondition (local changes exist: snapshot differs from manifest,
  cheap because it only hashes files changed since the last scan by size+mtime pre-check).
- Triggers per §9.1: `scenePhase`, a 60s foreground timer, `NWPathMonitor`, edit idle
  (15s; `noteEdit()` called by the editor), background transition wrapped in
  `UIApplication.beginBackgroundTask` with an expiration handler that cancels the run.
- Timing constants in one `PhoneSync.Timing` enum (`foregroundPoll` 60s, `editIdle` 15s,
  `newDayBudget` 3s, `failedRetry` 5 min, `backgroundBudget` 25s).
- Tests (macOS, with `FakeGitHub` and a fake clock): coalescing, back-off states, departure
  without changes does nothing, `requestNewDay` result.

### 4.5 Done when

On a device: connect to the real private repo, watch the progress line, see today's sticky
text, and see the Library files on disk (verify via a debug list view, removed in Phase 6).

---

## Phase 5 — Today screen

**Goal:** daily capture on the phone, synced both ways. This is the MVP.

### 5.1 `PhoneEditor`

- `MarkdownTextView` (`UITextView` subclass, TextKit 2) + `UIViewRepresentable`.
- Styling: `NSTextStorage` delegate (or `NSTextContentStorage` delegate) running
  `MarkdownSyntaxHighlighter.apply` on each edit, same as the Mac's `didProcessEditing` path.
- `EditorEdits` wired in `textView(_:shouldChangeTextIn:replacementText:)` for auto-close and
  list continuation, gated by `PhoneSettings`.
- Accessory bar (§10.2) as an `inputAccessoryView`; every action goes through the text
  view's undo manager.
- Hardware keyboard: `UIKeyCommand`s for Tab, Shift-Tab, ⌘B, ⌘I.
- `isEditable` binding (for read-only Library in Phase 6); `dataDetectorTypes` off.
- `SelectionPreserver` (§8.5): before a silent reload, record the caret offset from the end
  of the common prefix; after, restore. Pure function in `Shared/`, unit-tested.
- Calls `PhoneSync.noteEdit()` on each text change.

### 5.2 `TodayView`

- Header: date title (long form from `DailyDate`), ‹ › buttons, swipe, title tap → date
  sheet with a graphical `DatePicker` (days with a sticky marked), status light.
- Body: `PhoneEditor` bound to `DailySession.document`.
- New Day card for `.ask`, using `DailySession.newDayOptions` and the shared copy.
- Toolbar: Library, Search, Contents (outline menu), Settings.
- Notice line from `NoticeBoard`.
- Conflict alert (Keep Mine / Keep Disk / Keep Both) bound to `StickyDocument.conflict`, the
  same as the Mac. Rare on the phone (§8.1), but kept.
- `scenePhase` → `.active` calls `DailySession.handleActivation()`, then
  `PhoneSync.request(.becameActive)`.
- `DailySession` constructed with `PhoneSync` as its `NewDaySyncing` and
  `newDayBudget: .seconds(3)`.

### 5.3 Status light + sheet (§10.4)

- `StatusLight` view: same colors and pulse rules as the Mac's `SyncStatusDot`. Tap opens a
  sheet with status line, "Last checked GitHub: …", "Last from <device>: …", **Sync Now**,
  **Details…**.
- Copy from `SyncStatusCopy` with `deviceNoun` "iPhone"/"iPad", plus the phone lines in §10.4.

### 5.4 Notices

Route `PhoneSyncRun` to the notice line: "Updated from <device>." (4s), union notices (6s,
§8.3), conflict-copy notice (8s, §8.4), "That note was removed on another device." Manual
Sync always answers ("Synced.", "Already up to date.", or the error line).

### 5.5 Done when

Manual checklist items 1–8 pass on a real phone and Mac.

---

## Phase 6 — Library and search

### 6.1 `LibraryBrowser`

- `NavigationStack` over the local `library/` directory; `INDEX.md` and `INBOX.md` pinned on
  the root list. Folders first, then files, case-insensitive alphabetical. Titles drop `.md`.
- Not-downloaded files (in the remote tree, not in `downloaded`) shown dimmed with "Not
  downloaded yet."; tap downloads that blob through the engine, then opens.
- File view: `PhoneEditor` read-only, live styling. **Edit**/**Done** toolbar toggle.
  Opening goes through `DailySession.open(fileURL:)` so the same document, autosave,
  reconcile, and conflict rules apply.
- Read-only mode: `-> library/…` paths and Markdown links to `library/` files are tappable
  (attribute-based link ranges from a small detector in `Shared/`).
- Pull-to-refresh runs Sync Now.

### 6.2 `SearchView`

- Search field + results list using `SearchIndex` (iOS cache in `Caches/`) and
  `SearchQuery`; filename matches via `FuzzyMatch` in a "Files" section.
- Tap → `DailySession.open(fileURL:reveal:)`; the editor scrolls to and selects the hit.
- "Nothing found." and the still-downloading caption (§10.5).
- Index refresh after every run that brought changes in.

### 6.3 Done when

Manual checklist items 9–13 pass.

---

## Phase 7 — Settings, Mac copy, background refresh, docs, release

### 7.1 iOS Settings (§10.6)

- GitHub section (connected repo, branch, "Connected as <login>", Replace Token…,
  Disconnect with the §11.3 alert and its unsynced-files count).
- Device name, Daily Sticky, Editor, Sync status, About with the §10.7 Guide copy.

### 7.2 Background refresh (§9.4)

- Register `BGAppRefreshTask` `com.petekm.PeteKM.ios.refresh` in `Info.plist`
  (`BGTaskSchedulerPermittedIdentifiers`, background mode `fetch`). Schedule on every
  background transition (earliest begin 30 min). Handler runs an arrival sync with a 25s
  budget and reschedules.

### 7.3 Mac copy changes (§13.3) — opt-in only

Skip unless Pete explicitly says yes. If yes, as its own commit and Mac release:

- Update the two strings in `SyncStatusCopy` / `AutoSync` notices and the Guide paragraph.
- Update exactly the matching expectations in `SyncStatusTests` / `AutoSyncTests`; no other
  test edits.

### 7.4 Docs

- `context/map.md`: new "Targets" section, `Shared/` layer table, iOS layer table, sync-core
  files, `State outside the folder` rows for the phone (local folder, manifest, Keychain,
  Caches index).
- `CLAUDE.md`: iOS build/test commands; note that `Shared/` compiles into both apps.
- `context/ACCEPTANCE.md`: rows for §6.3, §8.2–8.4, §9.2, §11.2 mapped to tests.
- `context/DISTRIBUTION.md`: iOS section (archive, upload, TestFlight internal testing).

### 7.5 Done when

All tests green on both schemes, the full manual checklist passes, and a TestFlight build
installs on the phone.

---

## Manual checklist (real iPhone + two Macs)

Daily Sticky:

1. Fresh connect on the phone → today's sticky is visible within a few seconds, before the
   Library finishes downloading. Typing works during the download.
2. Write on Mac A, hide its window. Open the phone → "Updated from <Mac A>." and the text is
   there.
3. Write on the phone, swipe home. Summon Mac A → "Updated from <device name>." and the text
   is there.
4. Write on the phone, wait 20s without leaving the app. Summon Mac B → text is there.
5. First open of a new day on the phone, after Mac A already started the day → the phone
   adopts Mac A's sticky; no duplicate headings.
6. Airplane mode on the phone, write. Write on Mac A in the same day's sticky. Turn airplane
   mode off and open the app → "Merged today's Daily Sticky from two devices. Check the
   order."; all lines from both present; Mac A pulls the same merged text.
7. Write on the phone and swipe the app away immediately (force-quit within 2s) → reopen,
   text is there; it syncs.
8. Open the phone across midnight → it rolls to the new day, yesterday's text saved.

Library:

9. Browse `library/`, open a note → read-only, styling shown, markers visible.
10. Edit → change a line → Done. Mac pulls the change.
11. Edit the same Library line on the phone (airplane mode) and on Mac A. Reconnect →
    both versions kept as two files, notice shown; Mac A pulls both without pausing.
12. Search a word that appears in a Library note and a past sticky → both found; tap opens
    at the hit.
13. A Library image and `CLAUDE.md` change on the Mac → never appear on the phone; a phone
    edit afterwards leaves them intact on GitHub.

Mac unaffected (with the phone in daily use for a week):

M1. Mac light stays green or yellow in normal use; it never shows "Can't send changes to
    GitHub" unless sign-in or the network is really broken.
M2. Agent files, `.gitattributes`, images in `library/` are unchanged on GitHub
    (`git log --stat` on the Mac shows phone commits touching only `.md` files in
    `daily/`, `library/`, `INDEX.md`, `INBOX.md`).
M3. No phone commit deletes a file (`git log --diff-filter=D --format=%B | grep PeteKM-Device`
    shows no phone device name).
M4. `/petekm-process` in a terminal on the Mac runs as before while the phone is in use.
M5. Mac Settings, fonts, colors, shortcut, Scratch, and search behave as before.

Failure paths:

14. Revoke the token on GitHub → status red, "Can't sign in to GitHub. Replace the token in
    Settings."; writing still works; Replace Token… recovers and pushes the backlog.
15. Disconnect with unsynced changes → alert shows the file count and offers Sync Now.
16. Delete the app's manifest (debug menu) → next run recovers per §8.6; nothing lost.
