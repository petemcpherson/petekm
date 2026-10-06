# PeteKM — Architecture Map

Fast orientation for an AI agent. Broad, not deep. Every section points at where the
real detail lives.

**Repo = the native macOS app.** It is *not* a PeteKM knowledge folder. The app
*generates* one on disk (see [Generated folder shape](#generated-folder-shape)).

## Source of truth

| Doc | What it settles | Size |
| --- | --- | --- |
| `context/spec.md` | Product behavior. Sections are cited in code comments as `§N`. | ~2200L |
| `context/DESIGN.md` | Visuals, UX, vocabulary, copy tone. | ~1500L |
| `context/plan.md` | 7-phase implementation plan. All phases complete. | ~210L |
| `context/sync/spec.md` | Two-way sync + unified `/petekm-process`. **Supersedes `spec.md` §17 in full**; amends §12–§15 wherever they name `Git Sync` or the old per-date process skills. | ~260L |
| `context/sync/plan.md` | Sync implementation plan + manual testing checklist. Implemented. | ~394L |
| `context/sync-v2/spec.md` | Automatic sync across devices: triggers, the hardened run, `daily/` union merge, Pre-New-Day, status dot/menu/quit alert. **Supersedes `context/sync/spec.md` §4.2** (manual-only) while "Sync automatically" is on. | ~470L |
| `context/sync-v2/plan.md` | Sync v2 implementation plan (5 phases) + manual two-Mac checklist. Implemented. | ~520L |
| `context/ACCEPTANCE.md` | Criterion → code → test mapping (spec §24, §22). Best "does X exist?" lookup. | ~100L |
| `context/DISTRIBUTION.md` | Signing, notarization, Sparkle, `scripts/release.sh`. | ~57L |
| `context/design-system/` | Tokens + pixel-art mark assets (`robopete*.png/svg`, `robopete.grid.json` — internal filenames only, no user-facing name). | — |

## Non-negotiable invariants

These have direct code consequences. Break one and the design breaks.

1. **Markdown on disk is the only canonical store.** No DB holds note content. Any
   index/cache must be fully rebuildable from `.md` (§2.2, §5.8). No SwiftData in the app.
2. **`daily/` is an immutable ledger; `library/` is mutable.** AI never writes `daily/`
   (§2.5, §13.3). Agent processing state lives in `.petekm-state.json`, never as markers
   inside a sticky.
3. **The app is not the only writer.** VS Code / Claude Code / Finder edit the same files.
   Detect external change, never clobber newer disk content, offer a real conflict path
   (§8.5, §19.4). All writes atomic.
4. **Capture never blocks.** Git, agents, missing VS Code, update checks — all degrade to
   a terse notice; none may gate opening or saving today's sticky (§17.4, §15.3).
5. **Markdown syntax stays visible.** Live styling layers *on top of* `#`, `**`, `-`.
   Not WYSIWYG (§9.1–9.2). Rules out rich-text/AttributedString-hiding approaches.
6. **Sandbox is OFF** (`ENABLE_APP_SANDBOX = NO`) because the app shells out to
   `git`/`code`/Terminal. Folder access still goes through a security-scoped bookmark.
7. **Vocabulary is fixed** (DESIGN §2): *Daily Sticky*, *Library*, *PeteKM* (no separate
   agent persona name). Copy is terse and plain — "Nothing found." No streaks, no motivation.

## Build / test

```bash
xcodebuild -scheme PeteKM -configuration Debug build
xcodebuild -scheme PeteKM test
xcodebuild -scheme PeteKM test -only-testing:PeteKMTests
scripts/release.sh 1.0.0 12        # archive + notarize + dmg
```

Targets: `PeteKM` (app), `PeteKMTests` (**Swift Testing** — `@Test`/`#expect`),
`PeteKMUITests` (XCTest). One scheme.

---

## Directory map — `PeteKM/`

| Folder | Owns |
| --- | --- |
| `App/` | Lifecycle, window, global hotkey, menu bar, service container |
| `Daily/` | Daily Sticky: date → file → document, New Day flow, main screen |
| `Editor/` | NSTextView Markdown editor, live styling, TOC, cursor memory |
| `Files/` | Folder shape, bookmarks, atomic writes, initialization, templates, Git/Sync, watchers |
| `External/` | VS Code, Finder, Terminal hand-off — every failure a notice, never a block |
| `Onboarding/` | First run + missing-folder recovery |
| `Palette/` | ⌘K command palette, command catalog |
| `Scratch/` | The Scratch pane — one durable-but-unfiled file, outside the contract |
| `Search/` | Disposable full-text index, fuzzy match, ranking |
| `Settings/` | Preferences model + tabbed Settings window + Sparkle |
| `DesignSystem/` | `DS` tokens, PixelMark/Wordmark |
| `Assets.xcassets/` | App icon, `PixelMark` imageset, `PixelMarkBadge` (menu-bar glyph with a sync badge dot) |

---

## Layer 1 — App lifecycle (`PeteKM/App/`)

`PeteKMApp.swift` is an `@NSApplicationDelegateAdaptor` shell. Its only Scene is
`Settings`; the real window is AppKit-owned.

| File | Role |
| --- | --- |
| `AppDelegate.swift` | Background-resident lifecycle. Builds `RootView`, owns window controller, hotkey monitor, menu-bar item. `applicationShouldTerminateAfterLastWindowClosed → false` (§8.7). Keyboard ⌘Q hides instead of quitting (`applicationShouldTerminate`); mouse Quit, logout, and Sparkle still quit — after a 5s departure sync, and a user-chosen Quit with notes still unsent gets one alert (sync v2 §9.2; `isSystemQuit` reads the quit reason). Mirrors `AutoSync` status into the menu bar. |
| `AppServices.swift` | `AppServices.shared` — the long-lived stores (`FolderStore`, `AppSettings`, `SyncLaunchCheck`, `AutoSync`). Honors `PETEKM_UITEST_FOLDER` env var to run against a scratch folder. |
| `StickyWindowController.swift` | One sticky window. `summon()`, float-on-top, hide-not-close (§8.6). Owns the app's `Notification.Name` events, including `.peteKMSummonWindow` (Settings lives in its own window, so an action there must summon the sticky). |
| `GlobalHotKeyMonitor.swift` + `KeyCombo.swift` | System-wide show/hide shortcut (§8.2). Needs Accessibility permission. |
| `MenuBarController.swift` | Menu-bar item; visibility rule paired with dock-icon setting (§8.8). While automatic sync is on: a disabled status row + **Sync Now** at the top, and the `PixelMarkBadge` glyph when the window dot would show. |
| `ShortcutRecorder.swift` | SwiftUI key-combo recorder used in Settings. |
| `RootView.swift` | Switches on `FolderStore.State`: `.unset` → onboarding, `.missing` → recovery, `.ready` → `DailyStickyView`. |

## Layer 2 — Files & folder (`PeteKM/Files/`)

| File | Role |
| --- | --- |
| `PeteKMFolder.swift` | **Start here.** Value type deriving every managed path from a root: `daily/`, `library/`, `.claude/skills/`, `INDEX.md`, `CLAUDE.md`, `AGENTS.md`, `INBOX.md`, `.petekm-state.json`, `.gitignore`. `dailySticky(for:)`, `dailyFilename(for:)` → `YYYY-MM-DD.md`. |
| `FolderStore.swift` | `@Observable`. Holds active folder; persists a security-scoped bookmark in `UserDefaults`. `State = .unset / .ready(PeteKMFolder) / .missing(lastKnownPath:)` (§19.6). |
| `FileWriting.swift` | Atomic write (temp + rename), read, exists, and `backUp(_:into:)` → `.petekm-backups/<name>.bak-YYYY-MM-DD` with a disambiguating counter (§6.5, §19.2). |
| `FolderInitializer.swift` | Creates the folder shape. `ExistingFilePolicy = .keep` (onboarding — never overwrite) or `.backUpThenReplace` (Refresh Agent Files, §6.5). Returns a `Report` (created/kept/backedUp/failed) with a terse `summary`. |
| `AgentTemplates.swift` | ~480L of template strings the app writes into a user's folder: `INDEX.md`, `CLAUDE.md`, `AGENTS.md`, `.gitignore`, state, and 5 skills. **Editing these is a product-content change, not an app change.** |
| `DirectoryWatcher.swift` | FSEvents/DispatchSource watcher; drives external-change detection and index refresh. |
| `GitSupport.swift` | Shells out to `git`. Two-way Sync: commit → fetch → pull --rebase when behind → push (`context/sync/spec.md` §5.1). Never force-pushes; a conflicting rebase is aborted and reported. `SyncOutcome` enum where every case is survivable, each with a plain `notice(editorName:)` string. `aheadBehind(_:)` parses `rev-list --left-right --count` and returns nil without an upstream. |
| `AutoSync.swift` | Sync v2 coordinator (`context/sync-v2/`). `@MainActor @Observable`. One entry point, `request(_ trigger:)`: arrival (folder ready, wake, summon, network regained, 5-min presence poll, new day) and departure (hide, 60s edit idle, sleep, quit) triggers, coalesced to one follow-up run, with back-off for offline / push failure / conflict pause. Publishes `SyncStatus`, `statusClock` (30s tick), `otherDeviceLast`, `lastRunStderr`, one-shot `lastNotice`. Off → v1 manual behavior. |
| `SyncStatusCopy.swift` | Pure copy for `SyncStatus`: `line(now:)` (§8.4), `dot(now:)` with the 2-minute rule (§8.1), `SyncTime.phrase` (relative / clock / date), `otherDeviceLine`, and the earlier-notes condition (§9.2.3). |
| `SyncLaunchCheck.swift` | Only while "Sync automatically" is off. `@Observable`, once per app process: fetch, compare with `aheadBehind`, and show the dismissible "Changes to sync." banner only when `ahead > 0 || behind > 0`. Every failure — no git, not a repository, no upstream, unreachable remote — is silent (`context/sync/spec.md` §4.3). |

### Generated folder shape

What `FolderInitializer` produces in a user's PeteKM folder (spec §5):

```
daily/YYYY-MM-DD.md          immutable ledger, AI never writes
library/**.md                mutable knowledge, AI curates
.claude/skills/petekm-{process,rebuild-index,organize,status}/SKILL.md
INDEX.md   CLAUDE.md   AGENTS.md   INBOX.md
.petekm-state.json           disposable agent state
.petekm-scratch.md           Scratch pane; not a note (see Layer 3b)
.gitignore
.gitattributes               daily/*.md merge=union (sync v2 §7)
```

### State outside the folder

Everything the app keeps outside a user's PeteKM folder. All of it is derived or
preference data — none of it holds note content (invariant 1), and deleting any of it
costs at most a rescan.

| Location | Written by | Holds | Safe to delete |
| --- | --- | --- | --- |
| `UserDefaults` (`com.petekm.PeteKM`) | `AppSettings`, `FolderStore` | `petekm.*` preferences, the security-scoped folder bookmark + last known path, per-file cursor positions | Yes — resets the app to first run |
| `~/Library/Application Support/PeteKM/SearchIndex/<digest>.json` | `SearchIndex.save` | Cached index (path/mtime/size/**text**) for one folder; `<digest>` is the first 16 hex of SHA-256 over the folder's absolute path, so each folder gets its own file and stale ones are never read | Yes — rebuilt on next scan |

Two consequences worth knowing. The index cache **contains note text**, so it outlives a
deleted notes folder until removed by hand. And because the digest is over the folder
*path*, moving a folder silently orphans its cache rather than invalidating it.

**Full reset** (quit first — the app is background-resident and rewrites its plist on exit):

```bash
osascript -e 'tell application "PeteKM" to quit'
defaults delete com.petekm.PeteKM
rm -rf ~/Library/Application\ Support/PeteKM
```

## Layer 3 — Daily Sticky (`PeteKM/Daily/`)

The capture loop. Read `DailySession` first.

| File | Role |
| --- | --- |
| `DailySession.swift` | `@MainActor @Observable` orchestrator. `pruneIfBlank` deletes a blank Daily Sticky on flush or on leaving it — a day written entirely in Scratch leaves no file (never a Library file, never dirty or conflicted, blank in memory *and* on disk). Owns `openedDate`, the open `StickyDocument`, New Day prompt state, `openedAsToday` / `openedIsDaily` (Library files open in the same editor, §10.2), `revealRange` for search hits, and directory watching. |
| `StickyDocument.swift` | One open file. `text` is a working copy; `savedText` mirrors disk. Debounced (600ms) atomic autosave. `Conflict(diskText:)` + `ConflictChoice = .keepMine/.keepDisk/.keepBoth` (§8.4, §8.5, §19.3, §19.4). |
| `DailyFiles.swift` / `DailyDate.swift` | Filename ↔ date, long-form display strings. `isBlankSticky` — nothing but whitespace and, at most, that day's own heading; `mostRecentSticky` steps over blank days so carry-forward is not swallowed by a day spent only in Scratch. |
| `NewDayComposer.swift` | `NewDayStart` = `.scratch / .carryForwardHeaders / .defaultHeaders`; builds the opening text (§7.2–7.6). |
| `NewDayPrompt.swift` | The tiny "ask each day" prompt (§7.3). |
| `MarkdownHeadings.swift` | Heading parse used by carry-forward. |
| `SyncStatusDot.swift` | The window's 6pt sync dot (top-trailing) and its popover: status line, other-Mac line, **Sync Now**, **Details…** (last run's stderr — the only place git output appears). |
| `DailyStickyView.swift` | Main screen. Wires `DailySession` + `EditorController` + `PaletteModel` + `ScratchStore`, paints the window background, hosts the conflict alert, TOC, the transient notice line, and the dismissible "Changes to sync." row from `SyncLaunchCheck` (no counts, no git words). |

## Layer 3b — Scratch (`PeteKM/Scratch/`)

Durable but temporary: one file, same content every day, deliberately outside the
daily/library contract. Not a note, and never becomes one.

| File | Role |
| --- | --- |
| `ScratchStore.swift` | `@MainActor @Observable`. Wraps a `StickyDocument` on `folder.scratch` (`.petekm-scratch.md`), watches the root, `clear()` backs up before emptying. Nothing is date-keyed — that is why it carries over. |
| `ScratchPaneView.swift` | Collapsible pane under the editor: strip (first line when collapsed), drag-to-resize handle, smaller `MarkdownEditor`, clear button. ⌘⇧S toggles. |
| `ScratchTexture` (same file) | The pane's ground — a wash plus a tiled 7pt dot grid, both pure alpha so a transparent window stays transparent. Shifts light or dark off `AppSettings.groundIsDark(systemIsDark:)`, which prefers the user's custom background color over the system appearance. Tiles are cached; the pane's body re-runs on every keystroke. |

**Four independent exclusions.** Break one and the feature's promise is broken:

1. Dot-prefixed → `SearchIndexBuilder.scan` skips it (`SearchIndex.swift`) → never searched,
   never in Open Library File…, never in the TOC.
2. In `.gitignore` (with `.petekm-backups/`) → `Sync` never commits it. Folders created before the
   feature are repaired by `FolderInitializer.ensureScratchIgnored` on window open.
3. Outside `daily/` and `library/` → outside every path the agent is pointed at.
4. Named as off-limits in the `CLAUDE.md` and `AGENTS.md` templates (`AgentTemplates.swift`).

Plain text on disk, not encrypted. The Guide and Settings copy say so; don't imply otherwise.

## Layer 4 — Editor (`PeteKM/Editor/`)

Custom `NSTextView`, not `TextEditor`. Syntax markers stay on screen.

| File | Role |
| --- | --- |
| `MarkdownEditor.swift` | `NSViewRepresentable` + `EditorController` (weak handle to the text view for `reveal(_:)`, `focusEditor()`, and initial cursor restore). |
| `MarkdownTextView.swift` | `NSTextView` subclass — key handling, list/pair behavior hookup. |
| `MarkdownSyntaxHighlighter.swift` | `MarkdownStyle` + the styling pass: heading size hierarchy, bold/italic, list indent — applied *over* visible `#`/`**`/`-` (§9.1–9.2). |
| `EditorEdits.swift` | Auto-close pairs, list-marker continuation (§9.3). Both settings-gated. |
| `MarkdownOutline.swift` + `TableOfContentsView.swift` | Outline entries → jump list (§9.4). |
| `CursorMemory.swift` | Per-file caret position across opens (§8.3). |

## Layer 5 — Palette & search (`PeteKM/Palette/`, `PeteKM/Search/`)

| File | Role |
| --- | --- |
| `PaletteCommand.swift` | `PaletteCommandID` catalog — the canonical command list, grouped, with display titles. Editor name is looked up, never hard-coded. `PaletteOutcome` is what a command asks the host view to do. |
| `PaletteModel.swift` | ~450L. Modes (commands / file open / insert path / search / date), row building, selection, availability gating (`isGitRepository`, `isEditorAvailable`, `isDocumentOpen`), `PaletteDateInput.parse` for "Open Date…", the `"/ "` prefix shortcut (`libraryFileShortcut`) that jumps the command list straight into file open, and `LibraryPaths.destinations` — folders (derived from indexed file paths) plus files, typed into the note as `-> library/…` via `PaletteOutcome.insertText` → `EditorController.insert`. |
| `CommandPaletteView.swift` | The overlay UI. |
| `SearchIndex.swift` | `@Observable`. **Disposable** index (`IndexedFile` = path/mtime/size/text). Incremental rescan off the main actor; watcher-driven with a time-based fallback for unwatched new folders. Rebuildable from disk by definition (§2.2). Cached to `~/Library/Application Support/PeteKM/SearchIndex/<sha256-prefix>.json`, keyed on the folder's path — see [State outside the folder](#state-outside-the-folder). |
| `SearchQuery.swift` / `FuzzyMatch.swift` | Ranking + `SearchResult` (used to drive `DailySession.revealRange`), and fuzzy filename matching for file-open. |

### Command catalog (user-facing surface)

`Open Daily Sticky` · `Open Previous Daily Sticky` · `Open Date…` · `Open Scratch` ·
`Search All PeteKM…` · `Open Library File…` · `Insert Library Path…` · `Open Library Index` ·
`Open Library in <editor>` · `Open PeteKM Folder in <editor>` ·
`Open Current File in <editor>` · `Review Inbox` · `Open Terminal in PeteKM Folder` ·
`Reveal PeteKM Folder in Finder` · `Sync` · `Settings`

## Layer 6 — External tools (`PeteKM/External/`)

| File | Role |
| --- | --- |
| `ExternalEditor.swift` | `protocol ExternalEditor` + `VSCodeEditor` + `ExternalEditorProvider.current`. Availability-checked; absence is a notice, never a block (§15.3). |
| `ExternalTools.swift` | Finder reveal, Terminal-at-folder via `NSWorkspace`. Each failure has a fixed terse notice string. |

## Layer 7 — Settings & updates (`PeteKM/Settings/`)

| File | Role |
| --- | --- |
| `AppSettings.swift` | `@Observable`, `UserDefaults`-backed. Keys are namespaced `petekm.*`: `dailyStartBehavior`, `defaultHeaders`, `showDateHeading`, `globalShortcut`, `hasCompletedOnboarding`, `editorFontName/Size/LineSpacing`, `showTableOfContents`, `autoClosePairs`, `continueListMarkers`, `scratchVisible`, `scratchHeight`, `floatOnTop`, `hideDockIcon`, `hideMenuBarItem`, `syncAutomatically`, `agentFilesNoticeShownFor`, `automaticUpdateChecks`, `backgroundHex`, `backgroundOpacity`, `textHex` (window color/transparency + editor text color, all in the Editor tab; `HexColor` parser lives here; window is non-opaque, `DailyStickyView` paints the background). **No AI settings exist, now or later (§18.8).** |
| `SettingsView.swift` | Tabs: General, Daily Sticky (incl. Scratch), Editor (+ Folder, Guide, Updates panes). |
| `FolderSettingsView.swift` | Change folder, Refresh Agent Files, Git: Initialize Repository / Set Remote / Sync (§18.9), the "Sync automatically" toggle and its status row. |
| `GuideSettingsView.swift` | In-app explanation of the daily/library contract, plus **Show Onboarding Again** (see Layer 8) and "Using Two Macs" (sync v2 §9.4). |
| `UpdateController.swift` | All Sparkle code behind `#if canImport(Sparkle)`. Reads `SUFeedURL`; inert without it. Never auto-installs. |
| `UpdateSettingsView.swift` | The Updates pane — check-now button and the automatic-checks toggle. |

## Layer 8 — Onboarding (`PeteKM/Onboarding/`)

`OnboardingModel` + `OnboardingView` (§6). Seven steps: `.welcome` → `.chooseFolder` →
`.structure` → `.dailyPreference` → `.claudeCode` → `.skills` → `.setUpLibrary`. Pick or create a
folder, initialize it with `.keep` policy (existing files are never overwritten), set the
daily-start behavior. `MissingFolderView` handles `FolderStore.State.missing` — relocate
or re-pick (§19.6).

`.skills` is the one place the four `/petekm-*` commands are explained before the
folder is handed over — what each does and when to reach for it. It runs nothing; the
skills live in the user's folder and are typed to their agent in a terminal.

`.setUpLibrary` is the last step and writes nothing. It is the one place the app talks
about Library *shape*: build the folders you think in (PARA named only as an example,
never created), copy existing Markdown into `library/` rather than `daily/`, and run
`/petekm-rebuild-index` afterwards. **The app imposes no folder system** — `library/`
starts empty and only the user or their agent shapes it. Three hand-off buttons reuse
`ExternalTools` and `ExternalEditorProvider.current`; each failure sets `toolNotice` and
nothing blocks (§15.3).

Replayable: Settings → Guide → **Show Onboarding Again** sets
`hasCompletedOnboarding = false` and posts `.peteKMSummonWindow`. `RootView` drops the
finished model on that change so the flow restarts at `.welcome`, and the folder step
offers **Keep using this folder** (`keepCurrentFolder()`, same `.keep` adoption) when a
folder is already set — otherwise the replay dead-ends there.

## Design system (`PeteKM/DesignSystem/`)

`DS.swift` — `DS.Color` (light/dark dynamic pairs), `DS.Text` (system faces, 10–28pt),
`DS.Space` / `DS.Radius` / `DS.Duration`. `PixelMark.swift` — pixel-art mark + wordmark (asset files
internally named `robopete*`), the only custom branding (DESIGN §3, §6). Prefer native
controls over custom chrome.

---

## Tests (`PeteKMTests/`, Swift Testing)

| File | Covers |
| --- | --- |
| `DailyStickyTests.swift` | Largest. Session reopen semantics, New Day composition, autosave, conflict resolution. |
| `FolderInitializerTests.swift` | Folder shape, zero-padded filenames, keep-vs-backup policy. |
| `SearchTests.swift` | Index scan, ranking, fuzzy match, date parsing. |
| `ScratchTests.swift` | Scratch path, the four exclusions, gitignore migration, persistence, clear-with-backup. |
| `EditorTests.swift` | Highlighter, auto-close, list continuation, outline. |
| `SettingsTests.swift` | Defaults round-trip, start-behavior. |
| `ExternalToolsTests.swift` | Editor/Terminal/Git outcome branches. |
| `AppLifecycleTests.swift` | `KeyCombo` encode/decode. |
| `GitSyncTests.swift` | Sync v2 engine against real temp repos (bare origin + two clones): run sequence, guards, trailer, union merge, timeouts. |
| `AutoSyncTests.swift` | Coordinator with scripted git, fake clock/network: coalescing, back-off, notices, toggle, Pre-New-Day; one two-clone integration test. |
| `SyncStatusTests.swift` | Status-line copy, dot + 2-minute rule, time phrases, earlier-notes condition, system-quit detection. |

`PeteKMUITests/` drives a real capture loop against a scratch folder via
`PETEKM_UITEST_FOLDER`.

---

## Where to look first, by task

| Task | Start at |
| --- | --- |
| "Does feature X exist / is it tested?" | `context/ACCEPTANCE.md` |
| Change what a new day starts with | `NewDayComposer.swift`, `AppSettings.dailyStartBehavior` |
| Anything touching disk writes | `FileWriting.swift` → `StickyDocument.swift` |
| Anything touching Scratch | `ScratchStore.swift` → the exclusions list in Layer 3b |
| Add a palette command | `PaletteCommand.swift` (catalog) → `PaletteModel.commit` → `PaletteOutcome` handler in `DailyStickyView` |
| Change what the app writes into a user's folder | `AgentTemplates.swift` (**product content**) |
| Editor rendering or key behavior | `MarkdownSyntaxHighlighter.swift`, `EditorEdits.swift`, `MarkdownTextView.swift` |
| New preference | `AppSettings.Keys` → the matching pane in `Settings/` |
| Window / hotkey / dock behavior | `AppDelegate.swift`, `StickyWindowController.swift` |
| Shipping a build | `context/DISTRIBUTION.md`, `scripts/release.sh` |

## Known drift

`context/spec.md` §17 (Git and Version History) is superseded in full by
`context/sync/spec.md` — §17 still describes a push-only `Git Sync`. Trust the sync spec
and the code.
