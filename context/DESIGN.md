# PeteKM — DESIGN.md

## 1. Purpose

This document defines the visual, interaction, naming, and UI design direction for **PeteKM**.

It is intentionally **not** a product requirements document and **not** an implementation plan. It describes how PeteKM should feel, look, communicate, and behave from a design perspective.

The guiding principle:

> **PeteKM should feel like a tiny, native macOS utility that happens to be a second brain.**

It should not feel like a complex PKM suite, productivity dashboard, knowledge graph, database app, or "AI workspace."

The visual identity should be restrained almost to the point of disappearing.

The custom personality comes from only a few places:

- the name **PeteKM**
- the **Daily Sticky** metaphor
- custom sticky colors and opacity
- the intentionally personal terminology
- the **PeteKM pixel mark**, a 1-bit 1980s-Macintosh pixel portrait of Pete — pure brand mark, not a character or AI persona
- one restrained brand accent: **electric blue `#0A5CFF`**

Everything else should feel quiet, practical, native, and fast.

---

## 1.1 The Design System (source of truth for visuals)

A full design system now exists as a Claude Design project (**"PeteKM Design System"**, `claude.ai/design/p/f95f6b6d-9433-4e41-b93c-97064b84e609`). Part II of this document (§46 onward) is the authoritative written form of that system: exact palette, type scale, spacing, radii, elevation, motion, interaction states, iconography rules, content voice, component inventory, and brand assets.

Local copies of the brand assets live in **`context/design-system/assets/`**. (The files keep their historical `robopete-*` filenames; the mark itself is now called the **PeteKM pixel mark** — the RoboPete persona was removed from the product 2026-08-20, see `spec.md` §13.1.)

| File | What it is |
| --- | --- |
| `robopete.grid.json` | The editable 32×32 pixel grid. `#`/`B` = ink, `W`/`.` = transparent. This is the master source for the mark. |
| `robopete.svg` | Vector render of the grid (`shape-rendering: crispEdges`), one fill: `#0A5CFF`. |
| `robopete-32.png` / `-64.png` / `-128.png` / `-512.png` | Integer-scaled raster renders (1×, 2×, 4×, 16×). Always render pixelated; never resample fractionally. |
| `robopete-appicon-1024.png` | App icon master: white rounded square (Apple icon grid) with the blue mark centered. Source for `AppIcon.appiconset`. |

Two scope notes on the design-system project itself:

1. The system was derived from a written brief plus macOS convention — **it is a proposal, not documented ground truth**. Where it conflicts with `spec.md`, the spec wins.
2. Its UI kit (`ui_kits/petekm-mac/`) mocks a **three-pane library window** (sidebar / list / reading pane / inspector). That is a design exploration for a possible Library browsing surface — it is *not* the product's primary window. The primary window remains the **Daily Sticky** (§7). Borrow the kit's metrics, chrome, and component styling; do not import its information architecture wholesale.
3. The system's strict white/black/blue palette governs **app chrome** (toolbars, palette, settings, popovers). The **Daily Sticky canvas keeps its own user-selected background colors** (soft yellow default, §7) — that is a deliberate, spec-mandated exception layered on top of the system. Chrome drawn *over* a sticky (popovers, palette) still follows the system.

---

# 2. Core Product Vocabulary

Keep the product vocabulary extremely small.

## PeteKM

**PeteKM** is the app and the overall second-brain system.

The name is simply:

> **PeteKM**

Avoid qualifiers such as:

- PeteKM Notes
- PeteKM AI
- PeteKM Brain
- PeteKM Daily
- PeteKM PKM

---

## Daily Sticky

The **Daily Sticky** is the primary capture interface.

It is:

- one Markdown document per day
- opened repeatedly throughout the day
- visually presented like a lightweight sticky-note utility
- casual and low-friction
- the main window the user interacts with

Use **Daily Sticky** consistently in the UI.

Examples:

- Open Daily Sticky
- Previous Daily Sticky
- Daily Sticky Settings
- New Daily Sticky
- Carry Forward Headers
- Search Daily Stickies

Avoid calling it:

- journal
- diary
- daily journal
- daily page
- daily entry
- task list

The word "daily" describes rollover behavior only. It must never imply a streak, obligation, journaling ritual, or productivity pressure.

Never use language like:

- You haven't written today
- Complete today's note
- Keep your streak going
- Start your day
- Daily reflection

The Daily Sticky is simply there when needed.

---

## Library

The **Library** is the organized knowledge base.

It consists of normal Markdown files and folders.

Call it:

> **Library**

Not:

- Durable Library
- Knowledge Base
- Knowledge Graph
- Vault
- Database
- Repository
- Archive

Examples:

- Open Library
- Search Library
- Open Library in VS Code
- Library File
- Library Search Results

---

## No AI persona

There is **no AI name, persona, mascot, or assistant** anywhere in the app UI (`spec.md` §13.1). The app has zero AI functionality; filing happens in the user's own terminal via their own agent (Claude Code initially).

Mental model:

> **PeteKM is the second brain.**
> **Daily Sticky is where I dump things.**
> **Library is where useful knowledge lives.**
> **My own agent, run in a terminal, keeps the Library organized.**

The only AI-adjacent surfaces the app owns:

- **Review Inbox** — opens `INBOX.md`, a plain file the agent writes ambiguous items to
- **Open Terminal in PeteKM Folder** — launches Terminal.app at the folder root, nothing more

UI copy never says "AI", "assistant", "agent is thinking", or similar. When copy must refer to agent-maintained files (onboarding, settings helper text), it says "your agent" or "agents" plainly — e.g. "Agents read Daily Stickies but never rewrite them."

Voice note (see §54): the app never speaks as "I" or "we", and never speaks *for* the agent.

---

# 3. Overall Design Philosophy

PeteKM should be visually minimal.

The app should **not** have a large, highly customized design system. The design system that exists (§46+) is deliberately tiny: **white, black, one hot electric blue**, hairline borders, system type, and a single pixel-art mark. Its job is to make "default macOS" precise, not to replace it.

## Default to Native macOS

Use normal macOS conventions wherever possible:

- system fonts
- native text rendering
- native controls
- native buttons
- native menus
- native sheets
- native popovers
- native window behavior
- native contextual menus
- native focus states
- native keyboard behavior
- native accessibility behavior

PeteKM should feel at home next to:

- Notes
- TextEdit
- Finder
- Preview
- Terminal
- Xcode

But visually lighter and more compact.

---

## Minimal Branding

PeteKM should have almost no traditional branding.

No elaborate:

- logo system
- illustration system
- icon family
- custom typography system
- gradients
- decorative cards
- background patterns
- branded UI chrome

The UI should mostly disappear and let the user focus on text.

The only intentional brand elements are:

1. the name **PeteKM**
2. the brand accent **electric blue `#0A5CFF`**
3. custom Daily Sticky backgrounds
4. the **PeteKM pixel mark**
5. the pixel wordmark `PETEKM` (Silkscreen, §49) — About window and onboarding only

---

# 4. Brand Color — DECIDED

The brand color is:

> **Electric blue `#0A5CFF`** (`--blue-500`)

Full scale and dark-mode variant in §47. Usage rule:

> **Blue is a verb.** It marks exactly one thing at a time: the active, selected, or actionable element. If two things are blue, one of them is wrong.

Uses:

- the single `primary` button per screen region
- selected sidebar/list row (solid blue fill, white text — the loudest color moment in the app, one per window)
- focus rings
- command palette highlight
- active icon buttons and quiet selection (blue tint `#EDF3FF` + blue glyph/text)
- links
- the pixel mark (drawn in brand blue)

It must **not** dominate the interface, and it must not interfere with user-selected Daily Sticky colors.

---

# 5. Typography — DECIDED

macOS system typography. No shipped custom body/UI face. Exact scale, weights, and tracking in §49.

Summary: SF Pro at native control sizes (28/22/17/15/13/12/11/10), weights 400/500/600 only, SF Mono for paths/counts/versions/keyboard glyphs, and **Silkscreen** (pixel display face) reserved exclusively for the `PETEKM` wordmark.

Markdown styling should create hierarchy without making the editor feel like a word processor.

---

# 6. The PeteKM Pixel Mark — FINAL ASSET EXISTS

## The One Custom Asset

The PeteKM pixel mark is a concrete asset: **a 1-bit, 32×32 pixel portrait of founder Pete** — spiky hair, glasses, goatee — drawn in a single color, electric blue `#0A5CFF`. Master grid: `context/design-system/assets/robopete.grid.json` (asset files keep their historical names).

It is a **brand mark only** — like a woodcut logo. It is never presented as a character, assistant, or AI persona, is never given a name in the UI, never "speaks", and never appears alongside AI-flavored copy.

Hard rules for the mark:

- **One color.** Never introduce a second color, gradient, shadow, outline, glow, or rotation.
- **Transparent interior.** The face interior is transparent, so the mark sits on any solid surface.
- **Integer scaling only.** Render at multiples of 32 px (32/64/128/512…), nearest-neighbor / `image-rendering: pixelated` / SwiftUI `.interpolation(.none)`. Never fractional resampling, never smoothing.
- **Recolor by context, not by whim:** brand blue on light surfaces; white (`--white`) on black or blue surfaces; **solid black in the menu bar** (white in dark mode), following macOS template-image convention — never blue in the menu bar.
- Never re-draw the mark by hand; regenerate from the grid.

The mark must never be:

- glossy
- 3D
- gradient-heavy
- modern "AI" styled
- neon sci-fi
- corporate mascot-ish
- hyper-detailed
- photorealistic

Avoid AI cliché visuals everywhere: sparkle icons, glowing orbs, purple-blue gradients, neural-network graphics, magic-wand metaphors.

---

## Mark Usage

The mark appears sparingly, as branding only:

- app icon (§37)
- About window
- onboarding welcome
- empty states (optional, e.g. empty Inbox)
- menu-bar item, if one exists (16 px template glyph)

It never appears as an activity indicator, status announcer, or "someone working" — there is no in-app AI activity to indicate. The Daily Sticky remains mostly text.

---

# 7. Daily Sticky — Core Visual Direction

The Daily Sticky is the visual heart of PeteKM.

It should feel extremely similar to a good macOS sticky-note app.

Target feeling:

> A small floating note that is always ready, never demanding, and instantly familiar.

The user may open and close the Daily Sticky dozens of times per day. It must feel lightweight enough that opening it becomes nearly subconscious.

---

## Window Character

The Daily Sticky window should be:

- small by default
- easily resizable
- easily draggable
- visually uncluttered
- able to remember size
- able to remember screen position
- able to remember opacity
- able to optionally float above other apps
- instantly summonable with a global keyboard shortcut

The Daily Sticky should reopen in the same place rather than behaving like a new document window every time. It should feel persistent. The user is not "opening a note" — they are revealing the same sticky surface again.

---

## Default Appearance

Current preferred personal default:

- soft yellow background
- approximately 80% opacity
- small floating window
- minimal visible chrome

Exact yellow value and opacity limits can be finalized later.

Soft yellow remains a built-in color option even though the PeteKM brand color is electric blue. **The sticky canvas is the one sanctioned exception to the white/black/blue system palette** (§1.1 note 3).

---

## Custom Sticky Colors

Users should be able to select different Daily Sticky background colors.

Likely color families:

- soft yellow
- pale blue
- pale green
- pale pink
- pale gray
- warm cream
- darker muted variants if desired

Exact values should be determined later. Avoid a huge theme system.

The goal is simply:

> Pick a background color that makes the Daily Sticky pleasant to leave on-screen.

---

## Transparency

Opacity should be adjustable. Transparency is a meaningful part of the experience, not decoration. The Daily Sticky should be able to sit above other windows without completely blocking what is underneath. Opacity preferences should persist.

(Elsewhere in the app, transparency/blur appears in exactly one place: the title bar — §51.)

---

## Always on Top

The user should be able to choose whether the Daily Sticky:

- behaves like a normal window
- stays above other apps

Simple UI language:

> Keep Daily Sticky on Top

or:

> Float Above Other Apps

The setting should persist.

---

# 8. Editor Design

The editor should initially be simple. The experience can gradually borrow proven features from Scratchdown later.

Design target:

> **A fast Markdown editor with just enough live styling to make raw Markdown pleasant to read and write.**

---

## Markdown Syntax Remains Visible

PeteKM should **not** try to hide Markdown syntax completely.

Example:

```md
## Work

This is **important**.

- First thing
- Second thing
```

The user may continue to see `#`, `##`, `**`, `*`, `-`, and other Markdown punctuation. This keeps the file representation honest and reduces editor complexity.

---

## Live Markdown Styling

PeteKM should support lightweight live styling for the basics.

### Headings

Markdown headings should display with visible hierarchy. Use the type scale in §49 as the reference ramp (e.g. `#` ≈ title-1 22, `##` ≈ title-2 17, `###` ≈ title-3 15, body 13). Syntax remains visible.

### Bold

Bold Markdown displays visually bold while retaining syntax.

### Italics

Italic Markdown displays visually italicized while retaining syntax.

### Bullet Lists

Bullet lists support clean indentation and nested indentation. Nested bullets should be visually easy to scan. This matters because the user naturally thinks in bullet structures.

---

## Basic Editing Convenience

The editor should eventually support useful "IDE-lite" conveniences borrowed from Scratchdown where valuable:

- auto-close quotation marks
- auto-close parentheses / brackets / braces
- sensible paired-character deletion
- keyboard-friendly indentation
- useful list continuation behavior

These are editor-quality enhancements. They should not block the core product architecture.

---

# 9. Headers as the Primary Daily Organization System

The user is expected to organize each Daily Sticky primarily with headings.

Example:

```md
# August 19, 2026

## Work

...

## PeteKM

...

## Movies

...
```

This is intentionally simple. The app should not require tags, backlinks, special object types, databases, properties, frontmatter, or metadata panels.

Headers are enough for capture.

---

# 10. New Daily Sticky Experience

On the first open of a new calendar day, PeteKM should create the new Daily Sticky file. The user should have control over what initial headers appear.

## First-Open Prompt

Preferred behavior:

> **New Daily Sticky**
>
> Carry forward yesterday's headers?
>
> **Carry Forward**
>
> **Start Fresh**

The interaction should be tiny and fast. It should not feel like a setup wizard.

---

## Header Behavior Preference

Settings may define the preferred behavior.

### Ask Every Day

Show the first-open prompt.

### Start Fresh

Create a blank Daily Sticky apart from any required automatic date heading.

### Use Default Headers

Automatically insert a user-defined list of headers.

### Carry Forward Yesterday's Headers

Take the heading structure from the previous Daily Sticky and insert those headings into the new file without carrying forward note content.

Core design goal:

> The user should never need to manually recreate the same useful heading structure unless they want to.

---

# 11. Daily Sticky Is Not a Blank Entry Form

Every time the app is summoned during the same day, it should reopen the same Daily Sticky file. It should not create a new entry. It should not show a blank capture form.

Mental model:

> Today has one sticky.

Open it at 8:00 AM, 10:15 AM, 2:30 PM, 11:00 PM — it is always the same document.

---

# 12. Command Palette

The command palette is one of the most important pieces of UI in PeteKM. It allows the app to stay visually minimal without becoming functionally limited. The Daily Sticky does not need a large toolbar or sidebar if most actions are available from a fast keyboard-driven command palette.

---

## Command Palette Feel

It should feel similar to familiar power-user tools: Xcode, VS Code, Raycast, Spotlight.

It should be:

- keyboard-first
- fast
- fuzzy-searchable
- visually compact
- native-feeling
- easy to dismiss

Visual spec: a floating panel using `--shadow-panel` elevation over a `--surface-scrim` (rgba(0,0,0,.28)) overlay, 8 px card radius, hairline structure inside, fade-in with a 4 px rise over 180 ms (§52). Selected row = solid blue fill + white text. Shortcut chips use the KeyHint treatment (§55).

---

## Likely Command Groups

### Daily Sticky

- Open Daily Sticky
- Open Previous Daily Sticky
- Open Date…
- Carry Forward Headers
- Start Fresh

### Library

- Search Library
- Open Library
- Open Library File…
- Open Library in VS Code
- Reveal Library in Finder

### System

- Search All PeteKM
- Review Inbox
- Open Terminal in PeteKM Folder
- Git Sync
- Reveal PeteKM Folder
- Settings

The exact list can evolve.

---

# 13. Search Design

PeteKM should have normal, fast, local search. AI-assisted retrieval happens outside the app, in the user's own terminal agent. Search should not require AI for ordinary retrieval.

## Search Goals

Local search should search more than filenames: filenames, folder names, Markdown file contents, headings, body text. Search should feel immediate. It should work across Daily Stickies, Library files, and optionally the entire PeteKM parent folder.

## Search Results

Search results should include enough context to understand why a result matched: file name, section/header if known, matching text snippet, date for Daily Sticky files, Library path. Counts and paths render in mono (§49): `1,284 notes`, never "lots of notes."

## Search Is Not AI

Local search should remain predictable and fast. Semantic or interpretive retrieval belongs to the user's own agent, in the terminal. Keep them conceptually separate.

---

# 14. Library Interaction

PeteKM should not attempt to recreate VS Code. The Library is primarily a filesystem-backed Markdown knowledge base. The app may provide lightweight search and navigation, but advanced browsing and editing can happen in VS Code. This is a feature, not a compromise.

(If a native Library browsing window is ever built, the design-system UI kit's three-pane layout and metrics — §51 — are the starting point. It is optional, and secondary to the Daily Sticky.)

## Open Library

A command should open the entire PeteKM parent folder or Library folder in VS Code.

## Open Library File

The command palette should support fuzzy searching Library files; selecting a result opens it in VS Code.

## No Need for a Full Library Editor

PeteKM does not need to build a file-tree replacement, multi-document tabs, full project navigation, complex file management, or advanced code-editor features. The Daily Sticky is the custom editor experience. VS Code is an acceptable power-user interface for the Library.

---

# 15. Soft vs Hard Mental Model

Internally: **soft** = daily captured thoughts, **hard** = organized knowledge. Product UI uses **Daily Sticky** and **Library**. "Soft/hard notes" remain internal terminology only.

---

# 16. Immutability of Daily Stickies

This is both a product rule and a design rule. Daily Sticky files represent what the user actually typed. They are historical source records. AI agents must never rewrite, clean up, reorganize, summarize, or otherwise mutate them.

The UI should reinforce this philosophy. Possible onboarding/settings copy:

> Daily Stickies are your original record. Agents read them but never rewrite them.

This should feel reassuring rather than technical.

---

# 17. Filing Happens Outside the App

The app contains zero AI functionality (`spec.md` §15). Filing runs in the user's own terminal via their agent and the `/petekm-*` skills. The app's design consequences:

- **No AI commands** in the palette or menus. The only related conveniences are **Open Terminal in PeteKM Folder** and **Review Inbox**.
- **No AI run UI.** No processing state, no progress bar for filing, no success/failure toasts, no counts. The agent's own terminal output is the report.
- **The app notices agent changes as ordinary external edits** (`spec.md` §8.5) — the editor refreshes the same way it does when VS Code touches a file.

## Inbox

The agent maintains `INBOX.md` for items that are ambiguous or require human judgment: unclear destination, possible duplicate topic, unresolved question, low-confidence filings. The app's involvement is exactly one command — **Review Inbox** — which opens the file in the editor. Missing/empty file shows:

> Nothing in Inbox.

The Inbox should read as "items waiting for your judgment", not an AI error state.

---

# 18. No AI Feedback or Notifications

The app never announces, summarizes, or narrates agent activity. There are no AI status messages, notifications, or result strings — deleted along with the persona. Anything the user learns about a filing run, they learn from their terminal.

(General non-AI status copy — save state, Git results — follows the voice rules in §54.)

---

# 19. No AI Processing UI

Removed. The app runs no AI, so no idle/working/success states exist for it. The determinate ProgressBar (§55) remains for the app's own long operations only — search indexing, folder import.

---

# 20. Git UI

Git is important to the underlying philosophy but should not dominate the UI. Git provides backup, version history, undo/recovery, and confidence in AI-driven edits.

The app may expose a few simple commands:

- Git Sync
- Commit & Push
- Show Git Status

PeteKM does not need to become a Git client.

---

# 21. Settings Design

Settings should use a normal macOS Settings window. Avoid building a custom settings dashboard.

Form conventions (from the design system, §55): **Switch** rows for preferences — label left, switch right, one-sentence description under the label ("Watches copied text while PeteKM runs."). **Checkbox** for multi-select and dialog booleans. **Select** popup for 4+ options; **SegmentedControl** for 2–4 mutually exclusive views.

Likely sections:

## Daily Sticky

- default color
- opacity
- always-on-top behavior
- default size
- new-day header behavior
- default headers

## Editor

- font size
- possible font selection
- line spacing
- Markdown live styling preferences
- auto-close pairs
- list behavior

## Shortcuts

- global show/hide shortcut
- command palette shortcut
- other major actions

## Library

- PeteKM parent folder location
- VS Code integration
- search behavior

## Git

- Git integration settings
- sync/commit preferences

## Appearance

- sticky color presets
- dark/light behavior if needed

---

# 22. Onboarding Design

Onboarding should be extremely short. This is not a consumer SaaS onboarding funnel. The user should get to the Daily Sticky quickly. The most important onboarding task is selecting or creating the PeteKM parent folder.

## Possible Flow

### Welcome

Small introduction with the PeteKM pixel mark (128 px) and the `PETEKM` pixel wordmark — one of only two sanctioned wordmark placements.

Example:

> **PeteKM**
>
> A local second brain built around one simple idea:
> capture now, organize later.

Privacy is stated flatly, never boasted (§54):

> Your notes never leave this Mac.

### Choose Brain Folder

User either selects an existing folder or creates a new folder. Question-style headings are allowed and sentence-cased: "Where should notes live?"

### Create Structure

PeteKM creates the required internal files/folders.

### Daily Sticky Preference

Choose: ask each day / start fresh / use default headers / carry forward headers.

### Done

Open the first Daily Sticky.

Do not teach PKM methodology. No explanations of Zettelkasten, atomic notes, PARA, backlinks, graphs, or tagging systems.

---

# 23. Parent Folder Presentation

The parent folder is important because it is the real source of truth. The app should make this understandable without becoming technical.

Possible Settings label:

> PeteKM Folder

Possible helper text:

> PeteKM stores your Daily Stickies, Library, and agent instructions here as normal files.

The folder can be named anything the user wants.

---

# 24. App Chrome

The Daily Sticky should have very little visible chrome.

Possible elements:

- standard macOS window controls
- subtle title or date if useful
- optional minimal action/menu control
- editor area

Avoid:

- permanent left sidebar
- permanent right sidebar
- toolbar packed with buttons
- bottom status bar unless truly useful
- large title banner
- breadcrumb bars
- AI sidebar
- file navigator

Power should live in keyboard commands and menus.

Where chrome does exist (any full window like Settings or a future Library view), it follows the fixed metrics in §51: title bar 38 px, toolbar 44 px, structure drawn entirely with 1 px hairlines — never gaps of color, never shadows between panes.

---

# 25. Menu Bar / Menus

PeteKM should behave like a proper macOS app. Normal app menus should remain familiar.

Possible high-level menus:

- PeteKM
- File
- Edit
- View
- Daily Sticky
- Library
- Window
- Help

Principle:

> If an action fits naturally into normal macOS menus, use them.

If a menu-bar (status) item exists, its glyph is the 16 px pixel mark rendered as a template image — solid black, white in dark mode, never blue (§57).

---

# 26. Global Shortcut Experience

The global shortcut is central.

Intended interaction:

1. user is doing something else
2. presses global shortcut
3. Daily Sticky appears immediately
4. cursor is ready
5. user types
6. presses shortcut again or switches away
7. Daily Sticky disappears or returns to normal state

This should feel faster than opening Notes or VS Code. No startup splash screen, no folder loading UI, no "new note" flow may interrupt this.

---

# 27. Cursor and Position Persistence

The Daily Sticky should feel continuous.

Remember:

- window position
- window size
- monitor/display where practical
- opacity
- color
- always-on-top preference
- cursor position within today's file
- scroll position where practical

The user should feel like they are returning to the exact same sticky.

---

# 28. Date Presentation

The file may use a technical date-based filename (`2026-08-19.md`), but the visible UI does not need to foreground that filename.

If the Daily Sticky shows a date, use friendly presentation such as:

> Wednesday, August 19

The app should avoid making the user think about filenames during capture. (When a path *is* shown deliberately — settings, search results — it renders in SF Mono, §49.)

---

# 29. Previous Daily Stickies

Older Daily Stickies should be accessible but should not clutter the main editor.

Possible commands:

- Previous Daily Sticky
- Open Date…
- Search Daily Stickies

No permanent calendar sidebar is required. Chronological navigation stays secondary to capture.

---

# 30. Search Result Opening

### Daily Sticky result

Open the historical Daily Sticky in PeteKM, ideally focused near the matching text.

### Library result

Open the Library file in VS Code or PeteKM depending on final product behavior.

---

# 31. Empty States

Empty states should be minimal and may use the pixel mark. Written in second person, with the next step (§54).

### Empty Daily Sticky

Just show the cursor. No motivational copy.

### No Search Results

> Nothing found.

### Empty Inbox

Optionally the pixel mark (64 px, pixelated).

> Nothing in Inbox.

The tone stays plain — no exclamation marks, no emoji, no "You're all set!".

---

# 32. Error Tone

Errors say what happened and what to do — no apology, no hedging (§54).

Good:

> PeteKM couldn't open VS Code.

> Git push failed.

> That folder isn't writable.

Avoid:

> An unexpected synchronization exception occurred.

> Sorry! Something went wrong.

Where practical, offer the next obvious action.

---

# 33. Animation — DECIDED

Motion tokens (§52): durations 80 / 120 / 180 / 260 ms, standard ease `cubic-bezier(.2, 0, .2, 1)`.

- hover/press tints: 80–120 ms
- popovers, command palette, quick panels: fade in with a 4 px rise, 180 ms
- window-level transitions: 260 ms

**Nothing bounces, springs, rotates, or scales.** No spinners where a determinate progress bar will do.

Avoid: constant motion, bouncing mascot, pulsing AI effects, confetti, elaborate loading sequences. Honor Reduce Motion.

---

# 34. Sound

No custom sound design. The app should not make routine sounds during capture. If sound is ever added, it should be optional and restrained.

---

# 35. Dark Mode

PeteKM should respect macOS appearance where practical. Exact dark-mode token values are defined in §47 (dark surfaces `#141414`/`#1C1C1C`/`#1A1A1A`, accent brightened to `#2E72FF`, hairlines `#2E2E2E`).

Daily Sticky colors are allowed to have their own identity: a soft yellow sticky can remain soft yellow in dark mode if text contrast remains comfortable. Normal settings, dialogs, menus, and command palette follow system appearance.

---

# 36. Accessibility

Using native macOS controls and system typography should provide a strong baseline.

Preserve:

- keyboard navigation (PeteKM is keyboard-first; **keyboard focus is always visible** — §53)
- sufficient text contrast
- clear focus states
- resizable text where practical
- VoiceOver compatibility
- predictable controls
- reduced-motion compatibility

Transparency must never make text unreadable. Every icon-only control has a label (§55 IconButton).

---

# 37. App Icon — DONE

The app icon is the PeteKM pixel mark: the blue mark centered on a **white rounded square** on the Apple icon grid (824/1024 square, ~186 px corner radius at 1024), no shadow, no gradient, no background texture.

- Master: `context/design-system/assets/robopete-appicon-1024.png`
- Installed: `PeteKM/Assets.xcassets/AppIcon.appiconset/` (all mac slots 16 → 512@2x, generated from the master)
- Regeneration: render the grid at integer scale onto the white rounded square; downscale from the 1024 master for small slots.

The earlier sticky-note icon concepts are retired. The pixel mark provides the visual identity by itself.

---

# 38. About Window

The About window is one of the few places with slightly more personality — and one of the two sanctioned homes of the `PETEKM` pixel wordmark (Silkscreen, uppercase, tracking `0.08em`).

Possible content:

> **PETEKM**
>
> Your local second brain.
>
> Capture in your Daily Sticky.
> Keep the useful stuff in your Library.
> Let your agent sort it out.

Include the pixel mark (128 px). Version string in SF Mono. Keep it small and charming.

---

# 39. Product Tone

PeteKM should sound like it was built by one person for himself. It should not sound like a startup.

Tone:

- direct
- informal
- concise
- occasionally funny
- technically competent
- not precious
- not motivational
- not productivity-guru-ish

The full, enforceable voice rules are §54. Highlights: sentence case everywhere; "you" for the reader, "PeteKM" in third person, never "I"/"we"; verbs for actions, nouns for places; no emoji ever; no exclamation marks; concrete monospaced numbers; mechanism over magic.

Good:

> Nothing found.

> Open Library in VS Code

> Carry forward yesterday's headers?

> Start fresh

Avoid:

> Unlock your knowledge potential.

> Build a more intentional life.

> Supercharge your productivity.

> Your AI-powered knowledge companion.

Absolutely not.

---

# 40. Core Language Examples

## Daily Sticky

- Open Daily Sticky
- Previous Daily Sticky
- New Daily Sticky
- Carry Forward
- Start Fresh
- Default Headers

## Library

- Open Library
- Search Library
- Open Library File…
- Open Library in VS Code
- Reveal in Finder

## Inbox / agent surfaces

- Review Inbox
- Nothing in Inbox.
- Open Terminal in PeteKM Folder

## System

- Git Sync
- Settings
- Open PeteKM Folder
- Search All PeteKM

(Menu items and buttons render these in sentence case per §54; the proper nouns Daily Sticky, Library, Inbox, PeteKM, VS Code, Finder, Git, Terminal keep their capitals.)

---

# 41. Design Non-Goals

PeteKM should not visually become:

- Notion
- Obsidian
- Craft
- Capacities
- a project management app
- a database UI
- a dashboard
- a knowledge graph
- a chat-first AI app
- an IDE clone
- a journaling app
- a task manager
- a calendar app

Do not add complexity merely because other PKM tools have it.

---

# 42. What the Main Experience Should Feel Like

The perfect PeteKM interaction is almost boring:

The user presses a shortcut. A small translucent soft-yellow sticky appears exactly where it always appears. The cursor is already in today's Markdown file.

The user types:

```md
## Work

Need to figure out how certificate auth actually relates to...
```

The user presses the shortcut again. The sticky disappears.

Hours later, the user opens it again. Same file. Same place.

Later: Command Palette → **Open Terminal in PeteKM Folder**. Terminal opens at the folder root; the user runs `claude` and `/petekm-process-today`. The agent reports what it filed, right there in the terminal. The app stays out of it.

If the user wants to inspect or manually edit the organized knowledge: Command Palette → **Open Library in VS Code**. VS Code opens the real Markdown filesystem.

That is the product.

---

# 43. Design North Star

When making future visual or UX decisions, ask:

> **Does this make PeteKM feel faster, quieter, and more like a tiny native Mac utility?**

If yes, it probably belongs. If it makes PeteKM feel like a full productivity platform, it probably does not.

Second question:

> **Does this reduce friction between having a thought and getting it into the Daily Sticky?**

Capture friction should approach zero.

Third question:

> **Can the agent handle this later instead of making the user organize it now?**

If yes, prefer that.

---

# 44. Branding Summary

| Element | Value |
| --- | --- |
| Product | **PeteKM** |
| Primary capture surface | **Daily Sticky** |
| Organized knowledge | **Library** |
| AI | None in-app; user's own terminal agent |
| Visual identity | Mostly native macOS; white/black/one-blue chrome |
| Brand accent | **Electric blue `#0A5CFF`** (dark mode `#2E72FF`) |
| Daily Sticky default | Soft yellow, translucent (exact values TBD) |
| Custom asset | 1-bit 32×32 **PeteKM pixel mark**, single-color |
| Wordmark | `PETEKM` in Silkscreen — About + onboarding only |
| Typography | macOS system fonts (SF Pro / SF Mono) |
| Core brand philosophy | Almost no branding |

The personality should come from the product itself, not decorative design.

---

# 45. Final Design Principle

PeteKM should look like it has **less design than it actually does**.

The real design work is in:

- removing decisions
- hiding unnecessary controls
- making capture instant
- preserving spatial familiarity
- making Markdown pleasant
- making search fast
- letting macOS handle everything macOS already handles well

The ideal reaction is not:

> "Wow, what a beautifully branded productivity app."

It is:

> "Oh. This is exactly where I dump stuff."

And after an evening terminal run:

> "Holy shit, it's all filed."

---
---

# PART II — DESIGN SYSTEM REFERENCE

Authoritative token values and rules, transcribed from the "PeteKM Design System" Claude Design project. The system's CSS custom-property names are kept as canonical token names; in SwiftUI, mirror them as constants (e.g. `DS.Color.accent`, `DS.Space.s5`). Where the web kit specifies a substitution (Lucide icons, Silkscreen), the SwiftUI-native equivalent is noted.

---

# 46. System Overview

Three colors do everything: **white `#FFFFFF`**, **black `#000000`**, **electric blue `#0A5CFF`**. Greys are pure neutral — no warm or cool tint — and exist only for chrome, hairlines, and secondary text. One illustration exists in the entire brand: the PeteKM pixel mark. There are **no images, no photography, no patterns, no textures, no gradients — anywhere**. If a surface needs to recede, it gets 2% darker, not a gradient. If a design feels like it needs a photo or illustration, it needs less content instead.

---

# 47. Color Tokens

## Primitives (light)

| Token | Hex | Notes |
| --- | --- | --- |
| `--white` | `#FFFFFF` | |
| `--black` | `#000000` | |
| `--blue-050` | `#EDF3FF` | accent tint |
| `--blue-100` | `#D6E3FF` | accent tint strong |
| `--blue-300` | `#5C8DFF` | |
| `--blue-500` | `#0A5CFF` | **the brand blue** |
| `--blue-600` | `#0047D6` | hover |
| `--blue-700` | `#0038A8` | press |
| `--grey-025` | `#FAFAFA` | sunken surface |
| `--grey-050` | `#F5F5F5` | sidebar |
| `--grey-100` | `#EDEDED` | hover tint |
| `--grey-150` | `#E3E3E3` | **the hairline** |
| `--grey-200` | `#D6D6D6` | field borders |
| `--grey-300` | `#B8B8B8` | strong borders |
| `--grey-400` | `#8E8E8E` | tertiary text |
| `--grey-500` | `#6B6B6B` | secondary text |
| `--grey-600` | `#4A4A4A` | |
| `--grey-700` | `#2E2E2E` | |
| `--grey-800` | `#1A1A1A` | |
| `--red-500` | `#D8342B` | error |
| `--amber-500` | `#B07500` | warning |
| `--green-500` | `#1C7A3E` | success |

## Semantic aliases (light)

- Accent: `--accent` = blue-500 · `--accent-hover` = blue-600 · `--accent-press` = blue-700 · `--accent-tint` = blue-050 · `--accent-tint-strong` = blue-100
- Text: primary = black · secondary = grey-500 · tertiary = grey-400 · inverse = white · accent/link = accent
- Surfaces: window = white · sidebar = grey-050 · card = white · sunken = grey-025 · hover = grey-100 · press = grey-150 · selected = accent · selected-quiet = blue-050 · overlay = `rgba(255,255,255,.82)` · scrim = `rgba(0,0,0,.28)`
- Borders: hairline = grey-150 · strong = grey-300 · field = grey-200 · focus = accent
- Status: error / warning / success as above — **semantic colors appear only as text or 1 px outlines, never as a filled banner.**

## Dark mode overrides

| Token | Dark value |
| --- | --- |
| text-primary | white |
| text-secondary | grey-300 |
| text-tertiary | grey-400 |
| surface-window | `#141414` |
| surface-sidebar | `#1C1C1C` |
| surface-card | `#1A1A1A` |
| surface-sunken | `#101010` |
| surface-hover | `#252525` |
| surface-press | `#2E2E2E` |
| surface-overlay | `rgba(20,20,20,.82)` |
| border-hairline | `#2E2E2E` |
| border-strong | `#4A4A4A` |
| border-field | `#3A3A3A` |
| accent | `#2E72FF` |
| accent-tint | `#12203D` |

## Usage rules

- **Blue is a verb** (§4). One solid-blue selection per window; one primary button per screen region.
- Greys never carry meaning; they only structure.
- No color ever appears as a large filled area except the blue selected row and the blue primary button.

---

# 48. Backgrounds, Borders, Elevation

- Backgrounds are flat: window white, sidebar `#F5F5F5`, inspector/sunken `#FAFAFA`.
- **Hairlines carry the entire structure:** `1px solid #E3E3E3`. Panes are separated by hairlines, never by gaps or gutters of color.
- **A card is: 1 px hairline border, 8 px radius, white fill, no shadow.** No inner shadows, no glows, no colored borders, no "left accent border" cards.
- Shadows exist only on layers that genuinely float above the window:
  - `--shadow-popover`: `0 4px 16px rgba(0,0,0,.10), 0 0 0 1px rgba(0,0,0,.06)` — menus, popovers
  - `--shadow-panel`: `0 12px 40px rgba(0,0,0,.16), 0 0 0 1px rgba(0,0,0,.06)` — command palette, quick-capture-style panels
  - `--shadow-focus`: `0 0 0 3px` accent at 28% — focus ring
- Blur exists in exactly one place: the title bar — `rgba(255,255,255,.82)` + `saturate(180%) blur(20%)` to match macOS chrome. Blur is never decorative. Overlay scrim: `rgba(0,0,0,.28)`.

---

# 49. Typography Tokens

Families:

- `--font-system`: `-apple-system` → SF Pro (SwiftUI: `.system`)
- `--font-mono`: SF Mono / Menlo (SwiftUI: `.system(design: .monospaced)`)
- `--font-pixel`: **Silkscreen** (Google Fonts) — the pixel display face. Used *only* for the `PETEKM` wordmark. Never in UI chrome, never body copy. (Flagged substitution: if a licensed 80s-Mac bitmap face is preferred later, it replaces Silkscreen 1:1.)

Scale (px):

| Token | Size | Use |
| --- | --- | --- |
| display | 28 | onboarding hero only |
| title-1 | 22 | window-level headings |
| title-2 | 17 | section headings |
| title-3 | 15 | subsection headings |
| body | 13 | default UI + reading text |
| callout | 12 | dense secondary UI |
| caption | 11 | metadata, helper text |
| micro | 10 | ALL-CAPS micro-labels (`LIBRARY`, `DETAILS`) |

- Line heights: tight 1.15 · snug 1.3 · body 1.45 · loose 1.6
- Weights: **400 / 500 / 600 only** (700 exists solely for the pixel face). No light, no black.
- Tracking: `-0.01em` on titles, 0 on body, `0.04em` on ALL-CAPS micro-labels, `0.08em` on the pixel wordmark.
- Composite styles: body = 400 13/1.45 · ui-label = 500 13/1.2 · heading = 600 17/1.3 · caption = 400 11/1.3.
- Mono is used for: paths, counts, versions, sizes, durations, and keyboard glyphs. `1,284 notes`, `3.2s cold index`, `4.2 MB`.

---

# 50. Spacing Scale

2 px base scale — deliberately dense, like a real Mac app:

`--space-1..12` = **2, 4, 6, 8, 12, 16, 20, 24, 32, 40, 56, 72**

Gutters: window 16 · sidebar 8 · row 10. Control heights: sm 20 · md 24 · lg 32. Hairline = 1 px.

## Corner radii

| Token | Value | Use |
| --- | --- | --- |
| `--radius-xs` | 3 | tiny chips |
| `--radius-sm` | 5 | **fields** |
| `--radius-md` | 6 | **controls/buttons** |
| `--radius-lg` | 8 | **cards** |
| `--radius-window` | 10 | window |
| `--radius-pill` | 999 | **only** toggle switches and count badges |

Nothing is a circle except traffic lights, toggle knobs, and the unread dot.

---

# 51. Layout Metrics (full windows)

Fixed chrome, from the UI kit (designed at 1280×800):

- title bar **38 px** (the one blurred surface)
- toolbar **44 px** (second row: search + view controls)
- sidebar **220 px**
- list column **300 px**
- inspector **260 px**
- reading measure capped at **680 px**

Nothing is fluid except the reading pane. These metrics apply to any full app window PeteKM ever grows (Settings, a future Library browser). The Daily Sticky window intentionally has almost none of this chrome (§24).

---

# 52. Motion Tokens

| Token | Value | Use |
| --- | --- | --- |
| `--dur-instant` | 80 ms | hover tints |
| `--dur-fast` | 120 ms | press, control transitions |
| `--dur-base` | 180 ms | popovers/panels: fade + 4 px rise |
| `--dur-slow` | 260 ms | window-level transitions |
| `--ease-standard` | `cubic-bezier(.2, 0, .2, 1)` | default |

Nothing bounces, springs, rotates, or scales. Determinate progress bars (4 px, real percentage) instead of spinners wherever the total is knowable.

---

# 53. Interaction States

- **Hover:** 4–5% neutral tint (`--surface-hover`); one step darker blue on primary buttons. Never a scale change, never a shadow appearing.
- **Press:** slight darkening (`brightness(.94)` equivalent). Nothing shrinks or bounces.
- **Focus:** 1 px accent border + 3 px soft blue ring (accent at 28%). Keyboard focus is always visible — PeteKM is keyboard-first.
- **Selected (loud):** solid blue fill + white text — sidebar/list rows. One per window.
- **Selected (quiet):** blue tint (`--accent-tint`) + blue text/glyph — tags, active icon buttons, segmented controls.
- **Disabled:** 40% opacity, default cursor. No grey-out recoloring.

---

# 54. Content Voice (enforceable rules)

The voice is **a competent friend explaining a tool they built**. Plain, short, specific. It never sells and never gushes.

1. **Sentence case everywhere.** Buttons, menu items, headings, labels: "Quick capture", "Rebuild index", "Where should notes live?" ALL CAPS only for micro-labels and the pixel wordmark. (Product proper nouns — Daily Sticky, Library, Inbox, PeteKM — keep their capitals.)
2. **"You" for the reader; the app in third person.** Never "we", never "I", and the app never speaks for the agent. ✅ "PeteKM stores notes as plain files." ❌ "I filed this for you." ❌ "We've organized your notes."
3. **State the mechanism, not the magic.** ✅ "Watches copied text while PeteKM runs." ❌ "Intelligently captures everything, everywhere."
4. **Verbs for actions, nouns for places.** Buttons are verbs (Capture, Open note, Rebuild index); sidebar and tabs are nouns (Inbox, Library, Everything).
5. **No emoji. Ever.** The only pictorial element in the brand is the pixel mark.
6. **No exclamation marks.** No "Oops!", "Nice!", "You're all set!". A finished state reads "Inbox clear."
7. **Privacy stated flatly, never boasted.** ✅ "Nothing is uploaded, now or later." ❌ "Your privacy is our top priority!"
8. **Numbers concrete and monospaced.** `1,284 notes`, `4.2 MB`. Never "lots of notes" or "blazing fast".
9. **Empty states: second person + the next step.** ✅ "New captures land here automatically."
10. **Errors: what happened and what to do, no apology.** ✅ "That folder isn't writable."
11. **Length:** UI labels 1–3 words; helper text one sentence; body copy 1–3 short sentences per paragraph.

Example strings in-voice:

> Type anything. File it later.
> Plain Markdown files. PeteKM never moves them.
> Index up to date · 1,284 notes
> Your notes never leave this Mac

---

# 55. Component Inventory

18 primitives exist in the design-system kit. In SwiftUI, prefer the native control and apply the system's metrics/tokens; build custom only where AppKit/SwiftUI has no equivalent styling.

## Core

- **Button** — variants: `primary` (blue fill, one per screen region), `secondary` (white + hairline), `ghost` (text only), `destructive` (red label + hairline — never red fill). Heights sm 24 / md 32 / lg 38. Optional 16 px leading icon.
- **IconButton** — icon-only, toolbars and headers; **accessibility label required**. `active` = blue tint + blue glyph. Sizes 22 / 26 / 32.
- **SegmentedControl** — 2–4 mutually exclusive views inside one pane. 5+ choices → Select.
- **Badge** — tiny uppercase pill for counts/states. Tones: neutral, accent, quiet, success, warning, error — semantic tones outlined, not filled.
- **Tag** — knowledge tag chip with drawn `#` prefix; selectable; removal affordance in editors.
- **Card** — hairline container (§48). Never a shadow. Optional title + mono meta line; `interactive` adds hover tint.
- **PixelMark** — the PeteKM pixel mark as a component so it is never re-drawn by hand. Sizes = multiples of 32; single color prop.

## Forms

- **TextField** — single-line or multiline; 5 px radius, `--border-field`, focus ring per §53.
- **SearchField** — the primary way into the knowledge base; keep visible in toolbar; shows shortcut chip (⌘K).
- **Checkbox** — multi-select and dialog booleans.
- **Switch** — preferences rows only: label left, switch right, one-sentence description below label.
- **Select** — popup menu for 4+ options (sort orders, folders, agents).

## Navigation

- **TitleBar** — 38 px, blurred overlay surface, title + mono subtitle ("1,284 notes · local"), trailing icon buttons.
- **Toolbar** — 44 px second row: segmented control leading, search center, primary action trailing.
- **SidebarItem** — source-list rows: 15 px stroke icon, label, mono count; selection = solid blue fill + white text; `depth` for nesting.

## Feedback

- **EmptyState** — title + one-sentence description + optional single action; optionally the pixel mark.
- **ProgressBar** — 4 px determinate bar with label + real percentage. Indexing/import progress (the app's own operations only — no AI runs exist).
- **KeyHint** — shortcut chips: mono glyphs `⌘ ⇧ ⌥ ⌃ ↩ ⌫` in tiny hairline-bordered keys. Appears beside actions, in menus, in the command palette.

Deliberately **not** in the system: Dialog, Tooltip, Toast, Avatar, Tabs — nothing in the product calls for custom versions; use native macOS sheets/alerts/tooltips, and SegmentedControl where a web app would use tabs.

---

# 56. Iconography

- **In the app: SF Symbols.** The platform-native, correct choice. Target optical weight: matches a 24 px-grid, 1.5-stroke outline set rendered at ~15 px in chrome and 12–13 px in captions (the design-system mocks used Lucide as a stand-in for exactly this geometry).
- Icons are **monochrome and stroked** — never filled, never two-tone, never colored except when inheriting selected/active blue.
- Icons never appear without a purpose: no decorative icons in headings, cards, or empty states.
- **Emoji are never used.** Unicode is used only for keyboard glyphs and the `·` separator in metadata lines ("Index up to date · 1,284 notes").
- The one raster "icon" is the pixel mark, always rendered pixelated.

---

# 57. Brand Marks

## PeteKM pixel mark

See §6 for rules. Renders: 32 / 64 / 128 / 512 px from `robopete.grid.json` (historical filename). On white/light: brand blue. On black or blue: white. Menu bar: template image (black; system inverts in dark mode), 16 px.

## Wordmark

`PETEKM` set in Silkscreen, uppercase, tracking `0.08em`, in black or brand blue. Sanctioned placements: About window, onboarding welcome. Never in menus, buttons, toolbars, or window titles.

## App icon

§37. White rounded square (Apple icon grid), blue mark centered at ~74% of the square, no effects.

---

# 58. Applying the System in SwiftUI (practical mapping)

- Mirror tokens as a `DS` namespace (Color/Font/Spacing/Radius/Duration constants) generated once from §47–§52. Support light/dark via asset-catalog colors carrying the §47 dark overrides.
- Prefer native controls (`.buttonStyle(.borderedProminent)` tinted `#0A5CFF`, native `Toggle`, `Picker`, `TextField`) before custom styling; reach for custom drawing only where the system prescribes something AppKit doesn't do (hairline three-pane structure, KeyHint chips, pixel-mark rendering, command palette).
- Pixel mark: load the PNGs (or render the grid) with `.interpolation(.none)` and `.antialiased(false)`.
- The strict palette applies to chrome. The Daily Sticky canvas color/opacity remains a user setting (§7) and is the only surface allowed outside white/black/blue.
- When the design system and `spec.md` disagree, the spec wins; when this document and the live Claude Design project disagree, update whichever is stale — they are meant to stay in sync.
