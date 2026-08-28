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
| `Files/` | Folder shape, bookmarks, atomic writes, initialization, templates, Git, watchers |
| `Onboarding/` | First run + missing-folder recovery |
| `Palette/` | ⌘K command palette, command catalog |
| `Search/` | Disposable full-text index, fuzzy match, ranking |
| `Settings/` | Preferences model + tabbed Settings window + Sparkle |
| `DesignSystem/` | `DS` tokens, PixelMark/Wordmark |
| `Assets.xcassets/` | App icon, `PixelMark` imageset |

---

## Layer 1 — App lifecycle (`PeteKM/App/`)

`PeteKMApp.swift` is an `@NSApplicationDelegateAdaptor` shell. Its only Scene is
`Settings`; the real window is AppKit-owned.

| File | Role |
| --- | --- |
| `AppDelegate.swift` | Background-resident lifecycle. Builds `RootView`, owns window controller, hotkey monitor, menu-bar item. `applicationShouldTerminateAfterLastWindowClosed → false` (§8.7). |
| `AppServices.swift` | `AppServices.shared` — the two long-lived stores (`FolderStore`, `AppSettings`). Honors `PETEKM_UITEST_FOLDER` env var to run against a scratch folder. |
| `StickyWindowController.swift` | One sticky window. `summon()`, float-on-top, hide-not-close (§8.6). Posts `Notification.Name` events. |
| `GlobalHotKeyMonitor.swift` + `KeyCombo.swift` | System-wide show/hide shortcut (§8.2). Needs Accessibility permission. |
| `MenuBarController.swift` | Menu-bar item; visibility rule paired with dock-icon setting (§8.8). |
| `ShortcutRecorder.swift` | SwiftUI key-combo recorder used in Settings. |
| `RootView.swift` | Switches on `FolderStore.State`: `.unset` → onboarding, `.missing` → recovery, `.ready` → `DailyStickyView`. |

## Layer 2 — Files & folder (`PeteKM/Files/`)

| File | Role |
| --- | --- |
| `PeteKMFolder.swift` | **Start here.** Value type deriving every managed path from a root: `daily/`, `library/`, `.claude/skills/`, `INDEX.md`, `CLAUDE.md`, `AGENTS.md`, `INBOX.md`, `.petekm-state.json`, `.gitignore`. `dailySticky(for:)`, `dailyFilename(for:)` → `YYYY-MM-DD.md`. |
| `FolderStore.swift` | `@Observable`. Holds active folder; persists a security-scoped bookmark in `UserDefaults`. `State = .unset / .ready(PeteKMFolder) / .missing(lastKnownPath:)` (§19.6). |
| `FileWriting.swift` | Atomic write (temp + rename), read, exists, and `backUp(_:)` → `<name>.bak-YYYY-MM-DD` with a disambiguating counter (§6.5, §19.2). |
| `FolderInitializer.swift` | Creates the folder shape. `ExistingFilePolicy = .keep` (onboarding — never overwrite) or `.backUpThenReplace` (Refresh Agent Files, §6.5). Returns a `Report` (created/kept/backedUp/failed) with a terse `summary`. |
| `AgentTemplates.swift` | ~450L of template strings the app writes into a user's folder: `INDEX.md`, `CLAUDE.md`, `AGENTS.md`, `.gitignore`, state, and 5 skills. **Editing these is a product-content change, not an app change.** |
| `DirectoryWatcher.swift` | FSEvents/DispatchSource watcher; drives external-change detection and index refresh. |
| `GitSupport.swift` | Shells out to `git`. One-way only: commit + push, never pull/merge/rebase (§17.2). `SyncOutcome` enum where every case is survivable, each with a plain `notice` string. |

### Generated folder shape

What `FolderInitializer` produces in a user's PeteKM folder (spec §5):

```
daily/YYYY-MM-DD.md          immutable ledger, AI never writes
library/**.md                mutable knowledge, AI curates
.claude/skills/petekm-{process-today,process-date,rebuild-index,organize,status}/SKILL.md
INDEX.md   CLAUDE.md   AGENTS.md   INBOX.md
.petekm-state.json           disposable agent state
.gitignore
```

## Layer 3 — Daily Sticky (`PeteKM/Daily/`)

The capture loop. Read `DailySession` first.

| File | Role |
| --- | --- |
| `DailySession.swift` | `@MainActor @Observable` orchestrator. Owns `openedDate`, the open `StickyDocument`, New Day prompt state, `openedAsToday` / `openedIsDaily` (Library files open in the same editor, §10.2), `revealRange` for search hits, and directory watching. |
| `StickyDocument.swift` | One open file. `text` is a working copy; `savedText` mirrors disk. Debounced (600ms) atomic autosave. `Conflict(diskText:)` + `ConflictChoice = .keepMine/.keepDisk/.keepBoth` (§8.4, §8.5, §19.3, §19.4). |
| `DailyFiles.swift` / `DailyDate.swift` | Filename ↔ date, long-form display strings. |
| `NewDayComposer.swift` | `NewDayStart` = `.scratch / .carryForwardHeaders / .defaultHeaders`; builds the opening text (§7.2–7.6). |
| `NewDayPrompt.swift` | The tiny "ask each day" prompt (§7.3). |
| `MarkdownHeadings.swift` | Heading parse used by carry-forward. |
| `DailyStickyView.swift` | Main screen (~300L). Wires `DailySession` + `EditorController` + `PaletteModel`, hosts the conflict alert, TOC, and the transient notice line. |

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
| `PaletteModel.swift` | ~400L. Modes (commands / file open / search / date), row building, selection, availability gating (`isGitRepository`, `isEditorAvailable`), and `PaletteDateInput.parse` for "Open Date…". |
| `CommandPaletteView.swift` | The overlay UI. |
| `SearchIndex.swift` | `@Observable`. **Disposable** in-memory index (`IndexedFile` = path/mtime/size/text). Incremental rescan off the main actor; watcher-driven with a time-based fallback for unwatched new folders. Rebuildable from disk by definition (§2.2). |
| `SearchQuery.swift` / `FuzzyMatch.swift` | Ranking + `SearchResult` (used to drive `DailySession.revealRange`), and fuzzy filename matching for file-open. |

### Command catalog (user-facing surface)

`Open Daily Sticky` · `Open Previous Daily Sticky` · `Open Date…` ·
`Search All PeteKM…` · `Open Library File…` · `Open Library Index` ·
`Open Library in <editor>` · `Open PeteKM Folder in <editor>` ·
`Open Current File in <editor>` · `Review Inbox` · `Open Terminal in PeteKM Folder` ·
`Reveal PeteKM Folder in Finder` · `Git Sync` · `Settings`

## Layer 6 — External tools (`PeteKM/External/`)

| File | Role |
| --- | --- |
| `ExternalEditor.swift` | `protocol ExternalEditor` + `VSCodeEditor` + `ExternalEditorProvider.current`. Availability-checked; absence is a notice, never a block (§15.3). |
| `ExternalTools.swift` | Finder reveal, Terminal-at-folder via `NSWorkspace`. Each failure has a fixed terse notice string. |

## Layer 7 — Settings & updates (`PeteKM/Settings/`)

| File | Role |
| --- | --- |
| `AppSettings.swift` | `@Observable`, `UserDefaults`-backed. Keys are namespaced `petekm.*`: `dailyStartBehavior`, `defaultHeaders`, `showDateHeading`, `globalShortcut`, `hasCompletedOnboarding`, `editorFontName/Size/LineSpacing`, `showTableOfContents`, `autoClosePairs`, `continueListMarkers`, `floatOnTop`, `hideDockIcon`, `hideMenuBarItem`, `automaticUpdateChecks`, `backgroundHex`, `backgroundOpacity`, `textHex` (window color/transparency + editor text color, all in the Editor tab; `HexColor` parser lives here; window is non-opaque, `DailyStickyView` paints the background). **No AI settings exist, now or later (§18.8).** |
| `SettingsView.swift` | Tabs: General, Daily Sticky, Editor (+ Folder, Guide, Updates panes). |
| `FolderSettingsView.swift` | Change folder, Refresh Agent Files, Git init/status. |
| `GuideSettingsView.swift` | In-app explanation of the daily/library contract. |
| `UpdateController.swift` | All Sparkle code behind `#if canImport(Sparkle)`. Reads `SUFeedURL`; inert without it. Never auto-installs. |

## Layer 8 — Onboarding (`PeteKM/Onboarding/`)

`OnboardingModel` + `OnboardingView` (§6): pick or create a folder, initialize it with
`.keep` policy (existing files are never overwritten), set the daily-start behavior.
`MissingFolderView` handles `FolderStore.State.missing` — relocate or re-pick (§19.6).

## Design system (`PeteKM/DesignSystem/`)

`DS.swift` — `DS.Color` (light/dark dynamic pairs), `DS.Font` (system faces, 10–28pt),
spacing/radius tokens. `PixelMark.swift` — pixel-art mark + wordmark (asset files
internally named `robopete*`), the only custom branding (DESIGN §3, §6). Prefer native
controls over custom chrome.

---

## Tests (`PeteKMTests/`, Swift Testing)

| File | Covers |
| --- | --- |
| `DailyStickyTests.swift` | Largest. Session reopen semantics, New Day composition, autosave, conflict resolution. |
| `FolderInitializerTests.swift` | Folder shape, zero-padded filenames, keep-vs-backup policy. |
| `SearchTests.swift` | Index scan, ranking, fuzzy match, date parsing. |
| `EditorTests.swift` | Highlighter, auto-close, list continuation, outline. |
| `SettingsTests.swift` | Defaults round-trip, start-behavior. |
| `ExternalToolsTests.swift` | Editor/Terminal/Git outcome branches. |
| `AppLifecycleTests.swift` | `KeyCombo` encode/decode. |

`PeteKMUITests/` drives a real capture loop against a scratch folder via
`PETEKM_UITEST_FOLDER`.

---

## Where to look first, by task

| Task | Start at |
| --- | --- |
| "Does feature X exist / is it tested?" | `context/ACCEPTANCE.md` |
| Change what a new day starts with | `NewDayComposer.swift`, `AppSettings.dailyStartBehavior` |
| Anything touching disk writes | `FileWriting.swift` → `StickyDocument.swift` |
| Add a palette command | `PaletteCommand.swift` (catalog) → `PaletteModel.commit` → `PaletteOutcome` handler in `DailyStickyView` |
| Change what the app writes into a user's folder | `AgentTemplates.swift` (**product content**) |
| Editor rendering or key behavior | `MarkdownSyntaxHighlighter.swift`, `EditorEdits.swift`, `MarkdownTextView.swift` |
| New preference | `AppSettings.Keys` → the matching pane in `Settings/` |
| Window / hotkey / dock behavior | `AppDelegate.swift`, `StickyWindowController.swift` |
| Shipping a build | `context/DISTRIBUTION.md`, `scripts/release.sh` |

## Known drift

`CLAUDE.md` still describes the repo as "the stock Xcode SwiftUI+SwiftData template".
That is stale — all 7 plan phases are complete and SwiftData is gone. Trust this map
and the code over that sentence.
