# Product Specification: PeteKM — Local Markdown Second Brain for macOS

**Name:** **PeteKM**  
**Platform:** Native macOS application  
**Primary storage:** User-owned local Markdown files  
**AI posture:** The app contains **zero AI functionality**. All AI filing/organization is done by the user's own filesystem-capable agent (Claude Code initially; Codex-friendly) run in a terminal against the PeteKM folder.  
**Document purpose:** Define what the product is, how it behaves, what data it owns, and the intended user experience. This is a product/behavior specification, **not** an implementation plan.

---

# 0. Open Decisions (answer inline, then fold into spec)

Gap-analysis 2026-08-20. Type answers under each item; once resolved, the decision gets merged into the relevant section and removed from here.

## 0.1 Blocking — these shape the architecture

### 0.1.1 App lifecycle

The global shortcut only works while the app is running. Unspecified:

- Launch at login (on by default? a setting?)?
- Regular Dock app, or agent-style app with no Dock icon (`LSUIElement`)?
- What does the red close button do — hide the window or quit the app?
- What does ⌘Q do?

**Answer:**

i don't care about launch at login, but yes--the app should largely remain open in the background. command-q should ACTUALLY quit, but maybe command-w simply closes. there should be an option in settings to hide the dock icon, ideally.

### 0.1.2 How the app actually runs RoboPete

**Resolved 2026-08-20, folded into §13–§15:** The app has **zero AI functionality** — it never invokes, launches, monitors, or parses any AI agent. Filing happens in the user's own terminal against the PeteKM folder. The app's only role is generating the agent-facing files at onboarding. The "RoboPete" persona is removed everywhere; skills are named `/petekm-*`; librarian policy lives in `AGENTS.md` (no `ROBOPETE.md`); state file is `.petekm-state.json`.

### 0.1.3 "File with RoboPete" vs "Process Daily Sticky" — one command or two?

**Resolved 2026-08-20 — moot.** The app has no AI commands (0.1.2). Which days a skill processes is a skill-authoring detail inside `/petekm-process-today` / `/petekm-process-date`, not app behavior.

## 0.2 Missing decisions

### 0.2.1 Template upgrade path

The app ships `CLAUDE.md`, `AGENTS.md`, and the `.claude/skills/petekm-*` templates. A new app version improves them, but existing PeteKM folders hold old copies and §19.2 forbids overwriting. How do updates propagate — versioned templates with an "update agent files?" prompt, or never touched after initial creation?

**Answer:**

### 0.2.2 Pasted images / attachments

User pastes a screenshot into the Daily Sticky — then what? The spec is Markdown-only and defines no assets folder. Options: unsupported in v1 (paste inserts nothing / plain text only), or an `attachments/` convention with a Markdown image link.

**Answer:**

### 0.2.3 App update mechanism

No App Store (§20.1) means no built-in update channel. Sparkle, manual download, or nothing for v1?

**Answer:**

### 0.2.4 Editing past Daily Stickies in-app

User opens `2026-08-12.md` via **Open Date…** — editable or read-only in the app? The immutability rule targets AI only; §8.5 implies humans may edit history, but the UX intent is unstated.

**Answer:**

### 0.2.5 Menu-bar item: v1 or not?

Spec §25 defers "menu-bar-only mode" to the future; `DESIGN.md` §6/§25/§57 spec a menu-bar glyph as if it exists. Does v1 ship a menu-bar (status) item at all?

**Answer:**

## 0.3 Ambiguities to pin down

### 0.3.1 Search scope of root files

Does **Search All PeteKM** cover `INBOX.md`, `CLAUDE.md`, `AGENTS.md`? §11.1 lists daily + Library only. `INBOX.md` probably should be searchable.

**Answer:**

### 0.3.2 Conflict UI minimum shape

§19.4 requires a "clear conflict path" but describes no choices. Minimum viable answer needed for the plan (e.g. keep mine / keep disk / keep both as a copy).

**Answer:**

### 0.3.3 Git Sync — pull, or one-way?

Git Sync = commit & push. If the remote is ahead, push fails — then what? If v1 never pulls, say so explicitly ("v1 backup is one-way; fix divergence in a real Git tool").

**Answer:**

### 0.3.4 Missing PeteKM folder at launch

Folder on a disconnected drive / renamed / iCloud-evicted. What does the app show, and what's the recovery flow?

**Answer:**

### 0.3.5 Carry-forward with no prior sticky

First day ever, or behavior set to carry-forward with an empty `daily/`. Fallback = start from scratch? Implied by §7.4, never stated.

**Answer:**

### 0.3.6 INDEX.md initial content

Brand-new folder: empty file, or placeholder header? Adopting an existing folder: suggest the user run `/petekm-rebuild-index` in their terminal?

**Answer:**

## 0.4 Stale / contradictory bits to clean up

### 0.4.1 DESIGN.md needs a full RoboPete sweep

**Resolved 2026-08-20 — sweep done.** RoboPete persona, "Ask RoboPete", AI commands, run/progress UI, AI feedback strings, RoboPete menu, and RoboPete settings all removed from `DESIGN.md`. The pixel-art portrait survives as the **PeteKM pixel mark** — pure brand mark (app icon, About, onboarding, empty states, menu-bar glyph), never presented as a character or AI persona. Asset files keep their historical `robopete-*` filenames.

### 0.4.2 `.petekm-cache/` never defined

Appears in the default `.gitignore` (§6.2) but is specified nowhere. Either spec it (rebuildable cache lives at the folder root under that name) or drop the line.

**Answer:**

### 0.4.3 RoboPete progress bar can't have a real percentage

**Resolved 2026-08-20 — moot.** No in-app agent runs (0.1.2), so no run UI, progress bar, or agent feedback exists. Covered by the 0.4.1 DESIGN.md sweep.

## 0.5 Confirm these are intentional (yes/no is enough)

### 0.5.1 No deletion/archival of old Daily Stickies — `daily/` stays flat forever (§5.1).

**Answer:**

### 0.5.2 Editor undo history is lost across app restarts.

**Answer:**

### 0.5.3 No export feature ever — the filesystem *is* the export (§27 rule 10).

**Answer:**

---

## 1. Product Summary

This product is a small, fast, native macOS note-capture application built around one core behavior:

> Press a global keyboard shortcut at any point during the day and immediately return to the same Markdown document for **today**.

The application is not intended to become a full notes platform, project-management system, task manager, Notion replacement, or Obsidian clone.

Its job is to make **capture nearly frictionless** while preserving all knowledge as ordinary files on the user’s computer.

The system has two conceptual layers:

1. **Daily Stickies** — chronological, messy, low-friction notes captured throughout the day.
2. **Library** — organized Markdown files containing long-lived knowledge, lists, reference material, project notes, and other information worth maintaining over time.

The Daily Stickies are the permanent historical record and must remain exactly as the user typed them.

The Library may be created, updated, organized, summarized, and maintained by the user's own AI agent (Claude Code initially) working in the PeteKM folder.

The user should not be required to name files, choose folders, create tags, maintain backlinks, or decide where information belongs while capturing it. Those are intentionally deferred decisions.

The desired mental model is:

> **Capture now. Organize later — mostly with AI.**

---

# 2. Product Principles

These principles should govern future feature decisions.

## 2.1 Frictionless capture wins

The product exists primarily because naming files, choosing folders, creating new documents, and deciding how to organize information create unnecessary friction.

Opening the app should not feel like “creating a note.”

It should feel like reopening a piece of paper that has been sitting on the user’s desk all day.

The expected behavior is:

1. Press shortcut.
2. Today’s note appears.
3. Cursor is ready.
4. Type.
5. Hide the app.
6. Repeat dozens of times throughout the day.

There should be no mandatory title field, save command, folder picker, classification step, tag field, or organizational decision during capture.

## 2.2 Markdown files are the source of truth

The user’s knowledge must exist as normal `.md` files in a user-selected folder on disk.

The app must never make a proprietary database the canonical store for note content.

If the app disappeared permanently, the user should still possess a complete, understandable library of ordinary Markdown files.

Any database, index, cache, search index, cursor-state file, or application metadata must be **derived or disposable**. Deleting it must not destroy the user’s knowledge.

## 2.3 The filesystem is a feature

The product intentionally embraces the fact that the notes are files.

The user must be able to:

- open the PeteKM folder in Finder;
- open the entire PeteKM folder in VS Code;
- edit any Markdown file outside the app;
- use terminal tools such as `rg`, `grep`, Git, Claude Code, and Codex;
- copy or move the entire PeteKM folder;
- back it up using ordinary filesystem tools;
- initialize it as a Git repository;
- inspect AI changes using Git diffs;
- stop using this app without needing an export.

## 2.4 AI should organize; the user should capture

The app should not force artificial PKM habits simply to make the data easier for AI to understand.

Specifically, the system does **not** require:

- wikilinks;
- `[[double bracket]]` syntax;
- tags;
- frontmatter on every note;
- atomic notes;
- manual backlink maintenance;
- a knowledge graph;
- manually curated metadata.

The user may type ordinary Markdown and ordinary prose.

AI agents should search, infer, organize, and selectively maintain durable knowledge from that material.

## 2.5 Daily Stickies are immutable to AI

This is a foundational safety rule.

**AI agents may read Daily Stickies but must never modify, rewrite, “clean up,” summarize in place, rename, reorganize, move, or delete them.**

Daily Stickies represent the original source material exactly as captured.

If an AI-generated Library file is wrong, the user must always be able to return to the original Daily Sticky.

## 2.6 Library files are allowed to evolve

The Library is explicitly different.

Library files may be:

- created;
- edited;
- expanded;
- consolidated;
- reorganized;
- renamed;
- moved;
- summarized;
- deduplicated;

by AI agents or by the user, subject to the safety rules defined later in this spec.

The Library is intended to become increasingly useful over time.

## 2.7 Keep the app small

The custom macOS application is primarily a **capture interface**, not a complete knowledge-management IDE.

Power-user operations that are already excellent in VS Code or the terminal should generally be delegated to those tools rather than rebuilt unnecessarily.

---

# 3. Terminology

## 3.1 PeteKM folder

The top-level, user-owned folder containing the entire knowledge system.

The user can name this folder anything they want.

Examples:

- `Brain`
- `Pete Brain`
- `Second Brain`
- `Notes`
- `Knowledge`

The app should never depend on a specific folder name.

Throughout this specification it is referred to as the **PeteKM folder**.

## 3.2 Daily Sticky / Soft note

A chronological Markdown file created automatically for one calendar day.

Example:

`daily/2026-08-19.md`

“Daily Sticky” is the preferred UI terminology.

“Soft note” describes the concept: raw, chronological, low-friction source material that has not necessarily been distilled into durable knowledge.

A Daily Sticky is never AI-modified.

## 3.3 Library

The portion of the PeteKM folder containing long-lived knowledge.

Preferred UI terminology: **Library**.

Possible contents include:

- running lists;
- project reference notes;
- people or company notes;
- technical concepts;
- hobbies;
- product knowledge;
- procedures;
- research;
- collections;
- summaries;
- manually maintained prose.

Examples:

- `library/Personal/Movies Watched.md`
- `library/Work/MFT.md`
- `library/Work/JSCAPE.md`
- `library/Personal/Home Theater.md`

These files may be edited both by the user and by the agent.

## 3.4 Library file

An individual Markdown file inside the Library.

The informal term “hard note” may be used during development, but the user-facing product should prefer **Library file** / **Library**.

## 3.5 The librarian workflow

There is no AI persona, mascot, or embedded assistant. "The librarian workflow" names the set of rules, instructions, and agent skills — plain files shipped in the PeteKM folder — that any filesystem-capable AI agent follows to maintain and interrogate the folder.

Initially this is expected to run through Claude Code, launched by the user in a terminal inside the PeteKM folder.

The architecture should remain readable and useful to other filesystem-capable AI agents.

## 3.6 Library Index

A machine- and human-readable Markdown overview of the Library, stored at the PeteKM folder root.

Preferred filename:

`INDEX.md`

Its purpose is to help humans and AI agents quickly understand the structure and important contents of the Library without reading every file.

It is not the sole search mechanism and does not need to catalog every sentence or every Daily Sticky.

## 3.7 Agent state

Disposable operational state (`.petekm-state.json`) used to remember information such as the last successfully processed Daily Sticky.

It is not knowledge and does not replace Markdown files.

---

# 4. Top-Level User Experience

The core experience should be intentionally repetitive and predictable.

## 4.1 Typical day

During the day:

1. User presses the global capture shortcut.
2. App appears immediately.
3. Today’s Daily Sticky is already open.
4. The app restores an appropriate cursor position, preferably where the user last left off.
5. User adds a heading, bullets, prose, or any other Markdown.
6. Content autosaves.
7. User presses the shortcut again or otherwise dismisses/hides the app.
8. Later, the user repeats the same workflow and returns to the **same Daily Sticky**, not a new capture box.

The app may be opened 30+ times per day.

That behavior should feel lightweight.

## 4.2 Example Daily Sticky

```md
# August 19, 2026

## Redwood onboarding

Learned more about how MFT authentication works today.

Nick explained that certificate-based authentication is common for...

Need to better understand the difference between user authentication and
protocol-level authentication.

## App idea

Maybe the Daily Sticky app should have a command palette.

- Search notes
- Open the Library in VS Code
- Open a terminal for filing

## Movies

Watched The Conversation. 4.5/5.

## House

Need to figure out garage storage.
```

No additional metadata is required.

## 4.3 When durable information is needed

The user has two choices:

### Direct editing

The user opens the Library or a specific Library file in VS Code and edits it normally.

### AI filing

The user opens a terminal in the PeteKM folder and has their agent process recent Daily Stickies or maintain a Library file (e.g. `/petekm-process-today`).

Example outcome:

A sentence in the Daily Sticky:

> Watched The Conversation. 4.5/5.

may cause the agent to update:

`library/Personal/Movies Watched.md`

The original Daily Sticky remains unchanged.

---

# 5. PeteKM Folder Structure

The exact internal structure should remain simple and legible.

A default newly initialized PeteKM folder should resemble:

```text
<My PeteKM Folder>/
├── daily/
├── library/
├── .claude/
│   └── skills/
├── INDEX.md
├── CLAUDE.md
├── AGENTS.md
├── .petekm-state.json
└── .gitignore
```

If Git is enabled, the folder may also contain:

```text
.git/
```

Once the agent has encountered ambiguous items, the root may also contain `INBOX.md` (§13.12), created lazily by the agent rather than at setup.

The app may create rebuildable application-support/cache data elsewhere or in an ignored hidden folder, but knowledge content must remain ordinary Markdown files.

## 5.1 `daily/`

Contains Daily Stickies only.

Filename format:

`YYYY-MM-DD.md`

Examples:

- `2026-08-19.md`
- `2026-08-20.md`
- `2026-12-03.md`

The filename is intentionally machine-generated so the user never names these files.

Daily Stickies may remain flat in this directory indefinitely.

The system should not automatically reorganize them into year/month folders unless a future explicit feature changes this behavior.

## 5.2 `library/`

Contains long-lived Markdown knowledge.

The Library may contain folders and nested folders.

The user does not need to manually create these folders during normal capture.

The agent may propose or create useful Library organization over time.

The user may freely edit the structure in Finder, VS Code, terminal, or other tools.

## 5.3 Librarian policy lives in `AGENTS.md`

There is no separate policy file. `AGENTS.md` (§5.6) carries the full shared librarian policy:

- the librarian role;
- the distinction between daily and Library files;
- absolute prohibition on AI modification of Daily Stickies;
- rules for creating/updating Library files;
- rules for preserving uncertainty;
- preference for simple organization;
- provenance expectations;
- index maintenance behavior;
- destructive-action safeguards.

PeteKM Claude skills should refer to `AGENTS.md` for this policy.

## 5.4 `INDEX.md`

A high-level map of the Library.

It is intended to help AI agents and humans answer questions such as:

- What major topics exist?
- Where is the running movies list?
- Which Library file covers MFT?
- What work projects are currently represented?

It should favor concise descriptions and paths over large duplicated summaries.

Example:

```md
# Library Index

Last updated: 2026-08-19

## Work

- `library/Work/MFT.md` — Managed file transfer concepts, terminology, protocols, and authentication.
- `library/Work/JSCAPE.md` — Product notes and learned capabilities.
- `library/Work/Sales Process.md` — Discovery, demos, and internal sales-process notes.

## Personal

- `library/Personal/Movies Watched.md` — Running movie log organized by year.
- `library/Personal/Home Theater.md` — Equipment, layout, and setup decisions.

## Projects

- `library/Projects/SNED.md` — Product concept and evolving decisions.
```

`INDEX.md` should not list every Daily Sticky.

## 5.5 `CLAUDE.md`

Contains concise repository-wide instructions useful whenever Claude Code is launched from the PeteKM folder.

It should **not** contain every detailed librarian procedure.

Instead, it should:

- explain what the repository is;
- identify `daily/` as read-only source material for AI;
- identify `library/` as AI-maintainable knowledge;
- tell Claude to read the librarian policy in `AGENTS.md` before modifying durable knowledge;
- point to relevant Claude Code project skills;
- describe `INDEX.md`;
- state that ordinary filesystem search should be used before loading excessive files;
- reiterate that no Daily Sticky may be modified.

The goal is for Claude Code to understand the repository immediately without making the root instruction file enormous.

## 5.6 `AGENTS.md`

The primary agent-facing document. It serves two roles:

1. High-level orientation for any coding/AI agent that recognizes `AGENTS.md`.
2. The full shared librarian policy (§5.3) — the detailed rules any agent must follow when maintaining the Library.

It must preserve the same safety contract as `CLAUDE.md`. The two files do not need to be identical, but they must not contradict each other; `CLAUDE.md` stays short and points here for policy.

## 5.7 `.petekm-state.json`

Stores small amounts of operational state.

Example:

```json
{
  "lastSuccessfulProcessing": "2026-08-19T20:42:13-04:00",
  "lastProcessedDailyNote": "2026-08-19.md"
}
```

This file:

- may be changed by the agent or the app;
- may be deleted without losing knowledge;
- should be recreatable;
- should never contain the canonical version of notes.

## 5.8 Rebuildable indexes/caches

The app is allowed to maintain search indexes or caches for speed.

Examples could include:

- discovered Markdown filenames;
- headings;
- full-text search tokens;
- recent searches;
- file modification timestamps.

However:

> If all caches are deleted, the app must be able to rebuild them entirely from files on disk.

No user-authored note content may exist only in a cache.

---

# 6. First-Run Onboarding and PeteKM Folder Setup

The app should provide a simple onboarding flow on first launch.

The goal is to establish the PeteKM folder and create the expected internal structure without requiring the user to manually construct hidden folders or configuration files.

## 6.1 Choose or create PeteKM folder

The user should be offered two primary choices:

- **Create a new PeteKM folder**
- **Use an existing PeteKM folder**

When creating a new PeteKM folder:

1. User chooses a parent location using the normal macOS folder picker.
2. User chooses any name for the PeteKM folder.
3. App creates the folder.
4. App initializes the standard internal structure.

When choosing an existing PeteKM folder:

1. User selects the PeteKM folder root.
2. App inspects the existing contents.
3. Missing expected app/support files may be offered/generated.
4. Existing Markdown files must never be deleted or overwritten without explicit user intent.

## 6.2 Setup files created by the app

The app should be capable of creating the foundational structure itself.

At minimum:

- `daily/`
- `library/`
- `.claude/skills/`
- `INDEX.md`
- `CLAUDE.md`
- `AGENTS.md`
- `.petekm-state.json`
- `.gitignore`

The default `.gitignore` contains:

```gitignore
.petekm-state.json
.DS_Store
.petekm-cache/
```

Everything else — including `.claude/skills/`, `CLAUDE.md`, `AGENTS.md`, and `INDEX.md` — is intended to be committed, so a clone of the repo is a fully working, agent-ready PeteKM folder.

The application should therefore provide a usable agent-ready PeteKM folder even before the user opens Claude Code.

## 6.3 Git setup

Git should be supported but not be required for note capture.

During onboarding or later in Settings, the app may offer:

- Initialize this PeteKM folder as a Git repository.
- Skip Git setup for now.

Remote hosting and authentication do not need to be mandatory onboarding steps.

The PeteKM folder must remain completely usable without Git.

## 6.4 AI-agent setup guidance

After the PeteKM folder exists, the app may show a short “Use with Claude Code” onboarding panel explaining that the user can launch Claude Code from the PeteKM folder root.

The PeteKM folder itself should contain enough instructions and project-local skills that the AI agent can discover the intended workflows from the repository.

The user should not need to repeatedly paste a giant setup prompt.

A separate copyable “bootstrap/setup prompt” may exist as a convenience or recovery mechanism, but the filesystem itself should be self-describing after initialization.

---

# 7. Daily Sticky Creation

## 7.1 Automatic creation

When the app needs today’s Daily Sticky, it determines the user’s local calendar date and looks for:

`daily/YYYY-MM-DD.md`

If it exists, the app opens it.

If it does not exist, the app begins the **New Day** creation flow.

The user never manually chooses the filename.

## 7.2 First open of a new day

On the first open of each new calendar day, the user may want either:

- a blank note;
- yesterday’s heading structure;
- a predefined default heading structure.

The app should support all three without creating daily friction for users who prefer one consistent behavior.

## 7.3 Daily Start Behavior setting

Settings should include:

**Daily Start Behavior**

Possible values:

1. **Ask me each day**
2. **Start from scratch**
3. **Carry forward previous headers**
4. **Use my default headers**

### Ask me each day

When today’s file does not exist, show a small, keyboard-friendly prompt.

Core choices:

- **Carry forward headers**
- **Start from scratch**

If default headers are configured, also offer:

- **Use default headers**

The popup should be intentionally tiny and dismissible entirely from the keyboard.

The user should be able to make a choice with arrow keys / shortcuts and Enter.

## 7.4 Carry forward headers

“Carry forward headers” means:

- inspect the most recent prior Daily Sticky;
- extract Markdown headings only;
- preserve their order;
- preserve heading levels/hierarchy;
- create today’s note with those headings;
- **do not copy any body text, bullets, completed items, or other content.**

Example previous day:

```md
# August 18, 2026

## Work

Lots of text...

### Questions

More text...

## App ideas

Other text...
```

Today may begin as:

```md
# August 19, 2026

## Work

### Questions

## App ideas
```

The H1 date heading should reflect today rather than being copied literally.

## 7.5 Default headers

Settings should allow the user to define a reusable daily structure.

Example:

```md
## Work

## Personal

## Ideas
```

These are plain Markdown headers, not a proprietary template format.

The app should preserve exactly the configured heading hierarchy.

Default headers are optional.

## 7.6 Start from scratch

A fresh Daily Sticky should still have a predictable top title.

Recommended default:

```md
# August 19, 2026
```

Below that, the file is blank.

A setting may allow the automatic H1 date heading to be disabled if desired, but it should be enabled by default.

## 7.7 Midnight/date changes

If the app remains running across midnight, it should not silently continue presenting yesterday as “today” forever.

On the next show/focus after the local date changes, the app should recognize the new day and perform the appropriate new-day behavior.

Previously saved Daily Stickies remain accessible.

---

# 8. Main App Window

The main application experience should be visually simple.

## 8.1 Default view

The main view contains the editor for the currently selected Daily Sticky.

The default file is always today’s Daily Sticky.

The UI should not require a permanent file tree or complicated sidebar.

Useful lightweight chrome may include:

- current date;
- filename/path on demand;
- a button or shortcut for the command palette;
- optional table of contents;
- unobtrusive save/sync state if helpful.

The editor must remain the visual focus.

## 8.2 Global show/hide shortcut

A configurable global macOS shortcut is one of the product’s defining features.

Behavior:

- If app is hidden/inactive: shortcut shows/focuses the capture window.
- Today’s Daily Sticky is opened/focused.
- Cursor returns to an appropriate recent position.
- If app is already the active capture window: pressing the shortcut again may hide/dismiss it.

The app ships with **no global shortcut pre-assigned**. Onboarding prompts the user to set one (suggesting ⌃⌥Space, which rarely conflicts with system or app shortcuts). The shortcut is fully customizable per §18.2; the app must warn if a chosen shortcut is known to conflict with a common system binding (e.g. ⌘Space is Spotlight).

## 8.3 Cursor behavior

When reopening the app repeatedly during one day, the app should restore the user to where they were working rather than always jumping to the top.

At minimum, remember the last cursor/selection position for the current Daily Sticky.

Reasonable fallback behavior is to place the cursor at the end of the document.

Cursor position is application state, not canonical note data.

## 8.4 Autosave

Typing should save automatically to the underlying Markdown file.

The user should not need to press Save during normal capture.

The product should prioritize preventing lost text.

## 8.5 External edits

Because Markdown files may also be edited by VS Code, Claude Code, Finder-driven tools, or other editors, the application must expect files to change outside the app.

The desired behavior is:

- detect relevant external file changes;
- avoid silently overwriting newer external contents;
- refresh or reconcile safely;
- clearly warn on an actual conflict.

The app must not assume it is the only process touching the PeteKM folder.

Daily Stickies should normally be modified only by the user, but the user may edit them in another text editor.

## 8.6 Window character

The capture window behaves like a persistent sticky, not a document window (see `DESIGN.md` §7 for visual direction):

- remembers its size and screen position between summons;
- optional "float above other apps" (always-on-top) toggle that persists;
- later: user-selectable background color and adjustable opacity, both persisted.

Window geometry, opacity, and color are application state, not note data.

---

# 9. Markdown Editor Experience

The editor should begin simple, but it should feel significantly nicer than a raw unstyled text area.

The user already likes aspects of the Scratchdown editing experience and may later port proven editor behaviors into this app.

The new app should not initially depend on reusing Scratchdown’s persistence model or legacy architecture.

## 9.1 Markdown remains visible

The editor should **not** fully hide Markdown syntax.

Examples:

```md
## Heading
**bold**
*italic*
- bullet
```

The user should still see the `##`, `**`, `*`, `-`, etc.

This keeps editing predictable and reduces the complexity of a full WYSIWYG system.

## 9.2 Live visual styling

Even though syntax remains visible, the editor should visually style common Markdown while typing.

Required baseline behaviors:

### Headings

Markdown headings should display with visually different font sizes/weights according to level.

For example:

- `#` largest;
- `##` smaller;
- `###` smaller again.

The Markdown `#` characters remain visible.

### Bold

Text surrounded by Markdown bold markers should visually appear bold while the markers remain visible.

### Italics

Text surrounded by Markdown italic markers should visually appear italic while the markers remain visible.

### Bullet lists

Bullet lists should visually respect indentation and nested levels.

The raw bullet marker remains visible.

### Nested lists

Indented bullet levels should be easy to read and edit.

The editor should behave naturally when pressing Tab / Shift-Tab or otherwise changing list indentation, subject to standard text-editing expectations.

## 9.3 Editor niceties

The editor should support or eventually inherit small IDE-like conveniences from Scratchdown where they materially improve capture speed.

Examples:

- automatic closing quotation marks;
- automatic closing parentheses;
- automatic closing brackets;
- automatic closing braces;
- sensible handling of a closing character when one already exists;
- continued list markers when pressing Return;
- sensible indentation on newline.

These are editor conveniences, not data-model features.

They can be ported from Scratchdown after the core file-based workflow works.

## 9.4 Heading-based table of contents

A lightweight table of contents similar to Scratchdown is desirable.

It should:

- derive entirely from Markdown headings in the currently open document;
- update as headings change;
- allow quick keyboard or mouse navigation;
- not store separate canonical outline data.

The TOC may be hidden/collapsed by default depending on the final UI.

## 9.5 Not required for the initial editor

The product does not require a sophisticated rich-text implementation.

Not initially required:

- hidden Markdown syntax;
- block drag-and-drop;
- Notion-style blocks;
- tables with spreadsheet behavior;
- embedded databases;
- canvas/whiteboard;
- graph visualization;
- complex embeds;
- collaborative cursors;
- comments;
- real-time multiplayer.

---

# 10. Command Palette

The app should have a keyboard-first command palette, likely invoked by a shortcut such as `⌘K`.

The command palette is the primary gateway to functionality beyond typing into today’s note.

It allows the visible app to stay simple.

## 10.1 Command palette goals

The palette should:

- open quickly;
- be fully navigable without a mouse or trackpad;
- fuzzy-match commands;
- fuzzy-match files;
- provide access to search;
- provide access to external-tool actions;
- keep rarely used features out of the main UI.

## 10.2 Core commands

The command palette should eventually include at least:

- **Open Daily Sticky**
- **Open Date…**
- **Search All PeteKM…**
- **Open Library File…**
- **Open Library in VS Code**
- **Open PeteKM Folder in VS Code**
- **Open Current File in VS Code**
- **Reveal PeteKM Folder in Finder**
- **Open Terminal in PeteKM Folder** (launches Terminal.app in the folder root; no AI involved — §15)
- **Review Inbox** (opens `INBOX.md`; shows "Nothing in Inbox." if missing/empty — §13.12)
- **Open Library Index**
- **Git Sync** (commit & push; when Git integration is configured)
- **Settings**

Naming may be polished later, but the capabilities should exist.

## 10.3 File search within the palette

When the user wants to open a Library file, typing part of a filename should fuzzy-match Library files.

Example:

```text
movie
```

may match:

- `Movies Watched.md`
- `Movie Recommendations.md`

Results should be selectable with arrow keys and Enter.

The user should not need to click through folder trees.

---

# 11. Local Search

The app must support useful **non-AI** search across the PeteKM folder.

The user should not have to launch Claude Code simply to find a phrase they remember typing.

## 11.1 Search scope

Search should be able to cover:

- Daily Stickies;
- Library files;
- filenames;
- folder names;
- Markdown headings;
- full text inside Markdown files.

Search should not be limited to filenames.

## 11.2 Search behavior

The app should provide fast local full-text search.

A search for:

`certificate authentication`

should be able to return occurrences from Daily Stickies and Library files even if no file has those words in its filename.

## 11.3 Search result display

A useful search result should show enough context to identify the match.

For example:

```text
2026-08-19.md
Redwood onboarding
"...certificate-based authentication is common for..."

library/Work/MFT.md
Authentication
"...certificate authentication can..."
```

Desirable result metadata:

- filename;
- path or category;
- relevant heading;
- text snippet surrounding the match;
- date when obvious from a daily filename.

## 11.4 Search navigation

Search must be keyboard-friendly.

The user should be able to:

1. invoke search;
2. type query;
3. move through results with arrow keys;
4. press Enter;
5. jump directly to the relevant file and ideally the relevant match/heading.

## 11.5 Search is not AI

The local app search should remain deterministic and fast.

It does not need embeddings, an AI API, or semantic-vector infrastructure for the baseline product.

AI-powered retrieval remains available through the user's own agent in the terminal.

## 11.6 Search indexes are disposable

The application may create an index to make full-text search fast.

That index must be completely rebuildable from Markdown files and must not be the canonical storage location for content.

---

# 12. Library and VS Code

The app deliberately does not need to become the best interface for deep Library-file editing.

VS Code is an accepted and encouraged power-user interface.

## 12.1 Open PeteKM Folder in VS Code

A command should open the entire PeteKM folder as a VS Code workspace/folder.

This allows the user to:

- browse folders;
- inspect daily and Library files;
- search;
- manually rename/move Library files;
- edit Markdown;
- run source control tools;
- open a terminal;
- launch Claude Code from the correct location.

## 12.2 Open Library in VS Code

A separate command may open or focus the PeteKM folder in VS Code with the `library/` area selected or otherwise convenient.

The exact VS Code invocation is an implementation concern; the product behavior is that the user should arrive in the Library with minimal friction.

## 12.3 Open a specific Library file in VS Code

The command palette should allow:

1. **Open Library File…**
2. fuzzy-search files;
3. choose a file;
4. open the PeteKM folder in VS Code with that file active.

This is preferred over building a complex Library editor into the app.

## 12.4 Editing outside the app is first-class

External edits are not hacks or unsupported behavior.

The filesystem is the shared interface.

The app should treat editing via VS Code as a normal use case.

---

# 13. The Librarian Workflow

## 13.1 No persona

There is no AI persona, name, avatar, or mascot — in the app or in the repository files. "The librarian workflow" is simply the contract any AI agent follows when filing notes: read Daily Stickies, maintain the Library, never touch the source.

The app itself contains **zero AI functionality** and never refers to an AI assistant in its UI. The workflow exists entirely as plain files (`AGENTS.md`, `CLAUDE.md`, `.claude/skills/petekm-*`) that the user's own agent discovers when launched in the PeteKM folder.

In this spec, "the agent" means whatever filesystem-capable AI agent the user runs — Claude Code initially.

## 13.2 Core responsibility

The agent turns raw daily capture into useful durable knowledge **without altering the source material**.

Conceptually:

```text
DAILY STICKIES (source/ledger)
          |
          | read only
          v
       AGENT
          |
          | create/update
          v
LIBRARY (maintained knowledge)
```

## 13.3 Daily Stickies are an immutable ledger

The agent must treat `daily/` as read-only.

The agent must never:

- rewrite a Daily Sticky;
- fix grammar in a Daily Sticky;
- add a summary to a Daily Sticky;
- add links or tags to a Daily Sticky;
- rename Daily Stickies;
- move Daily Stickies;
- delete Daily Stickies;
- insert “processed” markers into Daily Stickies.

If the agent needs processing state, it belongs in `.petekm-state.json` or other disposable state.

## 13.4 What the agent should extract

When processing a Daily Sticky, the agent should look for information that has future value.

Examples:

- a durable fact or concept the user learned;
- a useful explanation;
- a running list entry;
- a project decision;
- an idea that belongs in an existing project file;
- a person/company/product reference worth maintaining;
- a process or procedure;
- a preference or decision;
- an unresolved question that is worth preserving;
- a recurring topic that deserves a Library file.

The agent should not feel compelled to preserve every sentence.

## 13.5 Examples

Daily source:

```md
## Movies

Watched The Conversation. 4.5/5. Loved the atmosphere.
```

Possible Library update:

`library/Personal/Movies Watched.md`

```md
## 2026

- 2026-08-19 — The Conversation — 4.5/5 — Loved the atmosphere.
```

Daily source:

```md
## Redwood onboarding

Nick explained that JSCAPE can use LDAP and SAML for user authentication.

Still need to understand how that differs from authentication at the transfer-protocol level.
```

Possible Library update:

`library/Work/JSCAPE.md`

```md
## Authentication

- JSCAPE can use LDAP and SAML for user authentication.
- Distinction between application/user authentication and transfer-protocol authentication still needs clarification.

Source: daily/2026-08-19.md
```

## 13.6 Preserve uncertainty

The agent must distinguish among:

- facts explicitly captured by the user;
- the user’s own speculation;
- unresolved questions;
- the agent’s inference;
- new external knowledge an agent may know.

The agent should never silently convert uncertainty into certainty.

If the Daily Sticky says:

> “I think certificate auth might work this way?”

the Library file should not turn that into:

> “Certificate auth works this way.”

## 13.7 Provenance

Library files should preserve useful provenance back to source Daily Stickies when the agent adds or materially updates information.

The format should remain ordinary Markdown and need not use special wikilink syntax.

Examples:

```md
Source: `daily/2026-08-19.md`
```

or:

```md
Sources:
- `daily/2026-08-18.md`
- `daily/2026-08-19.md`
```

The goal is easy traceability, not citation bureaucracy.

## 13.8 Prefer updating to proliferation

The agent should search the Library before creating a new Library file.

If `library/Work/MFT.md` already exists, new MFT knowledge should generally be incorporated there rather than creating:

- `MFT 2.md`
- `More MFT.md`
- `MFT Notes August.md`

New files should be created when they provide a genuinely useful durable boundary.

## 13.9 Organization is allowed to evolve

The agent may create useful folders and move Library files when appropriate.

However, routine daily processing should be conservative.

Large-scale restructures should preferably happen through an explicit organize/refactor action rather than silently during every daily run.

## 13.10 Running lists are first-class Library files

Not every Library file is an encyclopedia article.

Important examples include:

- Movies Watched
- Books
- Gift Ideas
- Restaurants
- Home Theater
- Project Decisions
- Questions to Research

The agent should understand that some Library files are append-oriented living documents.

## 13.11 Human editing wins

The user may manually edit any Library file.

The agent must treat the current on-disk version as authoritative and preserve deliberate human edits unless explicitly asked to rewrite them.

The agent should not blindly regenerate entire files from scratch when a targeted edit would preserve human structure more safely.

## 13.12 Inbox

When the agent processes Daily Stickies and cannot confidently decide where an item belongs in the Library, it must not guess. Instead it appends the item to a single plain Markdown file, **`INBOX.md`**, at the PeteKM folder root.

Rules:

- `INBOX.md` is **created lazily** by the agent the first time it is needed; the app does not create it during onboarding, and its absence is normal (§19.2 no-overwrite rules apply if a file with that name already exists).
- Each appended item is a plain Markdown bullet: a copy of (or short restatement of) the ambiguous content, with provenance (§13.7) — the source Daily Sticky date — and a one-line reason it was ambiguous. Example:

  ```markdown
  - Try "Foundation" audiobook — from 2026-08-19. Unsure: Books list or Audiobooks list?
  ```

- Inbox items are **copies, not moves.** The original text stays in the Daily Sticky untouched (§2.5).
- `INBOX.md` sits on the **mutable side** of the safety boundary, like the Library: the user may freely edit, annotate, reorder, or delete items, and the agent may also write to it.
- The intended loop: user edits/clarifies inbox items, then runs the filing skill again; the agent treats remaining inbox items as filing input alongside unprocessed Daily Stickies, files what it now can, and **removes items from `INBOX.md` once successfully filed** (with provenance in the target Library file). Items it still can't place stay put.
- Deleting a line from `INBOX.md` is a valid user action meaning "ignore this"; the agent must not resurrect deleted items.
- `INBOX.md` is committed to Git like other knowledge files (not ignored).

The user learns the Inbox was used from the agent's own report in the terminal (the filing skills must mention inbox counts in their final summary — §14.2). The app plays no part in that feedback. The command palette includes **Review Inbox** (§10.2), which simply opens `INBOX.md` in the editor; if the file is missing or empty, the app shows "Nothing in Inbox."

---

# 14. Claude Code Skills / AI Actions

Librarian workflows should be represented as repeatable AI-agent actions rather than giant prompts pasted repeatedly.

For Claude Code, these should be represented as **project-local Skills** stored inside the PeteKM folder:

```text
.claude/
└── skills/
    ├── petekm-process-today/
    │   └── SKILL.md
    ├── petekm-process-date/
    │   └── SKILL.md
    ├── petekm-rebuild-index/
    │   └── SKILL.md
    ├── petekm-organize/
    │   └── SKILL.md
    └── petekm-status/
        └── SKILL.md
```

Claude Code currently discovers project skills under `.claude/skills/<skill-name>/SKILL.md`, and the directory name can provide a slash-invokable command such as `/petekm-process-today`.

Each `SKILL.md` must begin with YAML frontmatter containing at least `name` and `description`; the description is what Claude uses to decide when a skill is relevant, so it should state the trigger conditions plainly.

These files live with the PeteKM folder so the workflows are:

- versionable;
- editable;
- inspectable;
- portable with the repository;
- specific to this PeteKM folder;
- available when Claude Code is launched in the PeteKM folder.

## 14.1 Skill philosophy

`CLAUDE.md` should contain short, always-relevant facts and safety rules.

Longer procedures should live in skills and be loaded only when the procedure is invoked.

`AGENTS.md` contains the shared librarian behavior/policy referenced by PeteKM skills (§5.3, §5.6).

## 14.2 Initial PeteKM skills

### `/petekm-process-today`

Primary everyday action.

Behavior:

1. Determine today’s daily filename.
2. Read the Daily Sticky.
3. Read the librarian policy in `AGENTS.md`.
4. Inspect `INDEX.md`.
5. Search existing Library files for relevant destinations.
6. Update or create Library files conservatively.
7. Preserve source provenance.
8. Do not modify the Daily Sticky.
9. Update `INDEX.md` if the Library structure materially changed.
10. Update `.petekm-state.json` only after successful completion.
11. Provide a concise report of what changed, including how many items went to `INBOX.md` if any.

### `/petekm-process-date`

Accepts a date or daily filename and performs the same process for that source note.

Useful when:

- processing was missed;
- importing older notes;
- re-running a day after changing librarian rules.

### `/petekm-rebuild-index`

Inspects the Library and recreates or repairs `INDEX.md`.

It must not require reading every Daily Sticky.

The Library filesystem itself is the primary source for this operation.

### `/petekm-organize`

Performs a more deliberate review of Library structure.

Potential behavior:

- identify duplicates;
- identify near-duplicate files;
- propose or perform sensible merges;
- simplify folders;
- rename unclear Library files;
- repair index paths.

Because this can produce larger structural changes, it should be explicitly invoked rather than automatically bundled into normal daily processing.

### `/petekm-status`

Reports useful operational information such as:

- last successfully processed Daily Sticky;
- any unprocessed Daily Stickies;
- whether `INDEX.md` appears stale;
- notable repository state relevant to filing.

This is informational and should not rewrite knowledge.

## 14.3 Natural-language AI use remains supported

Skills are conveniences, not the only way to use the PeteKM folder.

The user should always be able to launch Claude Code in the PeteKM folder and ask:

> Search everything I’ve written about certificate authentication and explain what I appear to understand so far.

or:

> Find every time I mentioned this product and tell me what questions are still unresolved.

The agent can use filesystem search to locate relevant material before reading files.

## 14.4 Agent scale behavior

The system must not assume that an AI agent will load the entire PeteKM folder into its context.

For a large PeteKM folder, the expected retrieval strategy is:

1. read `CLAUDE.md` / agent instructions;
2. inspect `INDEX.md` when useful;
3. search filenames/headings/full text using filesystem tools;
4. open only relevant files/ranges;
5. expand the search if necessary.

A PeteKM folder containing thousands of files is therefore acceptable.

---

# 15. Filing Happens Outside the App

**The app never invokes, launches, monitors, or parses any AI agent. Zero AI functionality.** This is a standing product boundary, not a v1 limitation.

## 15.1 The filing workflow

1. User opens a terminal in the PeteKM folder — themselves, or via the palette command **Open Terminal in PeteKM Folder** (which only launches Terminal.app at the folder root; nothing more).
2. User launches their agent (e.g. `claude`) and invokes a skill such as `/petekm-process-today`, or just asks in natural language.
3. The agent changes Library files, `INDEX.md`, and `INBOX.md` on disk as appropriate. The Daily Sticky remains untouched.
4. The agent's own terminal output is the report. The app shows no progress UI, no success/failure feedback, no counts.
5. The app notices the changed files the same way it notices any external edit (§8.5).

Because the skills ship in the folder, the user never copy/pastes the same filing prompt — but the app plays no part in running them.

## 15.2 AI provider philosophy

The product has **no AI API, no AI billing, no agent configuration**. It leverages whatever user-installed/authenticated AI coding agent the user already has (Claude Code initially). Support for other agents is a matter of the repository files (`AGENTS.md`) being agent-neutral, not of app features.

## 15.3 Cadence is the user's business

Filing can happen once a day, once a week, or never. Nothing in the app tracks, prompts, or nags about unprocessed days; `/petekm-status` (run in the terminal) answers "what's unprocessed?" when the user cares.

---

# 16. Search with AI vs Search in the App

There are intentionally two different search experiences.

## 16.1 App search

Use when the user roughly remembers what they typed.

Characteristics:

- immediate;
- local;
- deterministic;
- full-text;
- no AI;
- no token cost;
- keyboard-first.

Example:

> “Where did I type ‘certificate auth’?”

## 16.2 AI search (in the terminal)

Use when the user wants synthesis or fuzzy conceptual retrieval.

Characteristics:

- agent-powered;
- may search multiple related terms;
- may inspect multiple files;
- can summarize;
- can compare;
- can infer;
- can identify contradictions and unresolved questions.

Example:

> “What have I learned about authentication during onboarding, and what concepts am I still mixing up?”

The app does not need to reproduce the second experience inside its own search UI.

**Decided:** the app contains **no embedded AI chat, no "Ask RoboPete…" command, and no app-owned AI integration or API** — not just in v1, but as a standing boundary. The only way AI interacts with the PeteKM system is through the user's own AI coding agents (Claude Code, Codex, etc.) operating on the local files — typically by opening a terminal, `cd`-ing into the PeteKM folder, and invoking the agent there. (`DESIGN.md` §17's "Ask RoboPete…" command is superseded by this decision.)

---

# 17. Git and Version History

Git is strongly aligned with the product philosophy.

It provides:

- backup;
- history;
- diffing;
- rollback;
- visibility into the agent’s changes;
- portability.

## 17.1 Git should remain optional

Users must be able to use the app without Git.

For the target workflow, however, Git integration is desirable.

## 17.2 Commit behavior

A command may support:

**Git Sync** (commit & push)

The exact commit strategy is configurable/future-facing.

A simple automated commit message is acceptable, for example:

```text
PeteKM backup 2026-08-19 20:45
```

The history is primarily for backup and recovery, not perfect semantic commit archaeology.

## 17.3 AI + Git

AI changes to the Library should be easy to inspect in Git.

This safety model is particularly valuable because:

- daily source notes remain unchanged;
- the agent’s Library edits are versioned;
- accidental changes can be reverted;
- the user can compare what the agent changed.

## 17.4 Never block capture on Git

Git authentication failures, unavailable remotes, merge conflicts, or push failures must not stop the user from opening or saving today’s Daily Sticky.

Capture is always the higher-priority function.

---

# 18. Settings

Settings should remain focused.

## 18.1 PeteKM folder location

Display and allow changing/selecting the active PeteKM folder.

Changing the PeteKM folder should be an intentional action with clear safeguards.

## 18.2 Global shortcut

Allow configuration of the global show/hide capture shortcut.

No shortcut is pre-assigned on first launch; onboarding prompts the user to choose one (suggested: ⌃⌥Space). See §8.2.

## 18.3 Daily Start Behavior

Options:

- Ask me each day
- Start from scratch
- Carry forward previous headers
- Use my default headers

## 18.4 Default daily headers

Provide a simple Markdown text area for default headings.

Example:

```md
## Work

## Personal

## Ideas
```

This should remain plain text/Markdown.

## 18.5 Automatic date heading

Toggle whether new daily files begin with an H1 human-readable date.

Default: enabled.

The H1 format is hard-coded English `Month D, YYYY` (e.g. `# August 19, 2026`) so carry-forward parsing (§7.4) stays deterministic. UI chrome (window title, date picker, etc.) may display a friendlier locale-aware format per `DESIGN.md` §28.

## 18.6 Editor preferences

Potential settings:

- font family;
- font size;
- line spacing;
- show/hide table of contents;
- auto-close brackets/quotes;
- list continuation behavior.

The initial settings set may be smaller.

## 18.7 External editor

Default external editor: VS Code.

The architecture should not make VS Code a hard-coded data dependency; a future version could allow another external editor.

Commands should fail gracefully if VS Code is unavailable.

## 18.8 No AI settings

The app has no AI agent configuration — it never runs one (§15). Which agent the user launches in their terminal is outside the app's knowledge.

## 18.9 Git

Potential settings:

- Git enabled/disabled
- auto-initialize repository
- push remote information/status
- whether automatic backup occurs

Advanced Git settings can remain outside the initial release.

---

# 19. File and Data Safety

## 19.1 Never trap the user’s data

All user-authored knowledge must remain accessible without this application.

## 19.2 Do not overwrite unknown existing files during setup

If onboarding finds an existing:

- `CLAUDE.md`
- `AGENTS.md`
- `INDEX.md`
- `.gitignore`

the app must not silently replace it.

It should merge carefully, create a backup, or ask the user.

The exact resolution UI is an implementation detail, but silent destructive overwrite is prohibited.

## 19.3 Daily Sticky write safety

Autosave should favor atomic/safe file writes appropriate for local text editing.

The product should protect against truncated or lost Daily Stickies.

## 19.4 External changes

If the currently open note changes externally while the user has unsaved local changes, the app should not silently choose one version and destroy the other.

A clear conflict path is required.

## 19.5 AI safety boundary

The most important AI boundary is filesystem scope.

The agent’s routine filing behavior should operate inside the selected PeteKM folder and should not need to modify arbitrary files elsewhere on the computer.

---

# 20. Privacy and Offline Philosophy

The PeteKM folder is local-first.

The app itself should not require cloud storage, an account, or an application-owned sync service to create and edit notes.

Without invoking an external AI agent, capture and local search should function entirely from local files.

If the user chooses to use Claude Code, GitHub, iCloud, Dropbox, or another external service, those are separate tools with their own data policies.

This separation is particularly important when a PeteKM folder may contain work-related information.

The software should not imply that third-party AI or cloud use is automatically appropriate for employer-confidential data.

## 20.1 Distribution and sandbox posture

**Decided:** the app is **not** submitted to the Mac App Store. It is distributed directly (e.g. a notarized `.dmg`) using Developer ID signing and Apple notarization.

Consequences:

- The App Sandbox is **disabled**, because the product requires shelling out to `git`, `code`, and `claude` (§12, §15, §17) and read/write access to a user-chosen folder.
- The app still keeps security-scoped-bookmark-style discipline for the user-chosen PeteKM folder: persist access via a bookmark, never assume ambient filesystem access beyond what the user granted.
- The Xcode project's `ENABLE_USER_SELECTED_FILES = readonly` setting must be corrected as part of implementing folder access.

---

# 21. Explicit Non-Goals

The following are intentionally outside the product’s core identity unless future experience proves they are necessary.

## 21.1 No task-management system

Paper/pencil or other tools may continue to handle day-to-day tasks.

The app does not need:

- kanban boards;
- due dates;
- reminders;
- recurring tasks;
- calendar planning.

## 21.2 No mandatory tags

The user currently does not use tags.

The product must not require a tagging system.

Tags may remain valid plain Markdown text if the user ever chooses to type them, but the system should not depend on them.

## 21.3 No wikilink system

The product should not require `[[double bracket]]` links or any comparable manual linking syntax.

Normal Markdown links remain valid Markdown, but manual relationship maintenance is not part of the required workflow.

## 21.4 No knowledge graph

No graph visualization is required.

## 21.5 No database-centric PKM

Do not introduce database objects, properties, schemas, supertags, relations, or Notion-style database features merely because other PKM tools use them.

## 21.6 No custom AI model/API requirement

The app does not need its own AI subscription or API billing model.

## 21.7 No full VS Code replacement

The custom app does not need to replicate:

- full repository navigation;
- Git tooling;
- multi-file editing;
- terminals;
- advanced regex search;
- plugins/extensions;
- code-editor complexity.

VS Code already provides those capabilities.

## 21.8 No forced manual organization during capture

Never interrupt capture to ask:

- What should this file be named?
- What folder should this go in?
- What tags should it have?
- What note should it link to?
- What category is this?

Daily capture should remain nearly thoughtless.

---

# 22. Important Behavioral Scenarios

## Scenario A: first capture of the day

It is 8:12 AM.

The user presses the global shortcut.

`daily/2026-08-19.md` does not exist.

Daily Start Behavior is “Ask me each day.”

A tiny popup appears:

- Carry forward headers
- Use default headers
- Start from scratch

The user chooses “Carry forward headers.”

The app creates the file using yesterday’s heading hierarchy and today’s H1 date.

The editor appears immediately.

The user types.

The file autosaves.

## Scenario B: twentieth capture of the same day

At 3:40 PM, the user presses the shortcut.

The app opens instantly.

`daily/2026-08-19.md` is still the active Daily Sticky.

The cursor returns to the previous position.

No new document is created.

The user types a new heading and several bullets.

## Scenario C: remembered phrase

The user remembers writing something about “certificate auth” three days ago.

They open the command palette and choose **Search All PeteKM**.

They type:

`certificate auth`

The app returns matches from:

- relevant daily files;
- relevant Library files;

with snippets and headings.

No AI is required.

## Scenario D: open a running list

The user wants to manually add something to their long-running Movies Watched list.

They open the command palette.

Choose **Open Library File…**

Type:

`movies`

Select:

`library/Personal/Movies Watched.md`

The app opens the PeteKM folder in VS Code with that note active.

The user edits it normally.

## Scenario E: filing today's notes

At the end of the day, the user opens a terminal in the PeteKM folder (perhaps via **Open Terminal in PeteKM Folder**), launches Claude Code, and runs:

`/petekm-process-today`

The agent reads:

`daily/2026-08-19.md`

It searches the Library.

It:

- adds the watched movie to the existing movie log;
- updates an existing MFT Library file with newly learned information;
- adds an unresolved authentication question without pretending it is settled;
- creates no unnecessary files;
- updates `INDEX.md` only if necessary;
- updates `.petekm-state.json`.

It does **not** alter `daily/2026-08-19.md`.

The agent prints a concise summary of Library changes in the terminal. The app is not involved.

## Scenario F: ask a conceptual question

The user opens Claude Code from the PeteKM folder and asks:

> What have I learned so far about transfer authentication, and what am I still confused about?

The agent:

- reads the repository instructions;
- uses `INDEX.md` and filesystem search;
- searches daily and Library files;
- reads relevant files;
- synthesizes an answer.

It does not need to load the entire PeteKM folder into context.

## Scenario G: the agent makes a bad change

The agent edits `library/Personal/Movies Watched.md` incorrectly.

Because:

- the original Daily Sticky is untouched;
- Library files are ordinary Markdown;
- Git records changes;

the user can inspect the diff and revert the incorrect Library edit.

---

# 23. Product Quality Bar

The product succeeds if the user can genuinely build the habit:

> shortcut → type → hide

without thinking about the software.

The application should feel closer to a persistent scratchpad than a traditional document-management tool during capture.

At the same time, the underlying PeteKM folder should feel closer to a developer-friendly repository than a proprietary notes database.

The combination should provide:

- Scratchdown-like capture speed;
- ordinary Markdown durability;
- VS Code power-user access;
- Git history;
- fast local search;
- Claude Code / AI-agent retrieval;
- agent-maintained durable knowledge.

---

# 24. Core Acceptance Criteria

These are product-level acceptance criteria, not an implementation sequence.

## Daily capture

- A user can press a configurable global shortcut from another macOS application and reach today’s Daily Sticky.
- Repeated opens during the same day return to the same Markdown file.
- The Daily Sticky is stored as `daily/YYYY-MM-DD.md`.
- Typing is autosaved to that file.
- Daily Sticky filenames never require manual naming.
- New-day behavior supports blank start, header carry-forward, and custom default headers.
- Header carry-forward copies heading structure only, never yesterday’s body content.

## Markdown ownership

- All note content is stored as ordinary Markdown files.
- The PeteKM folder remains readable/editable without the app.
- No proprietary database is required to recover note content.
- Search or UI caches can be rebuilt from the filesystem.

## Editor

- Markdown syntax remains visible.
- Headings receive live visual hierarchy.
- Bold and italics receive live visual styling.
- Bullet indentation is visually clear.
- The editor can eventually support Scratchdown-style auto-closing conveniences without changing the file format.

## Search

- The app can search filenames, paths, headings, and full Markdown content.
- Search does not require AI.
- Results include useful snippets/context.
- Search is keyboard navigable.
- A result can open the relevant file/location.

## Library

- Library files are normal Markdown files under `library/`.
- The user can open the PeteKM folder or a selected Library file in VS Code from the app.
- The app does not need to provide a full-featured Library-file IDE.

## Librarian workflow

- The librarian workflow is represented entirely by repository instructions and reusable agent skills; the app contains zero AI functionality and never invokes an agent.
- Filing can read Daily Stickies but cannot modify them.
- The agent may create/update Library files.
- The agent searches for an appropriate existing Library destination before creating unnecessary files.
- The agent preserves uncertainty.
- The agent adds useful source provenance.
- The agent can maintain `INDEX.md`.
- The agent has disposable state (`.petekm-state.json`) separate from knowledge.
- All filing runs in the user's own terminal via Claude Code (or another agent).

## AI agent compatibility

- The PeteKM folder root contains concise `CLAUDE.md` guidance.
- The PeteKM folder root contains `AGENTS.md` guidance for broader agent compatibility.
- Shared librarian policy lives in `AGENTS.md`.
- Claude Code project skills live under `.claude/skills/`.
- The system does not require the entire PeteKM folder to fit into an AI context window.
- Agent instructions encourage search-first, selective-read retrieval.

## Safety

- AI never modifies Daily Stickies.
- App setup never silently overwrites existing user files.
- External file edits are considered normal.
- Git failures never prevent local capture.
- The app’s own caches/state can be deleted without destroying knowledge.

---

# 25. Future Possibilities — Explicitly Not Commitments

These ideas are compatible with the architecture but should not silently expand the MVP.

Potential future additions:

- scheduled/automated filing (repo-side, e.g. cron + headless agent — never app-side);
- automatic Git commit/push after successful filing;
- configurable external editors besides VS Code;
- Codex-specific skills/instructions;
- user-created PeteKM skills;
- “process all unprocessed days” skill;
- a read-only filing activity/history panel (derived from Git, no agent integration);
- local backlinks inferred from ordinary Markdown text;
- better semantic search using a fully local index;
- menu-bar-only mode;
- quick capture from macOS Services/Share Sheet;
- iCloud/Dropbox folder compatibility;
- lightweight Library-file viewing inside the app;
- multiple PeteKM folders;
- templates beyond simple daily headers.

These should be evaluated only after the core workflow proves itself.

---

# 26. One-Sentence Product Definition

> **A native macOS daily Markdown capture app that keeps your raw notes untouched, stores everything in a local folder you own, and ships that folder agent-ready — so your own AI agent (Claude Code) can turn those Daily Stickies into an organized, durable second brain.**

---

# 27. The Product Contract

If only a few rules survive every future iteration, they should be these:

1. **One Markdown file per day.**
2. **The global shortcut always gets you back to today quickly.**
3. **Never make the user name or file something during normal capture.**
4. **Daily Stickies are the immutable source of truth and AI may never edit them.**
5. **Library files are ordinary Markdown files that may evolve over time.**
6. **Your own AI agent does the librarian work — the app never runs AI.**
7. **Local search handles finding text; AI handles synthesis and understanding.**
8. **VS Code and the terminal are first-class power-user interfaces.**
9. **Git provides history and an undo layer around AI-maintained knowledge.**
10. **If this app disappears tomorrow, the PeteKM folder still works.**
