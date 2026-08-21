# PeteKM Implementation Plan

Derived from `context/spec.md` (product behavior) and `context/DESIGN.md` (visual/UX). Repo starts from the stock Xcode SwiftUI+SwiftData template — none of the product exists yet.

## Progress Tracker

- [x] Phase 1 — Foundation: strip template, folder access, onboarding & folder initialization
- [ ] Phase 2 — Daily Sticky core: file model, autosave, external-edit safety
- [ ] Phase 3 — Markdown editor experience
- [ ] Phase 4 — App lifecycle: global shortcut, window character, menu bar
- [ ] Phase 5 — Command palette & local search
- [ ] Phase 6 — External tools: VS Code, Terminal, Finder, Git
- [ ] Phase 7 — Settings, agent-file refresh, distribution & updates

---

## Phase 1 — Foundation: strip template, folder access, onboarding & folder initialization — [COMPLETED]

Goal: app launches, user picks or creates a PeteKM folder, folder is fully initialized and agent-ready. No editor yet.

### 1.1 Remove template scaffolding
- Delete `Item.swift`, SwiftData `ModelContainer` wiring, and the template list `ContentView` (spec §2.2 — no database may hold note content; SwiftData may only ever return later for derived index data).
- Restructure app sources into sensible groups (e.g. `App/`, `Onboarding/`, `Files/`, `Editor/`, `Palette/`, `Settings/`).

### 1.2 Sandbox posture & entitlements
- Adopt the decided posture (§20.1): **App Sandbox disabled**, Developer ID direct distribution. Fix `ENABLE_USER_SELECTED_FILES = readonly` in `project.pbxproj`.
- Even without sandbox, keep bookmark-style discipline: persist access to the user-chosen folder via a saved bookmark/path, never assume ambient access elsewhere.

### 1.3 PeteKM folder selection & persistence
- `FolderStore` (or similar): holds the active PeteKM folder URL, persisted across launches.
- Missing-folder recovery panel (§19.6): blocking panel with **Locate Folder…**, **Choose or Create a New Folder…**, **Quit**. Never auto-create at the old path; global shortcut summons this panel until resolved.

### 1.4 First-run onboarding (§6)
- Two paths: **Create new PeteKM folder** (parent picker + name) and **Use existing folder** (inspect contents, offer missing files only).
- Prompt user to set a global shortcut (suggest ⌃⌥Space); none pre-assigned (§8.2).
- Optional Git init offer (§6.3) — skippable, never required.
- Short "Use with Claude Code" panel (§6.4).

### 1.5 Folder initialization & agent-file templates
- Create on setup: `daily/`, `library/`, `.claude/skills/`, `INDEX.md` (placeholder text per §6.2), `CLAUDE.md`, `AGENTS.md`, `.petekm-state.json`, `.gitignore` (§6.2).
- Author the template content itself:
  - `CLAUDE.md` — short orientation, daily/ read-only rule, pointer to `AGENTS.md` (§5.5).
  - `AGENTS.md` — full librarian policy (§5.6, §13): immutable ledger, provenance, preserve uncertainty, prefer updating over proliferation, Inbox rules (§13.12).
  - Five skills under `.claude/skills/`: `petekm-process-today`, `petekm-process-date`, `petekm-rebuild-index`, `petekm-organize`, `petekm-status` — each `SKILL.md` with `name`/`description` frontmatter (§14).
- **Never silently overwrite** existing files during adoption (§19.2): merge, back up, or ask.

**Done when:** fresh launch → onboarding → chosen folder contains the full agent-ready structure; adopting an existing folder never clobbers anything; relaunch remembers the folder; missing-folder panel works.

---

## Phase 2 — Daily Sticky core: file model, autosave, external-edit safety

Goal: today's Daily Sticky exists, opens, saves, and survives concurrent editors. Plain-text editor is acceptable at this phase.

### 2.1 Daily file resolution (§7.1)
- Resolve local calendar date → `daily/YYYY-MM-DD.md`; open if present, else run New Day flow.
- Midnight handling (§7.7): on show/focus after local date change, switch to the new day's flow.

### 2.2 New Day flow (§7.2–7.6)
- Daily Start Behavior setting: Ask each day / Start from scratch / Carry forward headers / Use default headers.
- Tiny keyboard-first "Ask" popup (arrow keys + Enter).
- Carry-forward: parse most recent prior sticky, extract headings only (order + hierarchy), today's H1 date replaces old; silent fallback to scratch when no prior sticky exists.
- Scratch: `# Month D, YYYY` H1 (hard-coded English format per §18.5), toggleable.
- Default headers from settings (plain Markdown).

### 2.3 Autosave & write safety (§8.4, §19.3)
- Debounced autosave on typing; atomic writes (write-temp-then-rename or equivalent) to prevent truncation.
- No manual Save required; no data-loss window on quit/hide.

### 2.4 External-edit detection & conflict flow (§8.5, §19.4)
- Watch the open file (and folder) for external changes — VS Code, Claude Code, Finder are first-class co-writers.
- No unsaved local changes → silent reload.
- Real conflict (both changed) → three-choice dialog: **Keep Mine / Keep Disk / Keep Both** (default Enter = Keep Both, writes `<name> (conflict YYYY-MM-DD HHmm).md`). No merge UI.

### 2.5 Past stickies editable (§8.9)
- Opening a past daily file is fully editable — no lock, no warning. Immutability binds AI only.

**Done when:** shortcut-open returns to the same file all day; new-day flows all work; killing the app mid-typing loses nothing; editing the open file in VS Code reloads or conflicts correctly.

---

## Phase 3 — Markdown editor experience

Goal: editor feels markedly nicer than a raw text area while keeping syntax visible (§9).

### 3.1 Live styling with visible syntax (§9.1–9.2)
- NSTextView-based editor (likely via `NSViewRepresentable`) with syntax-aware attribute styling — not WYSIWYG, markers stay visible.
- Headings sized/weighted by level; bold/italic rendered with markers shown; bullet/nested-list indentation visually clear.

### 3.2 Editing conveniences (§9.3)
- Auto-close quotes/parens/brackets/braces; skip-over when closing char already present.
- List-marker continuation on Return; sensible newline indentation; Tab/Shift-Tab list indent.

### 3.3 Cursor restoration (§8.3)
- Remember cursor/selection per current Daily Sticky across show/hide; fallback to end of document. App state, not note data.

### 3.4 Table of contents (§9.4)
- Heading-derived TOC panel, live-updating, keyboard/mouse navigable, collapsible; no separate stored outline data.

### 3.5 Undo (§9.7)
- Standard in-memory undo/redo only; cleared on quit.

**Done when:** typing the §4.2 example renders with heading hierarchy, bold/italic, indented lists — all markers visible; auto-close and list continuation work; reopen restores cursor; TOC navigates.

---

## Phase 4 — App lifecycle: global shortcut, window character, menu bar

Goal: the defining shortcut → type → hide loop, 30+ times a day (§4.1, §8).

### 4.1 Global show/hide shortcut (§8.2)
- Configurable global hotkey (Carbon `RegisterEventHotKey` or a vetted library): hidden → show + focus today's sticky + restore cursor; active → hide.
- Warn on known system-conflicting choices (e.g. ⌘Space).

### 4.2 Window character (§8.6)
- Sticky-like window: remembers size/position between summons; optional persisted always-on-top float toggle.
- Minimal chrome: date, palette access, optional TOC; editor stays the visual focus (§8.1).

### 4.3 Background residency (§8.7)
- App keeps running when window closes; red close button and ⌘W hide; ⌘Q quits.
- Hide Dock icon toggle (activation-policy switch); enforce "Dock icon and menu-bar item may not both be hidden."

### 4.4 Menu-bar item (§8.8)
- Status item with pixel-mark glyph; menu: Open Daily Sticky, Search All PeteKM…, Reveal PeteKM Folder in Finder, Settings…, Quit PeteKM.

**Done when:** from any app, shortcut summons the editor instantly at the last cursor position; again hides it; survives window close; menu-bar and Dock-icon toggles obey the mutual-visibility rule.

---

## Phase 5 — Command palette & local search

Goal: keyboard-first gateway to everything beyond typing (§10), plus fast deterministic full-text search (§11).

### 5.1 Command palette (§10.1–10.2)
- ⌘K overlay: fuzzy-matched commands, fully keyboard navigable.
- Commands: Open Daily Sticky, Open Date…, Search All PeteKM…, Open Library File…, Open Library / PeteKM Folder / Current File in VS Code, Reveal in Finder, Open Terminal in PeteKM Folder, Review Inbox, Open Library Index, Git Sync (when configured), Settings. (VS Code/Terminal/Git actions wire up in Phase 6 — stub or hide until then.)

### 5.2 File fuzzy-open (§10.3)
- Type-ahead fuzzy match on Library filenames/paths; arrow keys + Enter.

### 5.3 Search index (§11.6, §5.8)
- Disposable full-text index over every `.md` in the folder (excluding `.claude/`, `.git/`), stored in Application Support keyed to the folder — never inside the PeteKM folder. Fully rebuildable from disk; incremental updates from the file watcher.

### 5.4 Search UI (§11.2–11.4)
- Search All PeteKM: results show filename, path, nearest heading, snippet, date for daily files; arrow-key navigation; Enter jumps to the file at the match.
- Review Inbox: opens `INBOX.md`; "Nothing in Inbox." when missing/empty (§13.12).
- Open Date…: date entry/picker → that daily file.

**Done when:** Scenario C works (search "certificate auth" → daily + Library hits with snippets, Enter jumps to match); Scenario D file-open fuzzy match works; deleting the index rebuilds transparently.

---

## Phase 6 — External tools: VS Code, Terminal, Finder, Git

Goal: filesystem-as-interface actions; all failures degrade, never block capture (§12, §15, §17).

### 6.1 VS Code integration (§12)
- Open PeteKM folder / Library / specific file in VS Code (`code` CLI or bundle launch). Graceful failure message when VS Code absent (§18.7); external editor abstracted for future configurability, not hard-coded as data dependency.

### 6.2 Terminal & Finder (§10.2, §15.1)
- Open Terminal in PeteKM Folder — launches Terminal.app at folder root, nothing more (zero AI involvement).
- Reveal PeteKM Folder in Finder.

### 6.3 Git integration (§17)
- Detect repo presence; optional init from Settings/onboarding.
- **Git Sync**: commit (message like `PeteKM backup 2026-08-19 20:45`) then push. One-way: never pull/merge/rebase. Push failure → local commit stands, brief non-blocking notice ("Committed locally. Push failed — resolve in a Git tool.").
- Hard rule: any Git failure never blocks opening or saving the Daily Sticky (§17.4).

**Done when:** all palette external-tool commands work; missing VS Code / missing git / dead remote each degrade with a notice while capture continues untouched.

---

## Phase 7 — Settings, agent-file refresh, distribution & updates

Goal: focused Settings surface (§18), deliberate template refresh, shippable app.

### 7.1 Settings window (§18)
- PeteKM folder: display + change (intentional, safeguarded re-onboarding).
- Global shortcut recorder (with conflict warning).
- Daily Start Behavior + default daily headers (plain Markdown text area) + H1 date-heading toggle.
- Editor prefs (initial small set): font, size, line spacing, TOC visibility, auto-close toggle, list continuation.
- App behavior: hide Dock icon, hide menu-bar item (disabled while Dock hidden), Git enable/init/remote status.
- No AI settings of any kind (§18.8).

### 7.2 Refresh Agent Files (§6.5)
- Manual action: rewrite current templates (`CLAUDE.md`, `AGENTS.md`, skills), backing up any differing existing file first (`AGENTS.md.bak-2026-08-20` style). Templates are otherwise write-once — app updates never touch existing folders.

### 7.3 Distribution & updates (§20.1–20.2)
- Developer ID signing, notarized `.dmg`; no Mac App Store.
- Sparkle: background check, user-approved install; update checks never block capture.

### 7.4 Acceptance pass & tests
- Walk spec §24 acceptance criteria and §22 scenarios A–G end to end.
- Unit tests (Swift Testing) for: daily filename/date logic, carry-forward heading extraction, atomic-save + conflict paths, index rebuild, template no-overwrite; UI tests for shortcut → type → hide loop.
- Vocabulary audit against `DESIGN.md` §2: Daily Sticky / Library / PeteKM exactly; terse copy, no persona, no motivational phrasing.

**Done when:** every §24 criterion checked; signed, notarized build updates itself via Sparkle.

---

## Cross-cutting rules (apply to every phase)

- Markdown on disk is the only canonical store; every cache/index/state is disposable and rebuildable (§2.2, §5.8).
- `daily/` immutable to AI; boundary enforced in shipped agent files, not app code paths (§2.5, §13.3).
- App contains zero AI functionality — no invocation, monitoring, or parsing of agents (§15).
- Capture never blocks on Git, missing tools, or errors (§17.4).
- Never silently overwrite user files (§19.2); atomic writes everywhere (§19.3).
- Native macOS look, near-zero branding; only custom asset is the pixel mark (`DESIGN.md` §3, §6).
