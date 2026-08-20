# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this repo is

This repo is the **native macOS app** PeteKM (SwiftUI, Xcode project). It is *not* a PeteKM knowledge folder.

Do not confuse the two `CLAUDE.md` files:
- **This file** — instructions for developing the Swift app.
- The `CLAUDE.md` the app *generates inside a user's PeteKM folder* at onboarding — a template artifact shipped by the app, describing the `daily/` + `library/` safety contract for RoboPete. Editing that template is a product-content change, not a change to these instructions.

Current state: the repo is still the stock Xcode SwiftUI+SwiftData template (`Item.swift`, list-based `ContentView`). None of the product exists yet. `context/spec.md` (product behavior) and `context/DESIGN.md` (visual/UX/vocabulary) are the source of truth for what to build.

## Build / test

```bash
xcodebuild -scheme PeteKM -configuration Debug build         # build
xcodebuild -scheme PeteKM test                               # all tests (unit + UI)
xcodebuild -scheme PeteKM test -only-testing:PeteKMTests     # unit tests only
xcodebuild -scheme PeteKM test -only-testing:PeteKMTests/PeteKMTests/example   # one test
```

Targets: `PeteKM` (app), `PeteKMTests` (Swift Testing — `@Test`/`#expect`, not XCTest), `PeteKMUITests` (XCTest). Single scheme, `PeteKM`.

## Architecture constraints that come from the spec

These are non-negotiable product rules with direct code consequences. Read the relevant spec section before designing around them.

**Markdown on disk is the only canonical store.** No database may hold note content. Any index, cache, or state must be fully rebuildable from the `.md` files (`spec.md` §2.2, §5.8). The template's SwiftData `Item`/`ModelContainer` wiring contradicts this and should be removed rather than extended — if SwiftData survives at all, it may only hold derived search-index/cache data.

**`daily/` is an immutable ledger; `library/` is mutable.** AI never writes to `daily/` (§2.5, §13.3). Processing state goes in the disposable `.robopete-state.json`, never as markers inside a Daily Sticky. This boundary should be enforced in code paths that hand paths to an agent, not just documented.

**The app is not the only writer.** VS Code, Claude Code, and Finder edit the same files concurrently. File I/O must detect external changes, never silently clobber newer on-disk content, and surface a real conflict path (§8.5, §19.4). Autosave writes should be atomic.

**Sandbox + user-chosen folder.** The PeteKM folder lives anywhere the user picks, so persistent access requires security-scoped bookmarks. `project.pbxproj` currently has `ENABLE_USER_SELECTED_FILES = readonly` — writing notes requires read/write, and shelling out to `git`/`code`/`claude` (§12, §15, §17) conflicts with the sandbox; decide sandbox posture deliberately before building folder access.

**Capture never blocks.** Git failures, agent failures, and missing VS Code must never prevent opening or saving today's Daily Sticky (§17.4, §15.3). Degrade, don't gate.

**Editor keeps Markdown syntax visible.** Live styling (heading size hierarchy, bold, italic, list indentation) applies *on top of* still-visible `#`, `**`, `-` markers — not a WYSIWYG that hides syntax (§9.1–9.2). This rules out most rich-text approaches.

## Key file/folder shapes the app generates

A PeteKM folder the app initializes (`spec.md` §5): `daily/YYYY-MM-DD.md`, `library/**.md`, `.claude/skills/robopete-*/SKILL.md`, `ROBOPETE.md`, `INDEX.md`, `CLAUDE.md`, `AGENTS.md`, `.robopete-state.json`, `.gitignore`. Onboarding must never silently overwrite any of these if they already exist (§19.2).

## Vocabulary (user-facing strings)

`DESIGN.md` §2 fixes the terminology and it should be used exactly in UI, commands, and menus: **Daily Sticky** (not journal/entry/page), **Library** (not vault/knowledge base), **RoboPete** (not "AI Assistant"), **PeteKM** with no qualifier. Copy tone: terse and plain — "RoboPete filed 4 things.", "Nothing found." No streaks, no motivational or productivity-guru phrasing (`DESIGN.md` §39).

Visual direction: default macOS look, near-zero branding; the only custom asset is RoboPete as 1980s-Mac pixel art (`DESIGN.md` §3, §6). Prefer native controls over a custom design system.
