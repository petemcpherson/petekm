# Implementation Plan: Sync v2 — Automatic Sync Across Devices

Source: `context/sync-v2/spec.md` (cited below as §N). v1 references are written `v1 §N`
and point at `context/sync/spec.md`.

## Progress

- [x] **Phase 1** — Hardened git engine (process env/timeouts/stderr, guards, v2 run sequence, trailer)
- [x] **Phase 2** — Daily union merge (`.gitattributes`) + `syncAutomatically` setting
- [x] **Phase 3** — `AutoSync` coordinator: triggers, coalescing, back-off, `SyncStatus`
- [x] **Phase 4** — Pre-New-Day: deferred first write of today's Daily Sticky
- [ ] **Phase 5** — Visibility: dot + popover, menu bar, Settings, notices, quit alert, Guide, docs

Each phase leaves the app shippable. Manual Sync keeps working after every phase; automatic
behavior only switches on at the end of Phase 3.

---

## Ground rules for every phase

- **Capture never blocks** (§3.2). No new code path may delay opening, typing into, or
  saving a Daily Sticky beyond the 2s Pre-New-Day budget in Phase 4.
- **One engine** (§3.1). Manual Sync, every trigger, and the sleep/quit paths all call the
  same `GitSupport` run sequence. Triggers only decide *when*.
- **Never delete a lock file. Never force-push.** PeteKM never aborts a rebase it didn't
  start; it aborts only its own marked rebase (§6.4).
- Git work runs off the main actor (`Task.detached(priority: .utility)`). Only flush and
  reconcile hop to the main actor (§6.7).
- Copy is used verbatim from §8.3 / §8.4. No git words in user-facing strings.
- Tests: Swift Testing (`@Test`, `#expect`) in `PeteKMTests`, using real temporary git
  repositories with `file://` remotes. No network.

---

## Phase 1 — Hardened git engine

**Goal:** `GitSupport` can run unattended safely and implements the §6.1 sequence. Manual
Sync switches to it. No triggers yet.

### 1.1 Process hardening in `GitSupport.run` (§6.7)

- [x] Add a `GitResult` value: `status: Int32`, `stdout: String`, `stderr: String`,
      `timedOut: Bool`. Keep the existing `run(_:in:) -> String?` as a thin wrapper so
      current callers (`SyncLaunchCheck`, Settings, `initializeRepository`) are unchanged.
- [x] Add `runDetailed(_:in:timeout:) -> GitResult`:
  - Environment = `ProcessInfo.processInfo.environment` plus
    `GIT_TERMINAL_PROMPT=0` and
    `GIT_SSH_COMMAND="ssh -o BatchMode=yes -o ConnectTimeout=10"`.
    Keep `HOME` and `PATH` intact (credential helpers, SSH agent).
  - Read stdout **and** stderr concurrently (two `readabilityHandler`s or a
    `DispatchGroup`), so a full stderr pipe can't deadlock the process.
  - Timeout: schedule `process.terminate()` after the budget; if still running 1s later,
    send `SIGKILL`. Return `timedOut = true`.
- [x] `GitSupport.Timeouts`: `network = 30s` (fetch, push), `local = 15s` (everything else).
      The sleep path passes an overall deadline instead (see 1.4).
- [x] Testability seam: a `GitRunner` protocol (`func run(_ args: [String], in: URL, timeout: Duration) -> GitResult`)
      with a `ProcessGitRunner` default. The sequence in 1.4 takes a runner so the
      coordinator tests in Phase 3 can use a fake.

### 1.2 Guards (§6.4)

- [x] `GitSupport.busyReason(_ folder:) -> BusyReason?` checks `.git/` for `index.lock`,
      `rebase-merge/`, `rebase-apply/`, `MERGE_HEAD`, `CHERRY_PICK_HEAD`.
      Returns the oldest mtime too, so the caller can detect a stale lock (> 10 min).
- [x] PeteKM's own rebase marker `.git/petekm-rebase`:
  - Written immediately before step 6b, removed immediately after (success or abort).
  - If `rebase-merge/` (or `rebase-apply/`) exists **and** the marker exists:
    run `git rebase --abort`, remove the marker, continue the run.
  - If a rebase exists without the marker: outcome `.busy`.
- [x] Add `case busy` and `case stuck` to `SyncOutcome`. Both are internal and never shown
      as a notice (§10.2). `stuck` (lock older than 10 min) feeds
      `SyncStatus.failing(.lock)` in Phase 3, which surfaces through the dot and status
      line instead. Make `notice(editorName:)` return `String?` (nil for both) and update
      its callers.
- [x] `SyncOutcome.manualNotice(editorName:) -> String` for manual runs (§5.5): `.busy` →
      `GitSupport.busyLine`, `.stuck` → `GitSupport.stuckLine`, else the v1 notice.

### 1.3 Device trailer (§6.3)

- [x] `GitSupport.deviceName`: `Host.current().localizedName`, cached in a `static let`.
      Fallback: `"This Mac"`.
- [x] `commit` = `git commit -m <subject> --trailer "PeteKM-Device: <name>"`.
      On non-zero exit, retry once without `--trailer`. A commit is never lost to the trailer.
- [x] `otherDeviceLastCommit(_ folder:, thisDevice:) -> (name: String, at: Date)?` (§9.3):
      parse `git log -n 100 @{upstream} --format=%ct%x09%(trailers:key=PeteKM-Device,valueonly,separator=)`;
      return the newest line whose device is non-empty and differs from `thisDevice`.
- [x] `incomingDeviceName(_ folder:)` for the "Updated from …" notice (§8.3): trailer of
      the newest commit in `HEAD..@{upstream}`, captured **before** the rebase. Nil when
      no trailer.

### 1.4 The v2 run sequence (§6.1)

Replace the body of `GitSupport.sync` with a new `GitSupport.run(_ folder:, context:)`
(name to taste) that returns a richer result. Keep `sync(_:)` as a convenience wrapper
returning only `SyncOutcome` for any remaining callers.

- [x] Inputs (`SyncContext`):
  - `flush: @MainActor () -> Void` — injected; Phase 3 wires `DailySession.flush()`.
  - `reconcile: @MainActor () -> Void` — injected; wires `document?.reconcileWithDisk()`.
  - `deadline: Date?` — for the 5s sleep/quit budget (§5.3). Network steps get
    `min(30s, time left)` and are skipped once it's spent (→ `.offline`). Local steps get
    `min(15s, max(time left, 1s))`, so the local commit always completes.
    `rebase --abort` ignores the deadline.
  - `allowRebase: Bool` — false while back-off is `.paused` (§6.6); fetch still runs.
    Still behind → `.pullConflict`, no push. Not behind → push as normal.
  - `runner: GitRunner`, `now: Date`, `calendar: Calendar`.
- [x] Sequence, exactly as §6.1:
  0. `gitUnavailable` / `notARepository` checks, then guard (1.2).
  1. `await flush()` on the main actor.
  2. `add -A`; if `status --porcelain` non-empty → commit with trailer.
  3. `fetch` (network timeout).
  4. No remote → `.noRemote`. Fetch failed or timed out → `.offline`.
  5. `rev-list --left-right --count HEAD...@{upstream}`.
  6. If behind > 0 and `allowRebase`:
     a. `await flush()`; `add -A`; commit if dirty.
     b. Re-run the guard. Compute `dailyPathsChangedOnBothSides` (1.5) and the incoming
        device name. Write marker → `rebase --autostash @{upstream}` → remove marker.
        On failure: `rebase --abort`, remove marker, return `.pullConflict`.
     c. `await reconcile()` immediately.
  7. Recompute ahead/behind. If ahead > 0 → push (`--set-upstream <remote> <branch>`
     when there is no upstream, as v1). Failure/timeout → `.pushFailed`.
  8. Return.
- [x] Result type `SyncRun`:
  `outcome`, `didCommit`, `didBringIn` (behind > 0 and rebase succeeded),
  `incomingDevice: String?`, `mergedDailyPaths: [String]`, `stderr: String` (last run only,
  in memory), `fetchSucceeded: Bool`, `pushSucceeded: Bool`, `ahead/behind` after the run.
- [x] Commit failure keeps v1's deliberate mapping to `.pushFailed` (see existing comment).
- [x] Return `.nothingToSync` when nothing was committed, behind == 0, ahead == 0.

### 1.5 Merged-daily detector (§7.3)

- [x] `dailyPathsChangedOnBothSides(_ folder:) -> [String]`:
      `base = git merge-base HEAD @{upstream}`; intersect
      `git diff --name-only base HEAD` with `git diff --name-only base @{upstream}`,
      keep paths matching `daily/*.md`. Called in step 6b **before** the rebase.

### 1.6 Rewire manual Sync

- [x] `DailyStickyView.gitSync` and `FolderSettingsView.sync` call the new sequence with
      real flush/reconcile closures (Settings passes no-ops if no session is reachable;
      Phase 3 routes both through `AutoSync.request(.manual)` instead).
- [x] Manual notices unchanged (v1 §5.3), plus the `busy` / `stuck` lines (§5.5) via
      `manualNotice`.

### 1.7 Tests — new `PeteKMTests/GitSyncTests.swift`

- [x] Test helper `GitFixture`: temp dir with `origin.git` (bare) plus clones `a` and `b`,
      each with `user.name`/`user.email` set locally and an initial pushed commit.
      Tear down in `deinit`.
- [x] Sequence: clean → `.nothingToSync`; local edit → committed and pushed; behind only →
      rebased, no push; diverged non-overlapping → rebased then pushed; push runs only when
      ahead (assert via `git log origin/main` count).
- [x] Second flush (6a): a `flush` closure that writes a file on its second call → that
      write lands in a commit.
- [x] Library conflict: both clones change the same `library/` line →
      `.pullConflict`, working tree byte-identical to before, no `rebase-merge/`, no marker.
- [x] Guards: `index.lock` present → `.busy`, `HEAD` unchanged. Marked stale rebase →
      aborted, run continues. Unmarked rebase → `.busy`. Lock older than 10 min → `.stuck`.
- [x] Hardening: remote `https://example.invalid/x.git` (or a local URL wrapped to require
      auth) → returns within the timeout; assert env contains `GIT_TERMINAL_PROMPT=0`.
      A fake runner test asserts timeout propagation maps fetch → `.offline`,
      push → `.pushFailed`.
- [x] Trailer: commit body contains `PeteKM-Device: <name>`; `otherDeviceLastCommit`
      picks the newest commit from a different device and skips trailer-less commits.

**Done when:** all of the above pass, and manual Sync from the palette and Settings behaves
as v1 from the user's point of view.

---

## Phase 2 — Daily union merge + setting

**Goal:** Same-day sticky edits on two Macs merge instead of pausing sync. The
`syncAutomatically` preference exists (UI comes in Phase 3).

### 2.1 `.gitattributes` (§7.2, §7.5)

- [x] `PeteKMFolder.gitattributes` → `root/.gitattributes`.
- [x] `AgentTemplates.gitattributes`:
      ```
      # PeteKM: same-day Daily Stickies from two Macs keep both sets of lines.
      daily/*.md merge=union
      ```
      and `AgentTemplates.dailyUnionLine = "daily/*.md merge=union"`.
- [x] `FolderInitializer.ensureDailyUnionMerge(_:) -> Bool`, modeled line-for-line on
      `ensureScratchIgnored`: create when missing, append when the line is absent, never
      replace user content, return true when it wrote.
- [x] Call it from `FolderInitializer.initialize` (same report patching as `.gitignore`)
      and from `DailyStickyView.prepareScratch`'s detached task (window open repair).
- [x] The file is tracked: confirm `AgentTemplates.gitignore` does not ignore it.
- [x] Templates: add one line to `AgentTemplates.claudeMd` and `.agentsMd` naming
      `.gitattributes` as "not yours to edit". This changes
      `agentTemplatesFingerprint`, which shows the existing out-of-date notice once —
      expected.

### 2.2 Setting (§4)

- [x] `AppSettings.Keys.syncAutomatically = "petekm.syncAutomatically"`, `Bool`,
      default `true`. Add to the defaults round-trip test in `SettingsTests`.

### 2.3 Tests

- [x] `FolderInitializerTests`: `ensureDailyUnionMerge` creates when missing, appends to an
      existing file with and without trailing newline, idempotent on second call.
- [x] `GitSyncTests` (uses the Phase 1 fixture, with `.gitattributes` committed):
  - Both clones append different lines to the same `daily/` file → rebase succeeds,
    every line from both sides present, `mergedDailyPaths` contains the path.
  - Add/add: both clones create the same `daily/YYYY-MM-DD.md` with different bodies →
    union keeps all lines.
  - Without the attribute on one clone's checkout → still `.pullConflict` safely
    (self-healing rollout, §7.5).

**Done when:** a two-clone same-day edit syncs cleanly; Library conflicts still pause.

---

## Phase 3 — `AutoSync` coordinator

**Goal:** Automatic sync runs from every trigger in §5.1–§5.3, coalesced, with back-off,
and exposes `SyncStatus`. The only UI added here is the settings toggle, automatic
notices, and hiding the v1 banner when on. The dot/menu/popover come in Phase 5.

### 3.1 New file `PeteKM/Files/AutoSync.swift` (§10.1)

- [x] `@MainActor @Observable final class AutoSync`.
- [x] `enum Trigger { folderReady, wake, summon, networkRegained, presencePoll, hide, editIdle, sleep, quit, newDay, manual }`
      with `isArrival` / `isDeparture`.
- [x] `enum SyncStatus: Equatable { off, synced(at: Date), syncing, pending(since: Date), offline(since: Date, pendingSince: Date?), paused, failing(FailReason) }`
      with `FailReason { push, lock }`.
- [x] `AutoSync.Timing` — every constant from §10.3 in one place.
- [x] Injected dependencies for tests: `GitRunner`, a `Clock`/`now` provider, and a
      `NetworkStatus` protocol wrapping `NWPathMonitor`.
- [x] Published state: `status`, `lastFetchAt`, `lastRunStderr`, `otherDeviceLast`,
      and `lastNotice: AutoSyncNotice?` (one-shot, consumed by the view).
- [x] `weak var session: DailySession?` — set via `register(_ session:)` from
      `DailyStickyView.onAppear`. Provides flush/reconcile closures for the run.

### 3.2 `request(_ trigger:)` — the single entry point (§5, §6.6)

- [x] Off or `.off`-eligible folder (no git / no repo / no remote) → return, except `.manual`.
- [x] In flight → set `runAgain = true`, merge the trigger kind, return.
- [x] Summon: skip unless `lastFetchAt` is older than `summonStaleness` (5 min).
- [x] Departure triggers: first flush, then a cheap local check off-main
      (`status --porcelain` non-empty or `ahead > 0`). No local changes → return.
- [x] Back-off (§6.6), all bypassed by `.manual`:
  - `.offline`: departure triggers still run the local commit only (step 1–2); no network
    until network regained, summon, or wake.
  - `.pushFailed`: at most one attempt per 15 min; clears on a successful push.
  - `.pullConflict`: `allowRebase = false`; departure commits continue; fetch continues.
    Remember `HEAD` and `@{upstream}` SHAs at pause; when either changes, retry once with
    rebase allowed.
  - `.busy`: silent, nothing stored.
- [x] After a run, if `runAgain` → start exactly one follow-up run.
- [x] Map `SyncRun` → `SyncStatus` and `lastNotice` (§8.3):
  - `didBringIn` with `incomingDevice` → "Updated from <name>." (4s); no device →
    "Updated from GitHub."
  - `mergedDailyPaths` non-empty → "Merged today's Daily Sticky from both Macs. Check the order." (6s; wins over "Updated from").
  - First `.pullConflict` of a pause → v1 conflict notice (15s), not repeated per retry.
  - Everything else automatic → no notice.
  - `.manual` → v1 `SyncOutcome.notice` as today.
- [x] Refresh `otherDeviceLast` after every successful fetch (off-main).

### 3.3 Trigger sources

- [x] **Folder ready:** `AutoSync.start(folder:)` called from `DailyStickyView.onAppear`
      (the view only exists in `.ready`); fires `.folderReady`. `stop()` on disappear /
      folder change.
- [x] **Wake / sleep:** `NSWorkspace.shared.notificationCenter` observers for
      `didWakeNotification` and `willSleepNotification`, registered in `AutoSync.start`.
  - Wake: wait for `NetworkStatus` satisfied, up to `wakeNetworkWait` (20s), then run.
    Record `wokeAt` for the §9.2 notice (Phase 5).
  - Sleep (§5.3): synchronous flush + local commit on the main actor's watch (fast), then
    the network sequence with a 5s `deadline`. The run's timeouts kill git when exceeded;
    the marker from 1.2 handles a killed rebase next time.
- [x] **Summon:** observe `.peteKMDidSummon`.
- [x] **Network regained:** `NWPathMonitor` on a private queue; hop to main on
      unsatisfied → satisfied transitions only.
- [x] **Presence poll:** `Task` loop every 5 min, started when the window becomes visible,
      cancelled on hide.
- [x] **Hide:** new `Notification.Name.peteKMDidHide`, posted from
      `StickyWindowController.hide()` (covers `windowShouldClose` and keyboard ⌘Q, which
      both call `hide()`). 2s debounce in `AutoSync`; a summon inside the window cancels it.
- [x] Expose visibility: `StickyWindowController` posts `.peteKMDidSummon` / `.peteKMDidHide`;
      `AutoSync` tracks `windowVisible` from those two.
- [x] **Editing idle:** `AutoSync.noteEdit()` restarts a 60s timer while the window is
      visible. Add `var onEdit: (() -> Void)? = nil` to `MarkdownEditor`; call it from
      `Coordinator.textDidChange`. `DailyStickyView` passes `autoSync.noteEdit`;
      `ScratchPaneView` passes nothing (Scratch never triggers sync, §5.2).
- [x] **Quit:** `AppDelegate.applicationShouldTerminate` — keep the keyboard-⌘Q-hides
      branch first. Otherwise, if automatic sync is on and local changes exist, return
      `.terminateLater`, run `.quit` with a 5s deadline, then
      `NSApp.reply(toApplicationShouldTerminate: true)`. (The alert is Phase 5; here it
      always quits after the run.)
- [x] **Manual:** palette Sync and Settings Sync call `autoSync.request(.manual)`; the
      view shows the returned notice. Works when the toggle is off too.

### 3.4 Wiring

- [x] `AppServices`: `let autoSync = AutoSync(settings:)`.
- [x] `AppDelegate`: inject `.environment(services.autoSync)` into `RootView`; pass
      `autoSync` to the terminate path.
- [x] Observe `settings.syncAutomatically`: off → tear down observers/timers,
      `status = .off`. On → start again.
- [x] `DailyStickyView`:
  - `syncLaunchCheck.runIfNeeded` and the "Changes to sync." banner only when the toggle
    is off (§4, §8.2). `SyncLaunchCheck` itself unchanged.
  - Consume `autoSync.lastNotice` into the existing `show(_:seconds:)` notice line.
- [x] `FolderSettingsView` `GitSettingsSection`: "Sync automatically" toggle + caption from
      §4, visible only when the folder is a repo with a remote.

### 3.5 Tests — new `PeteKMTests/AutoSyncTests.swift`

Fake `GitRunner`, fake clock, fake `NetworkStatus`.

- [x] Three triggers during one in-flight run → exactly one follow-up run.
- [x] Departure trigger with a clean tree and ahead == 0 → no run.
- [x] Summon with `lastFetchAt` 2 min ago → no run; 6 min ago → run.
- [x] `.offline` → departure commits only, no fetch; network regained → full run.
- [x] `.pushFailed` → second attempt suppressed for 15 min, allowed after; manual ignores it.
- [x] `.pullConflict` → no rebase on later runs; changing the fake `@{upstream}` SHA →
      one retry with rebase. Conflict notice emitted once.
- [x] Toggle off → `status == .off`, no runs from triggers; manual still runs.
- [x] Notice mapping: incoming with trailer / without trailer / merged daily.
- [x] Integration test with the real `GitFixture`: hide trigger on clone A with a dirty
      tree pushes; folder-ready on clone B brings it in and emits "Updated from <A's name>."

**Done when:** with the toggle on, writing on clone A and hiding the window delivers the
change to clone B on its next summon, with no banner and no manual Sync.

---

## Phase 4 — Pre-New-Day deferred write (§6.5)

**Goal:** Opening today's sticky never creates a competing file blind. Capture is not
delayed.

### 4.1 `StickyDocument` — deferred create

- [x] `init(url:text:deferredCreate:)`; `private(set) var isDeferred: Bool`.
      `savedText = composed text`, but the file does not exist yet.
- [x] `saveNow()` when deferred: if not dirty → do nothing. If dirty → if a file now
      exists on disk, raise the normal `Conflict` (never clobber); otherwise write
      `text` atomically and clear `isDeferred`.
- [x] `reconcileWithDisk()` when deferred — **important:** today a missing file plus
      non-empty text triggers `write(text)`. That must not happen while deferred, or the
      directory watcher defeats the deferral.
  - Disk missing → do nothing.
  - Disk present and not dirty → adopt disk (`text = savedText = onDisk`), clear
    `isDeferred`. Composed text discarded; nothing was written.
  - Disk present and dirty → existing conflict path.
- [x] `func commitDeferred()` — writes `text` if still deferred and the file is still
      missing (timeout path).

### 4.2 `DailySession`

- [x] In `create(start:for:)`: when all four §6.5 conditions hold
      (`syncAutomatically`, upstream exists, day is today, file missing), build a
      deferred `StickyDocument` instead of `StickyDocument.open(url:creatingWith:)`.
      "Upstream exists" comes from a cached `AutoSync.hasUpstream` (refreshed on each run);
      never shell out on the main actor here.
- [x] Call `autoSync.request(.newDay)` with a 2s budget (`deadline` on the run).
- [x] Resolve the deferral at the first of:
  - Run finished and brought the file in → `document.reconcileWithDisk()` (adopts).
  - First keystroke → normal autosave writes it (4.1 `saveNow`).
  - 2s elapsed, offline, or failure → `document.commitDeferred()`.
  Implement with a `Task` that awaits the run result or `Task.sleep(newDayBudget)`,
  whichever first.
- [x] `.ask` behavior (§6.5 step 4): when setting `newDayOptions`, also fire
      `.newDay`. In `startNewDay(_:)`, re-check the file on disk: if it arrived, open it
      and skip creation. If the run is finished when the prompt appears, nothing extra.
- [x] Carry-forward (§6.5): composition stays immediate, so capture is not delayed. If the
      run brings in a newer prior sticky but not today's file, and the user hasn't typed,
      recompose and replace the still-unwritten text. Guard it with the same
      "not dirty, still deferred" check.
- [x] `pruneIfBlank`: a deferred document has no file, so `readText` is nil and it returns
      early — no change needed; add a test.
- [x] `handleActivation` day rollover → `openToday` → same deferred path.
- [x] `AutoSync.register(session)` gives `DailySession` the `autoSync` reference; when no
      `AutoSync` is attached (tests, toggle off), behave exactly as today.

### 4.3 Tests (`DailyStickyTests` + `GitSyncTests`)

- [x] Incoming today's file, no keystroke → disk version adopted, composed text discarded,
      no write happened before the arrival (assert file mtime/contents equal the pulled one).
- [x] Keystroke before arrival → composed text + keystroke written immediately.
- [x] Timeout (fake run never completes) → composed text written at 2s.
- [x] Offline result → written immediately.
- [x] Directory-watcher reconcile while deferred and disk missing → no write.
- [x] Toggle off / no upstream / past date → immediate write as today.
- [x] `.ask`: file arrives while prompt is showing → answering opens the arrived file.
- [x] Blank deferred sticky left for another day → no file on disk.

Decisions made during implementation:

- `DailyStickyView` starts `AutoSync` and passes it to `DailySession(…, autoSync:)` before
  the first `openToday`, so the launch open can defer too (registering later would miss it).
- Before the first run has cached `hasUpstream`, `GitSupport.hasConfiguredUpstream` reads
  `.git/HEAD` + `.git/config` directly — no process on the main actor.
- A deferred, never-written sticky that is navigated away from (another date, a Library file)
  is dropped, like a blank one; reopening composes it again.
- With `.ask`, when the run brings today's file in while the prompt is still up, the prompt
  closes and the file opens without waiting for an answer (§6.5 step 4, "skip the prompt").

**Done when:** two clones opening the same new day in sequence end with one shared
sticky and no union merge needed when both are online.

---

## Phase 5 — Visibility, quit alert, Guide, docs

**Goal:** The user sees sync only when something needs them (§8, §9).

### 5.1 Status-line copy (§8.4)

- [ ] `SyncStatus.line(now:calendar:) -> String?` and
      `SyncStatus.showsDot(now:) -> DotStyle?` (`none / secondary / orange`) as pure,
      tested functions. 2-minute rule for pending (§8.1).
- [ ] Time formatting: relative under 1 hour ("2 min ago"), clock time today ("14:02"),
      date beyond today. One helper, tested.
- [ ] `otherDeviceLine` → "Last from <name>: <time>." or nil.
- [ ] `AutoSync` re-evaluates status on a 30s tick while pending, so the dot appears at
      the 2-minute mark without another trigger.

### 5.2 Window dot + popover (§8.2)

- [ ] New `PeteKM/Daily/SyncStatusDot.swift`: 6pt circle, top-trailing overlay in
      `DailyStickyView`. Color `DS.Color` secondary or `Color.orange`. `.help(line)`
      tooltip.
- [ ] Click → `.popover` with status line, other-device line, **Sync Now** button
      (`request(.manual)`), and **Details…** disclosure showing `lastRunStderr` in a
      selectable monospaced `Text` inside a small `ScrollView`.
- [ ] Hidden when `showsDot == none` or toggle off.

### 5.3 Menu bar (§8.2)

- [ ] `MenuBarController`: `var syncStatusLine: String?`, `var onSyncNow: (() -> Void)?`.
      When non-nil, insert a disabled status row (tooltip = other-device line) and
      **Sync Now** at the top, then a separator.
- [ ] Badge: new `Assets.xcassets/PixelMarkBadge.imageset` (template; pixel mark plus a
      corner dot). `glyph(badged:)` swaps the image.
- [ ] `AppDelegate` observes `autoSync.status` with `withObservationTracking` (same
      pattern as `observeFolder`) and calls `menuBar.refresh()`.

### 5.4 Settings (§8.2)

- [ ] `GitSettingsSection`: status line + other-device line under the toggle.

### 5.5 Quit alert (§9.2)

- [ ] In the `.terminateLater` path from Phase 3: after the 5s run, if changes are still
      not on GitHub **and** the quit is user-initiated, show the `NSAlert`
      ("Some notes haven't reached GitHub yet." / body from §9.2 /
      **Quit Anyway** / **Cancel**). Cancel → `reply(false)`.
- [ ] User-initiated detection: read
      `NSAppleEventManager.shared().currentAppleEvent` at `applicationShouldTerminate`
      time; if it is `kAEQuitApplication` with a `keyAEQuitReason` attribute (logout,
      restart, shutdown) → no alert. Menu-bar / app-menu Quit has no quit-reason → alert.
- [ ] Sparkle: set an `updaterDelegate` in `UpdateController` (inside
      `#if canImport(Sparkle)`) implementing `updaterWillRelaunchApplication(_:)` to set
      a `isRelaunchingForUpdate` flag; no alert when set.

### 5.6 Wake notice (§9.2.3)

- [ ] At the start of a wake/launch arrival run, if `ahead > 0` and the oldest unpushed
      commit's date is before `wokeAt` / process launch → notice
      "Notes from earlier on this Mac haven't reached GitHub yet." (8s). The run's own
      result notice replaces it when it finishes.

### 5.7 Guide (§9.4)

- [ ] `GuideSettingsView`: "Using two Macs" section, the three points from §9.4 in the
      same words.

### 5.8 Docs

- [ ] `context/map.md`: `AutoSync.swift` row in Layer 2, `.gitattributes` in the generated
      folder shape, `PixelMarkBadge` in assets, `syncAutomatically` in the settings list,
      new test files, and a source-of-truth row for `context/sync-v2/`.
- [ ] `context/spec.md` §5 folder shape: add `.gitattributes`.
- [ ] `context/ACCEPTANCE.md`: rows for automatic sync, union merge, Pre-New-Day, quit
      alert.
- [ ] `CLAUDE.md` (this repo): add `.gitattributes` to the generated-files list.

### 5.9 Tests

- [ ] `SyncStatus` line/dot for every row of §8.1 and §8.4, including the 2-minute edge.
- [ ] Time formatting helper.
- [ ] Wake-notice condition (pure function over commit dates + wake time).

**Done when:** the manual checklist below passes on two real Macs.

---

## Manual two-Mac checklist (§11)

Setup: both Macs on the same GitHub repo, v2 build installed, "Sync automatically" on,
SSH or credential-helper auth working non-interactively.

- [ ] 1. Write on A, hide the window, open B → B shows "Updated from A." and today's
      sticky matches.
- [ ] 2. Write on A, keep the window up, wait 60s, open B → same.
- [ ] 3. Turn off A's Wi-Fi, write, close the lid. Open B and write in today's sticky.
      Reopen A online → A shows "Merged today's Daily Sticky from both Macs. Check the
      order."; both Macs converge; no lines lost.
- [ ] 4. Same note in `library/` edited on both while A is offline → A pauses with the v1
      conflict notice, orange dot; B unaffected; resolving in a terminal clears the dot on
      the next trigger.
- [ ] 5. A offline with pending changes for over 2 min → dot appears; mouse Quit → alert;
      Cancel keeps the app; Quit Anyway quits; relaunch online → pushes, and the
      earlier-notes notice shows.
- [ ] 6. B: status popover shows "Last from A: <time>" matching A's last push.
- [ ] 7. Turn the toggle off → v1 behavior exactly (banner, manual only).
- [ ] 8. Run `/petekm-process` in a terminal while the app is open and typing → no lock
      errors surface; the app skips and catches up.

Extra checks:

- [ ] Fresh day, both Macs online: open A, then B → B adopts A's sticky, no merge notice.
- [ ] Keyboard ⌘Q still hides (and acts as a hide trigger); logout does not show the alert.
- [ ] Typing in Scratch only → no sync runs (check `git log`).
- [ ] With `git` off `PATH`, offline, and during a pause: open and save today's sticky.
