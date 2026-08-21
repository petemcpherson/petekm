# Acceptance Pass — spec §24 and §22

Walked at the end of Phase 7. Each line names where the behavior lives, and the
automated coverage that guards it.

## Daily capture (§24)

| Criterion | Where | Covered by |
| --- | --- | --- |
| Global shortcut reaches today's Daily Sticky from any app | `GlobalHotKeyMonitor`, `StickyWindowController.summon()` | `AppLifecycleTests` (KeyCombo), manual (hotkey needs Accessibility) |
| Repeated opens return to the same file | `DailySession` | `DailySessionTests/reopensTheSameFileForTheSameDay` |
| Stored as `daily/YYYY-MM-DD.md` | `DailyFiles`, `PeteKMFolder` | `FolderInitializerTests/dailyFilenamesAreZeroPadded` |
| Typing is autosaved | `StickyDocument` (debounced, atomic) | `StickyDocumentTests/autosaveFiresWithoutAManualSave` |
| No manual naming | `DailyFiles` — filenames are derived from the date | — |
| Blank / carry-forward / default-header starts | `NewDayComposer`, `AppSettings.dailyStartBehavior` | `DailySessionTests`, `SettingsTests` |
| Carry-forward copies headings only | `MarkdownHeadings`, `NewDayComposer` | `DailySessionTests/carryForwardUsesTheMostRecentPriorSticky` |

## Markdown ownership

| Criterion | Where |
| --- | --- |
| Content is ordinary Markdown on disk | `FileWriting`, `StickyDocument` — no database anywhere in the target |
| Folder readable/editable without the app | Plain `.md` tree written by `FolderInitializer` |
| No proprietary store required for recovery | Only derived data is `SearchIndex` (Application Support) and `AppSettings` |
| Caches rebuildable from the filesystem | `SearchTests/rebuildingFromAnEmptyIndexProducesTheSameContent`, `indexLivesOutsideThePeteKMFolder` |

## Editor

| Criterion | Where | Covered by |
| --- | --- | --- |
| Markdown syntax stays visible | `MarkdownSyntaxHighlighter` — attributes only, never rewrites text | `EditorTests` |
| Live heading hierarchy | `MarkdownStyle.heading(_:)` | `EditorTests/headingsAreSizedByLevelWithSyntaxIntact` |
| Bold/italic styling | `MarkdownSyntaxHighlighter.styleInline` | `EditorTests/boldAndItalicSpansKeepTheirMarkers` |
| Clear bullet indentation | `paragraphStyle(indentLevels:)` | `EditorTests/nestedListsIndentByDepth` |
| Auto-close conveniences without format change | `MarkdownTextView` | `EditorTests` auto-close and list-continuation tests |
| Chosen font applies everywhere, missing font falls back | `MarkdownStyle.font(size:weight:)` | `SettingsTests/chosenFontIsUsedForBodyAndHeadings`, `missingFontFallsBackInsteadOfBreakingTheEditor` |

## Search

Filename/path/heading/body search, snippets, keyboard navigation and jump-to-match
live in `SearchIndex`, `SearchQuery` and `CommandPaletteView`; covered by
`SearchTests` (including scenario C's "certificate auth" shape). No AI is
involved in any path.

## Library & external tools

`ExternalTools` / `ExternalEditor` open the folder, the Library, or the current file
in VS Code, Finder, or Terminal, and every one degrades to a notice when the tool is
missing (`ExternalToolsTests`). The app deliberately offers no Library IDE.

## Librarian workflow & agent compatibility

Shipped entirely as folder content: `AgentTemplates` writes `CLAUDE.md`, `AGENTS.md`
and five `.claude/skills/petekm-*` skills, with the immutable-ledger rule, provenance,
uncertainty and Inbox policy in `AGENTS.md`. Guarded by
`FolderInitializerTests/everySkillHasFrontmatterWithNameAndDescription` and
`templatesStateTheImmutableLedgerRule`. The app contains zero AI functionality — it
never invokes, monitors, or parses an agent.

## Safety

| Criterion | Where | Covered by |
| --- | --- | --- |
| AI never modifies Daily Stickies | Agent templates (policy lives in the folder, not app code) | `FolderInitializerTests` |
| Setup never silently overwrites | `FolderInitializer` `.keep` policy; Refresh backs up first | `neverOverwritesExistingFiles`, `refreshBacksUpDifferingAgentFiles`, `refreshNeverTouchesNotesOrTheIndex` |
| External edits are normal | `DirectoryWatcher` + `StickyDocument` reload/conflict | `externalChangeReloadsSilentlyWhenClean`, `bothSidesChangedRaisesAConflict` |
| Git failures never block capture | `GitSupport.sync` returns an outcome; Settings/palette show a notice | `syncKeepsTheLocalCommitWhenPushFails` |
| App caches/state deletable | `SearchIndex` in Application Support, keyed by folder | `SearchTests/indexLivesOutsideThePeteKMFolder` |

## Scenarios §22 A–G

- **A. Daily capture loop** — shortcut → today's file → type → hide. Automated where
  possible (`DailySessionTests`, `StickyDocumentTests`); the global-shortcut leg is
  manual because Accessibility permission can't be granted by a test runner.
- **B. New day** — all four Daily Start Behaviors, `DailySessionTests`.
- **C. Search** — `SearchTests` covers hits across `daily/` and `library/` with
  snippets and a jump range.
- **D. Fuzzy file open** — `FuzzyMatch` tests.
- **E. Filing with an agent** — outside the app by design; the folder ships the skills.
- **F. External edits / conflicts** — `StickyDocumentTests` conflict paths.
- **G. Git backup** — `ExternalToolsTests` sync outcomes, one-way only.

## Vocabulary audit (DESIGN §2, §39)

`SettingsTests/settingsCopyUsesProductVocabulary` asserts no "journal", "entry",
"vault", "knowledge base", "AI Assistant", "streak", or motivational phrasing in the
shipped copy, and a repo-wide grep over `PeteKM/**/*.swift` returns nothing.

## Known gaps

- **UI tests don't run in this environment.** `PeteKMUITests` drives the
  type → ⌘W → reactivate loop, but `xcodebuild` fails with "Timed out while enabling
  automation mode" — the runner needs interactive Automation permission. Unit tests
  (`PeteKMTests`) all pass.
- **Sparkle isn't linked in the source checkout.** `UpdateController` is behind
  `#if canImport(Sparkle)`; adding the package and the `SUFeedURL` / `SUPublicEDKey`
  Info.plist keys is a release-time step documented in `DISTRIBUTION.md`.
- **Signing/notarization is unverified here**, since it needs a Developer ID
  certificate and a notarytool profile. `scripts/release.sh` encodes the steps.
