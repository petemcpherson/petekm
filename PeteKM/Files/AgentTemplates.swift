//
//  AgentTemplates.swift
//  PeteKM
//
//  The agent-facing files the app writes into a PeteKM folder (spec §5.3–§5.7,
//  §6.2, §13, §14). These are plain Markdown shipped as content: the app has
//  zero AI functionality (§15) and never reads them back.
//
//  Written once at setup, never auto-updated (§6.5).
//

import Foundation

enum AgentTemplates {

    static let skillNames = [
        "petekm-process-today",
        "petekm-process-date",
        "petekm-rebuild-index",
        "petekm-organize",
        "petekm-status",
    ]

    // MARK: - INDEX.md (§6.2)

    static let index = """
    # Library Index

    The Library is empty so far. This index is maintained by the filing skills;
    run /petekm-rebuild-index to regenerate it at any time.
    """

    // MARK: - .gitignore (§6.2)

    static let gitignore = """
    .petekm-state.json
    .DS_Store
    """

    // MARK: - .petekm-state.json (§5.7)

    static let state = """
    {
      "lastSuccessfulProcessing": null,
      "lastProcessedDailyNote": null
    }
    """

    // MARK: - CLAUDE.md (§5.5)

    static let claudeMd = """
    # CLAUDE.md

    This folder is a PeteKM folder: a second brain kept as ordinary Markdown files.
    There is no database. The files on disk are the only source of truth.

    ## Layout

    - `daily/YYYY-MM-DD.md` — Daily Stickies. Raw, unedited daily capture.
    - `library/**.md` — the Library. Durable, organized knowledge.
    - `INDEX.md` — a map of the Library.
    - `INBOX.md` — items that could not confidently be filed (created only when needed).
    - `AGENTS.md` — the full librarian policy.
    - `.petekm-state.json` — small, disposable operational state.

    ## The rule that never bends

    `daily/` is read-only source material. Never edit, rewrite, reformat, rename,
    move, delete, summarize, tag, link, or add "processed" markers to any file in
    `daily/`. Not to fix a typo. Not to add a heading. Not once.

    If you need to record processing state, write it to `.petekm-state.json`.

    `library/`, `INDEX.md`, and `INBOX.md` are yours to maintain.

    ## Before filing anything

    Read `AGENTS.md`. It carries the full librarian policy: provenance, preserving
    uncertainty, updating existing files instead of creating near-duplicates, and
    the Inbox rules.

    ## Skills

    Project skills live in `.claude/skills/`:

    - `/petekm-process-today` — file today's Daily Sticky into the Library.
    - `/petekm-process-date` — the same, for a given date or daily filename.
    - `/petekm-rebuild-index` — regenerate `INDEX.md` from the Library.
    - `/petekm-organize` — deliberate Library restructuring.
    - `/petekm-status` — what has and has not been processed.

    ## Working at scale

    This folder may hold thousands of files. Do not load it wholesale. Read
    `INDEX.md`, search filenames, headings, and full text with ordinary filesystem
    tools, then open only the files and line ranges you actually need.
    """

    // MARK: - AGENTS.md (§5.6, §13)

    static let agentsMd = """
    # AGENTS.md

    Policy for any AI agent working in this PeteKM folder. `CLAUDE.md` is the short
    orientation; this file is the full contract. The two must never contradict each
    other.

    ## 1. The role

    You are a librarian. The user captures raw thought into Daily Stickies and never
    stops to organize. You turn that raw capture into durable, findable knowledge in
    the Library — without altering the source material.

    ```text
    daily/  (source, ledger)  --read only-->  YOU  --create/update-->  library/
    ```

    There is no persona here. No name, no mascot, no voice. Just the contract.

    ## 2. The safety boundary

    **`daily/` is an immutable ledger.** Never:

    - rewrite or reword a Daily Sticky;
    - fix spelling, grammar, or formatting in one;
    - add a summary, tags, links, or backlinks to one;
    - rename, move, or delete one;
    - insert "processed" markers of any kind.

    Processing state belongs in `.petekm-state.json`, which is disposable and may be
    deleted at any time without losing knowledge.

    **`library/`, `INDEX.md`, and `INBOX.md` are mutable.** They exist to be
    maintained, corrected, merged, and reorganized over time.

    Your filing work stays inside this folder. Routine filing never needs to modify
    files elsewhere on the computer.

    ## 3. What to extract

    When reading a Daily Sticky, look for anything with future value:

    - a durable fact or concept the user learned;
    - a useful explanation worth keeping;
    - an entry for a running list (movies, books, restaurants, gift ideas);
    - a project decision, or the reasoning behind one;
    - an idea that belongs in an existing project file;
    - a person, company, or product reference worth maintaining;
    - a process or procedure;
    - a stated preference;
    - an unresolved question worth preserving;
    - a recurring topic that has earned its own Library file.

    You are not required to preserve every sentence. Scheduling noise, passing
    thoughts, and duplicated context can stay in the Daily Sticky.

    ## 4. Preserve uncertainty

    Distinguish, and keep the distinction visible in the Library:

    - facts the user stated plainly;
    - the user's own speculation;
    - unresolved questions;
    - your inference;
    - outside knowledge you brought.

    Never silently promote uncertainty to certainty. If the Daily Sticky says
    "I think certificate auth might work this way?", the Library says the user
    believes this and that it is unconfirmed — not "Certificate auth works this way."

    Mark your own additions as yours when they are not in the source.

    ## 5. Provenance

    When you add or materially update information, record where it came from. Plain
    Markdown, no wikilink syntax, no citation bureaucracy:

    ```md
    Source: `daily/2026-08-19.md`
    ```

    or:

    ```md
    Sources:
    - `daily/2026-08-18.md`
    - `daily/2026-08-19.md`
    ```

    The goal is traceability back to the ledger.

    ## 6. Prefer updating over proliferating

    Search the Library before creating a file. If `library/Work/MFT.md` exists, new
    MFT knowledge goes there — not into `MFT 2.md`, `More MFT.md`, or
    `MFT Notes August.md`.

    Create a new file only when it draws a genuinely useful durable boundary.

    ## 7. Human edits win

    The user edits Library files directly, in any tool. The on-disk version is always
    authoritative. Preserve deliberate human structure and wording; make targeted
    edits rather than regenerating a whole file, unless you were explicitly asked to
    rewrite it.

    ## 8. Running lists are first-class

    Not every Library file is an article. Movies Watched, Books, Gift Ideas,
    Restaurants, Home Theater, Project Decisions, Questions to Research — these are
    append-oriented living documents. Append in their existing shape; do not
    restructure them to look like prose.

    ## 9. Organization may evolve — slowly

    You may create folders and move Library files when it genuinely helps. But
    routine daily processing is conservative: file today's items, adjust the index if
    the structure materially changed, stop.

    Large restructures belong in an explicit `/petekm-organize` run, never as a side
    effect of daily filing.

    ## 10. INDEX.md

    `INDEX.md` is a map, not a summary store. Concise descriptions and paths, grouped
    by area. It does not list Daily Stickies. Update it when the Library's structure
    changes; rebuild it from the Library filesystem when it drifts.

    ## 11. INBOX.md

    When you cannot confidently decide where something belongs, do not guess. Append
    it to `INBOX.md` at the folder root.

    - Create `INBOX.md` lazily, the first time it is needed. Its absence is normal.
    - Each item is a plain bullet: the ambiguous content (copied or briefly
      restated), its source date, and one line on why it was ambiguous.

      ```md
      - Try "Foundation" audiobook — from 2026-08-19. Unsure: Books list or Audiobooks list?
      ```

    - Inbox items are **copies, not moves**. The original text stays in the Daily
      Sticky, untouched.
    - `INBOX.md` is mutable on both sides: the user edits, annotates, reorders, and
      deletes items; so may you.
    - On later runs, treat remaining inbox items as filing input alongside
      unprocessed Daily Stickies. File what you now can, record provenance in the
      target Library file, and **remove filed items from `INBOX.md`**. Leave what you
      still cannot place.
    - A line the user deleted means "ignore this". Never resurrect it.

    ## 12. Destructive actions

    Deleting or overwriting a Library file, collapsing several files into one, or
    moving a large part of the tree are all destructive. Say what you intend to do
    and get agreement first. Never delete anything in `daily/`, under any
    instruction short of the user explicitly and specifically asking for it.

    ## 13. Reporting

    End every filing run with a short, concrete report: which Library files you
    created or updated, what you deliberately skipped, and how many items went to
    `INBOX.md`. The app shows no AI status of any kind — your terminal output is the
    only feedback the user gets.

    ## 14. Working at scale

    Assume this folder is large. Read `CLAUDE.md`, consult `INDEX.md`, search
    filenames, headings, and full text, then open only what you need. Never load the
    whole folder into context.
    """

    // MARK: - Skills (§14.2)

    static func skill(_ name: String) -> String {
        switch name {
        case "petekm-process-today": return processToday
        case "petekm-process-date": return processDate
        case "petekm-rebuild-index": return rebuildIndex
        case "petekm-organize": return organize
        case "petekm-status": return status
        default: return ""
        }
    }

    private static let processToday = """
    ---
    name: petekm-process-today
    description: File today's Daily Sticky into the Library. Use when the user asks to process, file, or organize today's notes in a PeteKM folder, or invokes /petekm-process-today.
    ---

    # Process today's Daily Sticky

    Read `AGENTS.md` first. Its policy governs everything below.

    ## Steps

    1. Determine today's local date and open `daily/YYYY-MM-DD.md`. If it does not
       exist, say so and stop — do not create it.
    2. Read the Daily Sticky in full. Do not modify it in any way.
    3. Read `INDEX.md` to learn the Library's current shape.
    4. For each item worth keeping (`AGENTS.md` §3), search the Library for an
       existing destination before creating anything new.
    5. Update or create Library files conservatively. Preserve uncertainty (§4) and
       record provenance back to the source Daily Sticky (§5).
    6. Anything you cannot confidently place goes to `INBOX.md` as a copy, with its
       source date and a one-line reason (§11).
    7. If `INBOX.md` already holds items, try to file them too, and remove the ones
       you successfully filed.
    8. Update `INDEX.md` only if the Library's structure materially changed.
    9. On success, update `.petekm-state.json` with `lastSuccessfulProcessing` (ISO
       8601, local offset) and `lastProcessedDailyNote`.
    10. Report: files created, files updated, items skipped, and the count sent to
        `INBOX.md`.

    ## Never

    - Modify anything in `daily/`.
    - Restructure the Library — that is `/petekm-organize`.
    - Guess a destination to avoid using the Inbox.
    """

    private static let processDate = """
    ---
    name: petekm-process-date
    description: File a specific past Daily Sticky into the Library, given a date or daily filename. Use when catching up on missed days, importing older notes, or re-running a day after changing librarian rules, or when the user invokes /petekm-process-date.
    ---

    # Process a specific Daily Sticky

    Same procedure as `/petekm-process-today`, for a date the user names.

    ## Steps

    1. Resolve the argument to a daily file: accept `2026-08-19`, `2026-08-19.md`,
       `daily/2026-08-19.md`, or a plain-language date. If it is ambiguous, ask.
    2. If the file does not exist, list nearby existing Daily Stickies and stop.
    3. Read `AGENTS.md`, then follow `/petekm-process-today` steps 2–8 against that
       file.
    4. Update `.petekm-state.json` only if this run processed a note **newer** than
       the recorded `lastProcessedDailyNote`; back-filling an older day must not make
       newer days look processed.
    5. Report as usual, naming the date you processed.

    If asked for a range of dates, process them oldest-first, one file at a time, so
    later days can build on Library files the earlier days created.
    """

    private static let rebuildIndex = """
    ---
    name: petekm-rebuild-index
    description: Regenerate or repair INDEX.md from the Library's files. Use when the index is stale, wrong, missing, or after a large reorganization, or when the user invokes /petekm-rebuild-index.
    ---

    # Rebuild the Library index

    The Library filesystem is the source of truth for this operation. Do **not** read
    Daily Stickies to build the index.

    ## Steps

    1. Walk `library/` and collect every `.md` file with its path.
    2. For each file, read enough to write one accurate line — usually the title and
       first section, not the whole file.
    3. Group entries by top-level Library folder, in a stable order.
    4. Write `INDEX.md`:

       ```md
       # Library Index

       Last updated: YYYY-MM-DD

       ## Work

       - `library/Work/MFT.md` — Managed file transfer concepts, terminology, protocols, and authentication.
       ```

    5. Keep descriptions to one line. The index is a map, not a summary store, and
       never lists Daily Stickies.
    6. Report how many files were indexed and any path in the old index that no
       longer resolves.

    If the Library is empty, restore the placeholder text rather than writing an
    empty file.
    """

    private static let organize = """
    ---
    name: petekm-organize
    description: Deliberate Library restructuring - find duplicates, merge near-duplicate files, simplify folders, rename unclear files, repair index paths. Use only when explicitly asked to organize, clean up, or restructure the Library, or when the user invokes /petekm-organize.
    ---

    # Organize the Library

    This is the one place where larger structural change is allowed. It is always
    explicitly invoked, never bundled into daily filing.

    Read `AGENTS.md` first — §7 (human edits win) and §12 (destructive actions) apply
    directly here.

    ## Steps

    1. Survey `library/`: paths, titles, sizes, obvious topic overlap.
    2. Identify candidates:
       - exact or near-duplicate files;
       - several thin files that clearly belong together;
       - unclear or inconsistent filenames;
       - folders with one file, or folders that have grown shapeless;
       - `INDEX.md` paths that no longer resolve.
    3. **Propose the plan and wait for agreement before changing anything.** List
       each move, merge, rename, and deletion explicitly.
    4. On approval, execute carefully:
       - merging preserves both sources' content and provenance lines;
       - renames and moves keep the file's history-worthy content intact;
       - nothing in `daily/` moves, ever.
    5. Rebuild `INDEX.md` to match the new structure.
    6. Report every change as a before → after list.

    Prefer the smaller reorganization. A Library that is slightly untidy is better
    than one the user no longer recognizes.
    """

    private static let status = """
    ---
    name: petekm-status
    description: Report filing status - last processed Daily Sticky, unprocessed days, whether INDEX.md looks stale, and Inbox size. Use when the user asks what has been filed or what is pending, or invokes /petekm-status.
    ---

    # PeteKM status

    Informational only. This skill never writes to `library/`, `INDEX.md`,
    `INBOX.md`, or `.petekm-state.json`.

    ## Report

    1. `lastSuccessfulProcessing` and `lastProcessedDailyNote` from
       `.petekm-state.json` (say so plainly if the file is missing — it is
       disposable, and its absence only means state was lost, not that filing failed).
    2. Daily Stickies newer than `lastProcessedDailyNote`, listed oldest-first.
    3. Library size: file count, and count per top-level folder.
    4. Whether `INDEX.md` looks stale — modification time older than the newest
       Library file, or paths that no longer resolve.
    5. `INBOX.md`: item count, or "Nothing in Inbox."
    6. If the folder is a Git repository, whether the working tree is clean.

    Keep it short and concrete. End with the single most useful next command, if
    there is one.
    """
}
