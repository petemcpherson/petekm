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
        "petekm-process",
        "petekm-rebuild-index",
        "petekm-organize",
        "petekm-status",
    ]

    // MARK: - INDEX.md (§6.2)

    static let index = """
    # Library Index

    Maintained by the filing skills. Run /petekm-rebuild-index to repair it at any
    time. Three sections: Placement guide and Areas are short and always read;
    Files is searched, never read whole.

    ## Placement guide

    - Running lists (movies, books, restaurants, gift ideas) → `library/Lists/`
    - Work topics, projects, decisions → `library/Work/`
    - People, companies, products → `library/Reference/`
    - Unsure → `INBOX.md`

    ## Areas

    The Library is empty so far.

    ## Files

    None yet.
    """

    // MARK: - .gitignore (§6.2)

    static let gitignore = """
    .petekm-state.json
    .petekm-scratch.md
    .petekm-backups/
    .DS_Store
    """

    /// Lines `.gitignore` must carry for the Scratch pane. Appended to an existing
    /// `.gitignore` on folders created before Scratch existed — a missed line here
    /// means private scratch text gets committed.
    static let scratchIgnoreLines = [
        ".petekm-scratch.md",
        ".petekm-backups/",
    ]

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
    - `.petekm-scratch.md` — the user's private scratch pad. Not yours. See below.

    ## The rule that never bends

    `daily/` is read-only source material. Never edit, rewrite, reformat, rename,
    move, delete, summarize, tag, link, or add "processed" markers to any file in
    `daily/`. Not to fix a typo. Not to add a heading. Not once.

    If you need to record processing state, write it to `.petekm-state.json`.

    `library/`, `INDEX.md`, and `INBOX.md` are yours to maintain.

    ## The other rule that never bends

    `.petekm-scratch.md` is the user's scratch pad, held open in the app beside the
    Daily Sticky. It is scratch on purpose: short-lived lists, a pasted secret, a
    reminder for the next few days. It is not knowledge and it is not a note.

    Never read it, open it, grep it, summarize it, quote it, file it, copy any part
    of it into `library/`, `INDEX.md`, or `INBOX.md`, or mention its contents. Treat
    it as though the file were not there. It is `.gitignore`d for the same reason.

    ## Before filing anything

    Read `AGENTS.md`. It carries the full librarian policy: provenance, preserving
    uncertainty, updating existing files instead of creating near-duplicates, and
    the Inbox rules.

    ## Skills

    Project skills live in `.claude/skills/`:

    - `/petekm-process` — file new Daily Stickies into the Library; pass a date to reprocess one day.
    - `/petekm-rebuild-index` — regenerate `INDEX.md` from the Library.
    - `/petekm-organize` — deliberate Library restructuring.
    - `/petekm-status` — what has and has not been processed.

    ## Working at scale

    This folder may hold thousands of files. Do not load it wholesale. Read the
    Placement guide and Areas sections of `INDEX.md`; grep its Files section rather
    than reading it. Search filenames, headings, and full text with ordinary
    filesystem tools, then open only the files and line ranges you actually need.
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

    **`.petekm-scratch.md` does not exist to you.** It is the user's scratch pad —
    the pane under the Daily Sticky in the app — and it holds exactly the things
    they do not want kept: a two-day to-do list, a pasted credential, a phone number
    for this afternoon. Never read it, grep it, summarize it, quote it, or copy any
    fragment of it anywhere. Never file it. Never mention what is in it. It is
    `.gitignore`d and it is not knowledge.

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

    Consult the Placement guide in `INDEX.md` before choosing a folder. If no rule
    fits and you create a new file anyway, add a one-line rule so the next run
    files the same kind of item the same way.

    ### Destination hints from the Daily Sticky

    The user may name a destination in the Daily Sticky itself. **A path that
    starts with `library/` is a destination hint**, wherever it appears — after an
    arrow, in parentheses, or bare on its own line:

    ```md
    ## Acme call -> library/Work/Acme.md
    - renewal moved to 2027

    - keyboard for dad's birthday -> library/Lists/Gifts.md
    ```

    - **A hint outranks the Placement guide and outranks your judgment.** It is an
      explicit instruction. Do not deliberate, do not look for a better home.
    - **Scope comes from position.** On a heading line → everything under that
      heading until the next heading. On a bullet or sentence → that item only.
      Alone on its own line → from there to the next heading. An item-level hint
      beats the heading it sits under.
    - **Folder** (`library/Work/`) → choose or create a file inside it, named your
      usual way. **File** (`library/Work/Acme.md`) → that exact file; create it if
      it does not exist.
    - **Only `library/` paths count.** A pasted `src/api/auth.ts`, a URL, or a shell
      command is ordinary content, never a hint.
    - **Unresolvable hint** — typo, a path that collides with an existing file, or
      genuinely ambiguous → do not guess and do not silently fall back. Send the
      item to `INBOX.md` with the hint quoted and one line on why it failed.
    - The hint is part of the Daily Sticky: never strip it, rewrite it, or mark it
      handled (§2). Do not copy the arrow into the Library file — record provenance
      the normal way (§5).
    - Hints are optional and rare. Most items carry none; file those exactly as before.

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

    `INDEX.md` is a map, not a summary store. It does not list Daily Stickies. Three
    sections:

    - **Placement guide** — where each kind of item goes. Short. User-editable.
    - **Areas** — one line per top-level Library folder: path, description, file
      count. Always read in full.
    - **Files** — one line per Library file, grouped by folder. Grep it; never read
      it whole once the Library is large.

    The filesystem is the truth and the index is a cache of it. If any Files path no
    longer resolves, or a Library file is newer than `INDEX.md`, the index is stale:
    repair it (`/petekm-rebuild-index`, incremental) before relying on it.

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

    ## 14. Sync

    This folder may be a Git repository shared across two machines. When it is,
    `/petekm-process` pulls before it reads and commits, pulls again, and pushes
    after it writes — so the Library you file into is current, and your work reaches
    the other device promptly.

    The rules are the same ones the app follows:

    - Commit before any network operation. Nothing on disk is ever exposed to a pull
      while uncommitted.
    - Never force-push. Not as a fallback, not ever.
    - Never resolve a conflict on your own — not "pick newer", not "merge and hope".
      A conflict stops the run and asks the user.
    - No Git, or no repository, or no remote → carry on and say so plainly at the
      end. Missing Git never blocks filing.

    ## 15. Working at scale

    Assume this folder is large. Read `CLAUDE.md`, then the Placement guide and
    Areas of `INDEX.md`; grep the Files section. Search filenames, headings, and full
    text, then open only what you need. Never load the whole folder or the whole
    Files section into context.
    """

    // MARK: - Skills (§14.2)

    static func skill(_ name: String) -> String {
        switch name {
        case "petekm-process": return process
        case "petekm-rebuild-index": return rebuildIndex
        case "petekm-organize": return organize
        case "petekm-status": return status
        default: return ""
        }
    }

    private static let process = """
    ---
    name: petekm-process
    description: File new Daily Stickies into the Library. With no argument, process every Daily Sticky newer than the last processed one, oldest-first; pass a date, filename, or plain-language date to reprocess just that day. Use when the user asks to process, file, catch up on, or organize notes in a PeteKM folder, or invokes /petekm-process.
    ---

    # Process Daily Stickies

    Read `AGENTS.md` first. Its policy governs everything below.

    ## Steps

    0. **Pull first.** Run:

       ```bash
       git rev-parse --is-inside-work-tree >/dev/null 2>&1 && git pull --rebase --autostash
       ```

       Not a Git repository, or Git isn't installed → skip silently and carry on;
       Process is never blocked by the absence of Git. If the pull reports a
       conflict, **stop entirely and process nothing.** Report: "Sync conflict —
       couldn't pull latest changes before processing. Resolve it (ask me, or run
       `git status` yourself), then run /petekm-process again." Never process
       against a repo mid-conflict, and never guess which side is right.
    1. **Pick the target Daily Stickies.**
       - **No argument (the common case):** read `lastProcessedDailyNote` from
         `.petekm-state.json` and list every `daily/*.md` whose date is newer.
         Process them **oldest-first, one file at a time**, so later days can build
         on Library files the earlier days created. It makes no difference whether
         the app created a file or the user dropped it in by hand — a Daily Sticky
         is just `daily/YYYY-MM-DD.md`. If the state file is missing or the marker
         is null, ask which day to start from rather than processing everything.
       - **One argument:** resolve it to a single daily file — accept `2026-08-19`,
         `2026-08-19.md`, `daily/2026-08-19.md`, or a plain-language date. Ambiguous
         → ask. Missing → list nearby existing Daily Stickies and stop. Process only
         that day, regardless of the state marker.
       - Nothing newer to process → say so and stop.
    2. Read the Daily Sticky in full. Do not modify it in any way.
    3. Check `INDEX.md` freshness: if any path in its Files section no longer
       exists, or `find library -name '*.md' -newer INDEX.md` prints anything,
       run the incremental repair from `/petekm-rebuild-index` first.
    4. Read the Placement guide and Areas sections of `INDEX.md`. Grep the Files
       section as needed; do not read it whole.
    5. For each item worth keeping (`AGENTS.md` §3): if it carries a `library/…`
       destination hint, file it exactly there and skip the rest of this step
       (`AGENTS.md` §6). Otherwise search the Library for an existing destination
       before creating anything new; follow the Placement guide for new files and
       add a rule when none fits.
    6. Update or create Library files conservatively. Preserve uncertainty (§4) and
       record provenance back to the source Daily Sticky (§5).
    7. Anything you cannot confidently place goes to `INBOX.md` as a copy, with its
       source date and a one-line reason (§11).
    8. If `INBOX.md` already holds items, try to file them too, and remove the ones
       you successfully filed.
    9. Add a Files line for every file you created, and update Areas counts or
       the Placement guide if they changed. Do not rewrite the rest of the index.
    10. Repeat steps 2–9 for each remaining target, oldest-first.
    11. On success, update `.petekm-state.json`: `lastSuccessfulProcessing` (ISO
        8601, local offset), and `lastProcessedDailyNote` **only if** this run
        processed a note newer than the recorded one. Back-filling or reprocessing
        an older day never moves the marker backward or falsely forward.
    12. **Commit and publish.** Run:

        ```bash
        git add -A && git commit -m "PeteKM: processed <dates>" && git pull --rebase --autostash && git push
        ```

        The second pull matters: the app or another device may have pushed while
        you were processing. If that pull conflicts, your commit is safe on the
        local branch — report "Processed successfully and committed locally, but
        couldn't sync — conflict pulling latest changes. Run Sync from the app, or
        ask me." No remote configured → the commit still stands; report "Processed
        and committed locally. No GitHub remote is set, so nothing was pushed."
        Not a Git repository → skip this step silently.
    13. Report: dates processed, files created, files updated, items skipped, the
        count sent to `INBOX.md`, and the sync result.

    ## Never

    - Modify anything in `daily/`.
    - Restructure the Library — that is `/petekm-organize`.
    - Guess a destination to avoid using the Inbox.
    - Force-push, or resolve a sync conflict on your own.
    """

    private static let rebuildIndex = """
    ---
    name: petekm-rebuild-index
    description: Regenerate or repair INDEX.md from the Library's files. Use when the index is stale, wrong, missing, or after a large reorganization, or when the user invokes /petekm-rebuild-index.
    ---

    # Rebuild the Library index

    The Library filesystem is the source of truth for this operation. Do **not** read
    Daily Stickies to build the index.

    Default mode is **incremental**: keep what is still correct, fix what drifted.
    Do a full rewrite only when the user asks for one or the index is missing or
    unparseable.

    ## Steps

    1. Walk `library/` and collect every `.md` file with its path.
    2. Compare against the current Files section:
       - path in index, file gone → drop the line;
       - file on disk, not in index (new, renamed, or moved) → describe it;
       - file newer than `INDEX.md` → re-check that its line is still accurate;
       - everything else → keep the existing line verbatim, including any wording
         the user edited.
    3. For each file that needs a description, read enough to write one accurate
       line — usually the title and first section, not the whole file.
    4. Regenerate Areas from the folders on disk: one line per top-level folder
       with path, description, and file count. Keep existing descriptions where the
       folder still exists.
    5. Keep the Placement guide as is. Only add a rule if a folder exists that no
       rule mentions; never delete a rule the user wrote.
    6. Write `INDEX.md`:

       ```md
       # Library Index

       Last rebuilt: YYYY-MM-DD

       ## Placement guide

       - Running lists (movies, books, restaurants, gift ideas) → `library/Lists/`

       ## Areas

       - `library/Work/` — job topics, projects, decisions (140 files)

       ## Files

       ### library/Work

       - `library/Work/MFT.md` — Managed file transfer concepts, terminology, protocols, and authentication.
       ```

    7. Descriptions stay on one line. The index is a map, not a summary store, and
       never lists Daily Stickies. Files are grouped by folder in a stable order.
    8. Report: files added, removed, re-described, and kept.

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
    5. Rebuild `INDEX.md` to match the new structure, including Areas and any
       Placement guide rules that pointed at moved folders.
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
    4. Whether `INDEX.md` looks stale — any Library file newer than it, any Files
       path that no longer resolves, or any top-level folder missing from Areas.
    5. `INBOX.md`: item count, or "Nothing in Inbox."
    6. If the folder is a Git repository, whether the working tree is clean, and how
       it stands against the remote — from
       `git rev-list --left-right --count HEAD...@{upstream}`, worded plainly:
       "3 commits not yet pushed", "2 new commits on GitHub, not yet pulled", or
       "Up to date with GitHub." If there is no upstream, omit the line; do not
       report it as an error.

    Keep it short and concrete. End with the single most useful next command, if
    there is one — usually `/petekm-process`.
    """
}
