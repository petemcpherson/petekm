# Implementation Plan: Multi-Device Sync + Unified Process

Source spec: `context/sync/spec.md` (final, no open decisions). Section refs below (`§N`)
are that spec unless marked `main spec §N` (= `context/spec.md`).

Supersedes `context/spec.md` §17 in full. Three phases, ordered so each one ships a
coherent slice: app-side Sync first (largest integrity surface), then the passive launch
check and conflict verification, then the agent-side templates + migration.

## Progress

- [x] **Phase 1 — App-side Sync: two-way `GitSupport.sync`, new `SyncOutcome`, Set Remote, "Sync" rename**
- [x] **Phase 2 — Launch check, "Changes to sync." banner, external-change verification**
- [x] **Phase 3 — Unified `/petekm-process` skill, template rewrites, skill-rename migration**

---

## Phase 1 — App-side Sync

Everything in `PeteKM/Files/GitSupport.swift` plus its callers. No new files needed
except tests. Nothing here touches `AgentTemplates.swift`.

### 1.1 Replace `SyncOutcome` (§5.3)

`GitSupport.swift:40-65`. Delete the current enum (including nested `PushSkipReason`)
and write:

```swift
enum SyncOutcome: Equatable {
    case gitUnavailable
    case notARepository
    case offline
    case noRemote
    case pullConflict
    case pushFailed
    case nothingToSync
    case synced
}
```

`notice` strings verbatim from §5.3's table:

| Case | Notice |
| --- | --- |
| `gitUnavailable` | `Git isn't available.` |
| `notARepository` | `This PeteKM folder isn't a Git repository.` |
| `offline` | `Saved locally. Couldn't reach GitHub.` |
| `noRemote` | `Saved locally. No GitHub remote is set.` |
| `pullConflict` | `Sync paused — the same note changed on two devices. Nothing was lost or changed. Ask PeteKM (in a terminal) to help sort it out, or open the folder in <editor> yourself.` |
| `pushFailed` | `Saved and up to date locally, but couldn't publish to GitHub. Try Sync again.` |
| `nothingToSync` | `Already up to date.` |
| `synced` | `Synced.` |

`pullConflict`'s notice names the external editor. `ExternalEditorProvider.current`
supplies the name elsewhere in the app (see `PaletteCommand.swift`'s editor-name lookup —
never hard-code "VS Code"). Either make `notice` a computed property that reads the
provider, or take the editor name as a parameter; prefer the latter so `SyncOutcome`
stays a pure value type and remains trivially testable.

Callers that pattern-match the old cases and must be updated: `FolderSettingsView.swift:214-225`
(`sync()`), `DailyStickyView.swift:234-242` (`gitSync()`), `PeteKMTests/ExternalToolsTests.swift:41-70`.

### 1.2 Rewrite `GitSupport.sync(_:)` to the §5.1 sequence

Exact order, each step returning early as specified. Blocking; callers already run it
via `Task.detached(priority: .utility)` — keep that.

1. `isGitAvailable` → `.gitUnavailable`; `isRepository` → `.notARepository`.
2. `git add -A`, then `git status --porcelain`; if non-empty, `git commit -m commitMessage(for:)`.
   Record `didCommit`. **Unconditional and first — before any network call** (§6.1).
   If the commit itself fails (`run` returns nil), **stop and return `.pushFailed`** — do
   not proceed to any network step with an uncommitted tree. §5.3 fixes the enum at eight
   cases, so no `commitFailed` case is added; `.pushFailed`'s copy ("Try Sync again.") is
   the only one of the eight that is not actively false here. Add a code comment naming
   this as a deliberate mapping, not an oversight.
3. `git fetch`. Non-zero exit → `.offline`. (Step 2's commit already happened.)
4. `remoteName(of:) == nil` → `.noRemote`. (Run this check before `fetch` if cheaper —
   §5.1 orders it after, but a repo with no remote makes `fetch` fail anyway; keeping
   spec order is fine and clearer.)
5. Ahead/behind via `git rev-list --left-right --count HEAD...@{upstream}` (parse two
   tab-separated ints: `ahead`, `behind`). If `behind == 0 && ahead == 0 && !didCommit` →
   `.nothingToSync`.
6. If `behind > 0`: `git pull --rebase --autostash`. On non-zero exit:
   **immediately `git rebase --abort`** (unconditional, §6.4) and return `.pullConflict`.
7. `git push`, or `git push --set-upstream <remote> <branch>` when `@{upstream}` doesn't
   resolve — keep the existing logic at `GitSupport.swift:96-104` verbatim. Failure →
   `.pushFailed`.
8. → `.synced`.

Never `--force`, never `-f`, never `push --force-with-lease` (§6.2). Never a
`checkout --theirs/--ours`, `merge -X`, or any automatic resolution (§6.3).

Add a small helper `aheadBehind(_ folder:) -> (ahead: Int, behind: Int)?` — Phase 2's
launch check and Phase 3's status-skill wording both need the same parse, and returning
`nil` when there's no upstream is the "omit the line" signal.

Keep `commitMessage(for:)` unchanged (`PeteKM backup <timestamp>`, §5.1 step 1).

### 1.3 Set Remote (§7)

`FolderSettingsView.swift`, `GitSettingsSection`. Shown only when `isRepository && remote == nil`:

- `TextField("GitHub URL", text: $remoteURL)` + `Button("Set Remote")`, disabled when the
  trimmed string is empty or `isWorking`.
- Runs `GitSupport.setRemote(_ url: String, in: folder)` → `run(["remote", "add", "origin", url])`.
- Failure → `status = "Couldn't add that remote — check the URL."` Success → `refresh()`
  so the section flips to showing `Remote: origin`.
- No validation, no auth UI, no repo creation (§7, §8).

### 1.4 The "Sync" rename (§1, §4)

User-facing copy only; internal `Git*` symbols stay (§1 table, §4 preamble). Sites:

| File:line | Change |
| --- | --- |
| `PaletteCommand.swift:46` | `"Git Sync"` → `"Sync"` |
| `PaletteCommand.swift:72` | subtitle → `"Save, then sync with GitHub."` (drop "Never pulls or merges" — now false) |
| `FolderSettingsView.swift:174` | button `"Git Sync"` → `"Sync"` |
| `FolderSettingsView.swift:176` | helper text → `"Saves your notes, then syncs with GitHub. Never overwrites anything — if the same note changed on two devices, it stops and tells you."` |
| `SettingsView.swift:105` | `"…so Git Sync can't commit it"` → `"…so Sync can't commit it"` |
| `GuideSettingsView.swift:77, 85` | `Git Sync` → `Sync` |
| `ScratchStore.swift:13`, `PeteKMFolder.swift:34`, `map.md` Layer 3b | comment text `Git Sync` → `Sync` |
| `GitSupport.swift:36` | `// MARK: - Git Sync (§17.2)` → `// MARK: - Sync (sync spec §4, §5)` |

`PaletteCommandID.gitSync` / `PaletteOutcome.gitSync` keep their names (implementation,
not copy). Availability gate stays `isGitRepository` (§4.2 item 1).

### 1.5 Tests (Phase 1)

Extend `PeteKMTests/ExternalToolsTests.swift` (Swift Testing, `@Test`/`#expect`). Existing
helpers `makeFolder()` / `makeRepository()` are already there; add a `makeRepositoryPair()`
that creates a bare "remote" repo plus two clones — enough to exercise real pull/push
locally with no network.

- `.notARepository` / `.gitUnavailable` outside a repo (existing test, updated cases).
- `.noRemote` after a dirty commit; commit exists in `git log`.
- `.nothingToSync` on a clean tree even with an upstream.
- `.synced` when a clone pushes a new file and the bare remote receives it.
- Clone A pushes; clone B (dirty, different file) syncs → `.synced`, both files present.
- **Conflict test — the important one:** both clones edit the same line of the same file;
  B syncs → `.pullConflict`, `git status --porcelain` shows no rebase in progress
  (`.git/rebase-merge` absent), and B's file content is byte-identical to what it was
  before the sync attempt (§5.2, §6.4).
- `.pushFailed` when the remote path is deleted after the clone.

---

## Phase 2 — Launch check + banner + conflict verification

### 2.1 The passive check (§4.3)

Once per app process lifetime, on the first transition of `FolderStore.State` to `.ready`
(launch, recovery from `.missing`, or a fresh folder pick) — **not** on
`.peteKMDidSummon` and **not** on `didBecomeActive` (§4.3, main spec §8.7).

Where: `FolderStore` is the state owner, but the banner belongs to `DailyStickyView`.
Simplest correct wiring: a `@State private var didCheckSync = false` guard is *not* enough
(the view can be rebuilt); put the once-flag on `FolderStore` (`private(set) var
didRunLaunchSyncCheck`) or on a small `SyncLaunchCheck` observable in `AppServices`, and
have `DailyStickyView.onAppear` ask it.

The check itself, off the main actor:

```
git fetch          → any failure: return nil, show nothing
GitSupport.aheadBehind(folder)   (1.2's helper)
```

Show the banner only when `ahead > 0 || behind > 0`. Every other outcome — no git, not a
repo, no upstream, fetch failed, even — is silent (§4.3: this check may never produce an
error state).

### 2.2 The banner

One non-modal, dismissible row in the Daily Sticky window: text **"Changes to sync."**,
a **"Sync"** button, and an "×". No counts, no ahead/behind, no Git words (§4.3).

Placement: alongside the existing transient `notice` line in `DailyStickyView` (see
`show(_:seconds:)` at `DailyStickyView.swift:262`) but **not** using it — the notice
auto-expires after 6s and carries no button. Add a separate `@State private var
showsSyncBanner` row rendered above the editor, styled with `DS` tokens like the notice.

The button calls the same `gitSync()` path as the palette command (§4.1 — one code path).
Dismissing, or running Sync, hides it for the rest of the session; since the check runs
once per process there is no reappearance path to guard (§4.3).

### 2.3 Verify the git-driven external-change path (§5.5) — verification, not a feature

A successful pull rewrites files on disk, possibly one open in the editor with unsaved
changes. The existing machinery (`DirectoryWatcher` → `DailySession` →
`StickyDocument.Conflict(diskText:)` / `ConflictChoice`, main spec §8.5/§19.4) should
already handle it, since FSEvents doesn't care who wrote.

**Required verification step:** with a file open and dirty, run a Sync that pulls a
changed version of that same file, and confirm the keepMine/keepDisk/keepBoth alert
appears. Also confirm `StickyDocument.reconcileWithDisk()` (called on
`didBecomeActive`, `DailyStickyView.swift:75-78`) catches it if the watcher misses.

If it does **not** trip: that is a pre-existing gap this spec surfaces but does not fix
(§5.5). Record it in `context/map.md` under "Known drift" and report it — do not design
new conflict UI here (§8).

A belt-and-braces measure that is *not* new UI and is worth doing: have the app-side
`sync()` completion handler call `session.document?.reconcileWithDisk()` on the main actor
after a `.synced` outcome, so a pulled change is noticed immediately rather than at next
activation.

### 2.4 Tests (Phase 2)

- `aheadBehind` returns `nil` with no upstream, `(0,0)` when even, correct non-zero pairs
  after a clone diverges (unit, using the Phase 1 repo-pair helper).
- Launch check returns "show nothing" for: no git, not a repo, no remote, unreachable
  remote. (Pure-function shape: make the decision a testable
  `SyncLaunchCheck.shouldPrompt(aheadBehind:) -> Bool` even if `fetch` itself isn't mocked.)
- The banner's once-per-session flag flips and does not reset on a re-summon
  (`AppLifecycleTests` is the natural home).
- §2.3's conflict verification is a manual/UI check; if `PeteKMUITests` can drive it
  against `PETEKM_UITEST_FOLDER`, add it there, otherwise record the manual result in
  `context/ACCEPTANCE.md`.

---

## Phase 3 — Unified Process (agent-side)

All product content: `PeteKM/Files/AgentTemplates.swift` plus the migration in
`FolderInitializer.swift`. **Editing templates is a product-content change** — match the
existing voice exactly (numbered steps, "Never" section, terse).

### 3.1 One skill (§3.2, §3.4)

`AgentTemplates.skillNames` (`AgentTemplates.swift:16-22`) becomes:

```swift
static let skillNames = [
    "petekm-process",
    "petekm-rebuild-index",
    "petekm-organize",
    "petekm-status",
]
```

Delete `processToday` and `processDate`; add one `process` template, wired in
`skill(_:)` at `AgentTemplates.swift:334-343`. Its content merges today's two skills:

- Frontmatter `name: petekm-process`, description covering both the no-arg sweep and the
  single-date override, and naming the `/petekm-process` invocation.
- **Step 0 (new, §3.3):**
  `git rev-parse --is-inside-work-tree >/dev/null 2>&1 && git pull --rebase --autostash`.
  Not a repo / no git → skip silently, proceed. Conflict → **stop Process entirely, process
  nothing**, report: `Sync conflict — couldn't pull latest changes before processing.
  Resolve it (ask me, or run git status yourself), then run /petekm-process again.`
- **Target resolution (§3.2):**
  - no argument → read `.petekm-state.json`'s `lastProcessedDailyNote`, list every
    `daily/*.md` whose date is newer, process **oldest-first**, one file at a time.
    Explicitly: it does not matter whether the app created the file or the user dropped
    it in by hand.
  - one argument → resolve `2026-08-19` / `2026-08-19.md` / `daily/2026-08-19.md` /
    plain-language date; ask if ambiguous; if missing, list nearby days and stop.
- **Steps 2–9** are today's `processToday` steps 2–9, unchanged.
- **State rule (§3.2):** update `lastProcessedDailyNote` only when the run processed a note
  *newer* than the recorded one — never backward, never falsely forward. Keep the existing
  `lastSuccessfulProcessing` ISO-8601 write.
- **Final step (§3.3):**
  `git add -A && git commit -m "PeteKM: processed <dates>" && git pull --rebase --autostash && git push`.
  Second pull conflicts → the local commit is safe; report `Processed successfully and
  committed locally, but couldn't sync — conflict pulling latest changes. Run Sync from the
  app, or ask me.` No remote → `Processed and committed locally. No GitHub remote is set,
  so nothing was pushed.` Never force-push, never skip the pull to "just push anyway."
- **Never** section keeps: modify `daily/`, restructure the Library, guess a destination to
  avoid the Inbox. Add: force-push or resolve a sync conflict on your own.

### 3.2 `petekm-status` gains a sync line (§3.4)

Existing item 6 (`AgentTemplates.swift:533`) — "whether the working tree is clean" — gains:
ahead/behind vs. the remote from `git rev-list --left-right --count HEAD...@{upstream}`,
worded plainly: `3 commits not yet pushed` / `2 new commits on GitHub, not yet pulled` /
`Up to date with GitHub.` No upstream → omit the line rather than error. Also update its
"most useful next command" to name `/petekm-process`.

### 3.3 Other template copy (§3.4)

- `claudeMd` skills list (`AgentTemplates.swift:123-124`): two bullets collapse to
  `` `/petekm-process` — file new Daily Stickies into the Library; pass a date to reprocess one day. ``
- `agentsMd` and `index`: any mention of the two old names → `/petekm-process`.
- `AGENTS.md` §3.3's two git steps should be described there too if AGENTS.md documents the
  process procedure — keep the skill as the normative place, AGENTS.md as policy.

### 3.4 In-app Guide copy

`GuideSettingsView.swift:47` → `/petekm-process`; `:56` → `/petekm-process 2026-08-11`,
and section 4's framing shifts from "process each one by date" to "plain
`/petekm-process` picks up everything newer than the last processed day, oldest-first" —
which is the whole point of §3.2.

### 3.5 Rename migration in Refresh Agent Files (§3.5)

`FolderInitializer.refreshAgentFiles` gains a one-time step, run **before** the normal
template writes:

1. For each of `petekm-process-today/SKILL.md`, `petekm-process-date/SKILL.md`: if it
   exists, `FileWriting.backUp(_:into: folder.backups)` (preserves hand edits, same
   convention as every other tracked file), record in `report.backedUp`.
2. Delete the file, then remove the now-empty `petekm-process-today/` and
   `petekm-process-date/` directories (only if empty — never `removeItem` on a directory
   holding anything else the user put there).
3. Fall through to the normal write loop, which now creates `petekm-process/SKILL.md`.

Gating needs no new setting: `agentTemplatesFingerprint` (`FolderInitializer.swift:137`)
changes automatically because `skillNames` and the templates changed, so
`agentFilesAreOutOfDate` goes true and `DailyStickyView.noticeIfAgentFilesOutOfDate`
(`:248`) fires the existing once-per-version notice. Verify `agentFilesAreOutOfDate`
does *not* also need to consider stale directories — it iterates `skillNames`, so a
leftover `petekm-process-today/` on disk is invisible to it; that is acceptable, because
the fingerprint change alone already prompts the refresh that removes them.

Onboarding (`policy: .keep`) is unaffected: a fresh folder never has the old directories.

### 3.6 Tests (Phase 3)

`PeteKMTests/FolderInitializerTests.swift`:

- `AgentTemplates.skillNames` contains `petekm-process` and neither old name;
  `skill("petekm-process")` is non-empty and contains the freshness step (the existing
  assertion at `:154` moves to the new name).
- Initialize a folder, hand-create `.claude/skills/petekm-process-today/SKILL.md` and
  `.../petekm-process-date/SKILL.md`, run `refreshAgentFiles`, then assert: both backups
  exist in `.petekm-backups/`, both directories are gone, `petekm-process/SKILL.md` exists
  with the shipped content.
- The migration is idempotent — a second `refreshAgentFiles` reports `Already up to date.`
- A stray user file inside `petekm-process-date/` blocks only that directory's removal and
  does not fail the run.
- `agentTemplatesFingerprint` differs from the pre-change value (implicitly covered by the
  existing stability test; no new assertion needed).

---

## Cross-cutting acceptance (do before calling any phase done)

1. **No force anywhere.** `grep -rn "force" PeteKM/Files/GitSupport.swift` and the process
   template must return nothing that pushes (§6.2).
2. **Commit precedes every network call** in both implementations (§6.1).
3. **Every conflict aborts and restores** — `rebase --abort` on the app side (§6.4),
   full stop on the agent side (§3.3).
4. **Capture never blocks** (§6.6): with git deleted from `PATH`, with no network, and
   mid-`pullConflict`, opening and saving today's Daily Sticky still works. Add this to
   `context/ACCEPTANCE.md`.
5. **Docs:** update `context/map.md` — Layer 2's `GitSupport.swift` row ("One-way only:
   commit + push, never pull" is now false), the generated-folder-shape skill list, the
   command catalog's `Git Sync` entry, and Layer 3b's exclusion 2 wording. Note in
   `context/spec.md` §17 that `context/sync/spec.md` supersedes it.
