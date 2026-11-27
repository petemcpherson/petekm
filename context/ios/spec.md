# iOS Specification: PeteKM on iPhone (and iPad)

**Status:** Draft for implementation. Written 2026-11-26.

**Relationship to other specs.**
- `context/spec.md` (product), `context/DESIGN.md` (visuals, vocabulary, copy tone) and
  `context/sync-v2/spec.md` (automatic sync) stay the source of truth. This spec adds a
  second client. It changes nothing about the folder contract, and the Mac app keeps
  working unchanged except for the small copy changes in §13.
- Sync v2 §12 listed "iOS or any third device type" as out of scope. This spec lifts that
  for one device type, iPhone/iPad, and adds no server.

---

## 1. Problem

PeteKM lives on two Macs. GitHub is the only shared storage. Away from a Mac, Pete has no
good way to:

- write in today's Daily Sticky, or
- read a note in the Library.

## 2. Goal

Open PeteKM on the phone and land in today's Daily Sticky, current with whatever the Macs
pushed. Type. Put the phone away, and the notes reach GitHub. The Macs pick them up the way
they pick up each other's work today.

Browse and read every Markdown note in the Library. Editing a Library note is also
supported, with the same no-loss rules.

Measured outcome: Pete never thinks about which device he wrote on.

## 3. Principles (normative)

1. **Markdown on disk is still the only canonical store.** The phone keeps a local copy of
   the Markdown files in a normal folder with the exact PeteKM shape (§5). Any other state
   (the sync manifest, the search index) is rebuildable from GitHub plus that folder.
2. **GitHub stays the only shared storage.** No PeteKM server, no webhooks, no iCloud.
3. **Capture never blocks.** Network, auth, rate limits, or a half-finished first download
   never prevent opening or saving today's Daily Sticky.
4. **No data loss, ever.** The phone never force-pushes, never overwrites a newer GitHub
   version, and never discards a local edit. Where it cannot merge, it keeps both copies.
5. **Same rules as the Macs.** Same file paths, same commit subject and device trailer, same
   `daily/` union rule. A Mac sees a phone commit as just another device's commit.
6. **`daily/` immutability is unchanged.** It binds agents. The phone runs no agents.
7. **Quiet when fine, visible when not.** Same status light, same copy, same notices as
   sync v2 §8, with the device noun changed (§10.4).

## 4. Decisions (made in this spec)

| # | Decision | Why |
| --- | --- | --- |
| D1 | Native iOS app (SwiftUI + UIKit text view), universal iPhone/iPad. | Native typing quality; reuses the Swift model code. |
| D2 | Same repo, same Xcode project, new `PeteKMiOS` target. Shared code moves into a `Shared/` folder compiled into both apps. | No duplication, no drift between clients on paths, dates, templates, merge rules. |
| D3 | Sync over the **GitHub REST API (Git Database endpoints)**, not an embedded git library. | iOS can't run `git`. libgit2 on iOS means building a C library, credential plumbing, and partial rebase support. The API gives an atomic compare-and-swap on the branch, which is all the safety we need. |
| D4 | The phone mirrors **only Markdown files** in `daily/` and `library/`, plus root `INDEX.md` and `INBOX.md` (§6.1). | That is what the phone shows. Everything else stays on GitHub untouched, and every phone commit builds on GitHub's tree, so those files are preserved. |
| D5 | `daily/` merges by **line union** on the phone too, in Swift (§8.3). | Matches the Mac's `.gitattributes` rule. Never drops a line. The user said "probably yes" to keeping both sets of lines; it is also the safest choice. |
| D6 | A `library/` (or root file) edited on **both** a Mac and the phone becomes **two files**: GitHub's version stays at the path, the phone's version is saved beside it as a conflict copy (§8.4). | The Mac's "pause and resolve in a terminal" has no phone equivalent. A conflict copy loses nothing and uses the Mac's existing `(conflict …)` naming. |
| D7 | Auth is a **fine-grained personal access token** scoped to the one repository, kept in the Keychain. | Five-minute setup, no OAuth app, narrowest permission. OAuth device flow is a later option (§15). |
| D8 | Library files open **read-only** with an **Edit** button. Daily Stickies open editable. | Scrolling and tapping on a phone easily places a caret and inserts text. Reading is the main Library use. |
| D9 | No Scratch, agents, terminal, VS Code, hotkey, menu bar, or onboarding of agent files on the phone. | Mac-only concerns. Scratch is gitignored, so it can't sync anyway. |
| D10 | The phone never creates the folder structure, agent files, `.gitignore`, or `.gitattributes`. It requires an existing PeteKM repository made by the Mac app. | One place initializes folders (the Mac). |
| D11 | Device name is a setting, default "iPhone" or "iPad". | Since iOS 16, `UIDevice.current.name` returns only the model name without a special entitlement. |

## 5. The local folder

- Location: `Application Support/PeteKM/Repos/<owner>__<repo>/` inside the app container.
  Not exposed in the Files app. The PeteKM app is the only writer on the phone, which
  removes the "other writers" problem that the Mac has (spec §8.5).
- Shape: exactly a PeteKM folder (`PeteKMFolder`), with only the mirrored files present
  (§6.1). `daily/YYYY/MM/YYYY-MM-DD.md`, `library/**.md`, `INDEX.md`, `INBOX.md`.
- Because the shape matches, `PeteKMFolder`, `DailyFiles`, `DailySession`, `StickyDocument`,
  `NewDayComposer`, `SearchIndex` and the rest of the shared model work on it unchanged.
- Excluded from iCloud/iTunes backup (`isExcludedFromBackup`). GitHub is the backup.
- The search index cache lives in `Caches/` (disposable).

## 6. What syncs

### 6.1 Mirror scope

A path is **in scope** when it is a regular file (mode `100644` or `100755`) and one of:

- matches `daily/**/*.md`
- matches `library/**/*.md`
- is exactly `INDEX.md` or `INBOX.md`

and its blob is at most 2 MB. Everything else is **out of scope**: never downloaded, never
written, never deleted by the phone. That includes `.claude/`, `CLAUDE.md`, `AGENTS.md`,
`.petekm-state.json` (already gitignored), images and PDFs in `library/`, `.gitattributes`.

Dot-prefixed path components are out of scope, matching `SearchIndex` (map Layer 3b).

The rules live in one pure function, `MirrorScope.includes(path:mode:size:)`, used for both
directions.

### 6.2 The manifest

`Application Support/PeteKM/Repos/<owner>__<repo>.sync.json`, written atomically after
every step that changes it. It is **outside** the mirrored folder.

```json
{
  "version": 1,
  "owner": "pete", "repo": "notes", "branch": "main",
  "baseCommit": "<sha>",
  "baseTree": "<sha>",
  "files": { "daily/2026/11/2026-11-26.md": "<blob sha>", "...": "..." },
  "refETag": "\"...\"",
  "lastFetchAt": "2026-11-26T14:02:00Z"
}
```

- `baseCommit` is the GitHub commit that the local folder was last reconciled with.
- `files` maps each **downloaded** in-scope path to the blob SHA it had in `baseCommit`. A
  path in the remote tree that is missing from `files` has simply not been downloaded yet.
  A path in `files` that is missing on disk is restored from GitHub (§8.8); it never becomes
  a deletion.
- Local changes are detected by **content hash**, never by timestamps: the git blob SHA of a
  file is `SHA1("blob <byte count>\0" + bytes)`, computed locally (`GitBlobHash`).

### 6.3 Self-healing property (normative)

Every decision compares three content hashes per path: base (manifest), local (disk), and
remote (GitHub's current tree). Two sides with the same hash are treated as agreeing, even
if they got there separately. Consequences:

- A crash after GitHub accepted a push but before the manifest was saved is harmless. The
  next run sees local == remote for those paths and simply adopts the new base.
- A crash halfway through writing downloaded files is harmless. Written files match
  remote; unwritten files still differ and get written next time.
- A lost or corrupted manifest triggers recovery (§8.6), never a blind overwrite.

## 7. Talking to GitHub

### 7.1 Endpoints used

All requests: `Authorization: Bearer <token>`, `Accept: application/vnd.github+json`,
`X-GitHub-Api-Version: 2022-11-28`, a generic `User-Agent: PeteKM-iOS`.

| Purpose | Endpoint |
| --- | --- |
| Validate repo + permission | `GET /repos/{o}/{r}` (`permissions.push`, `default_branch`, `private`) |
| Branch head | `GET /repos/{o}/{r}/git/ref/heads/{branch}` with `If-None-Match` |
| Commit → tree, parents, message | `GET /repos/{o}/{r}/git/commits/{sha}` |
| Full file list | `GET /repos/{o}/{r}/git/trees/{tree}?recursive=1` |
| File content | `GET /repos/{o}/{r}/git/blobs/{sha}` with `Accept: application/vnd.github.raw+json` |
| New blob (non-UTF-8 only) | `POST /repos/{o}/{r}/git/blobs` |
| New tree | `POST /repos/{o}/{r}/git/trees` with `base_tree`; entries with `content` (UTF-8) or a blob `sha`; never `sha: null` (§8.8) |
| New commit | `POST /repos/{o}/{r}/git/commits` |
| Move the branch | `PATCH /repos/{o}/{r}/git/refs/heads/{branch}` with `force: false` |
| Device of incoming commits | `GET /repos/{o}/{r}/commits?sha={branch}&per_page=30` (message trailers) |

`force: false` makes the branch move a **fast-forward only** compare-and-swap. If anyone
pushed since our base, GitHub answers `422` and nothing changes. That is the whole
concurrency story and it is why the phone can never clobber a Mac's push.

Blob and tree objects are immutable by SHA. The client caches commit→tree lookups in memory
and never re-downloads a blob whose SHA is already on disk.

### 7.2 Rate limits

- Authenticated limit is 5,000 requests per hour.
- The ref poll uses `If-None-Match`. A `304 Not Modified` does not count against the limit,
  so polling is free when nothing changed.
- A normal run costs: 1 ref + 1 commit + 1 tree + N blobs (incoming) + 3 (tree, commit,
  ref) for a push.
- On `403`/`429` with `x-ratelimit-remaining: 0` or `retry-after`, the engine stops, keeps
  all local work, and backs off until `x-ratelimit-reset`. Status line: "GitHub asked
  PeteKM to slow down. Syncing again at 14:30."
- The first download of a large Library may take several hours of budget (one request per
  file). It resumes across runs (§9.3).

### 7.3 Truncated trees

If `?recursive=1` returns `truncated: true` (over 100,000 entries or 7 MB), the client
walks the tree non-recursively, descending only into `daily/` and `library/` and their
subtrees. Root-level files come from the root tree.

### 7.4 Errors

| Response | Meaning to the engine | Outcome |
| --- | --- | --- |
| No network, DNS, timeout (15s per request) | Offline | `.offline` |
| `401` | Token invalid or expired | `.authFailed` |
| `403` without rate-limit headers, or `404` on the repo | Token lacks access | `.authFailed` |
| `403`/`429` rate limited | Back off | `.rateLimited(until:)` |
| `409` on any Git Database call | Repository empty or busy | `.failed` (retry on next trigger) |
| `422` on ref update | Not a fast-forward: someone pushed | Re-merge and retry (§8.1 step 7) |
| `5xx` | GitHub trouble | `.offline` (same back-off) |

## 8. The sync run

### 8.1 Sequence

One engine (`PhoneSyncEngine`) for every trigger and for Sync Now. At most one run in
flight; triggers during a run set a "run again" flag (same coalescing as sync v2 §5).

```
1. [main actor] Flush: StickyDocument.saveNow() on the open document.
2. GET ref (If-None-Match). If 304 → remote head == baseCommit.
   Network failure → .offline (local work stays on disk; nothing lost).
3. Compute LOCAL changes against the manifest (hash every in-scope file on disk):
     added, modified, missing (missing is restored, never sent, §8.8).
4. If remote head == baseCommit and no local changes → .synced. Done.
5. If remote head != baseCommit:
     a. GET commit → tree, GET tree recursive. Compute REMOTE changes against the manifest:
        added, modified, deleted (in scope only), plus not-yet-downloaded paths.
     b. Build the merge plan (§8.2) — pure function of base/local/remote hashes.
     c. Download every blob the plan needs (remote side, and base side for union merges).
        Network only; no disk writes yet.
     d. [main actor] Flush again. Re-hash paths the plan touches; if any local hash changed
        since step 3, rebuild the plan for those paths (pure, no network unless a new
        base blob is needed — then loop to c, max 2 times).
     e. [main actor] Apply the plan to disk (atomic writes, deletes), reconcile the open
        document (§8.5). Save manifest: baseCommit = remote head, files = remote hashes for
        every path that now matches remote.
6. If local changes remain (local-only edits, union merges, conflict copies):
     a. POST tree (base_tree = remote tree; changed and new paths with `content`, keeping
        each existing path's mode; never a deletion, §8.8–8.9).
     b. POST commit (parent = remote head; message §8.7).
     c. PATCH ref, force:false.
        200 → save manifest (baseCommit = new commit, files updated with local hashes).
        422 → go to step 2 (another device pushed meanwhile). Max 3 attempts per run,
              then .pending; the next trigger tries again.
7. Return outcome; update status (§10).
```

The network work happens before the main-actor apply, and the apply is a single
synchronous pass on the main actor right after a flush. The user cannot type in between,
so the open document is never dirty during the apply. This is stronger than the Mac's
"well under 100 ms" window (sync v2 §6.2).

### 8.2 The merge plan

For each in-scope path, with `B` = manifest hash (or absent), `L` = local hash (or absent),
`R` = remote hash (or absent):

| Case | Condition | Action |
| --- | --- | --- |
| Unchanged | `L == R` | Nothing (adopt `R` as new base) |
| Remote only changed | `L == B`, `R != B` | Write `R` locally (or delete if `R` absent) |
| Not yet downloaded | `B` absent, `L` absent, `R` present | Download `R` (§9.3 ordering) |
| Local only changed | `R == B`, `L != B` | Keep local; it goes out in step 6 |
| Both changed, `daily/` | `L != B`, `R != B`, `L != R`, path in `daily/` | Union merge (§8.3) of `B`/`R`/`L`; write result; it goes out in step 6 |
| Both changed, elsewhere | same, path not in `daily/` | Conflict copy (§8.4) |
| Remote deleted, local edited | `R` absent, `L != B` | Keep local (it is re-added in step 6) |
| Local missing, remote present | `L` absent, `B` present, `R` present | Restore `R` locally. **The phone never sends a deletion** (§8.8) |
| Both added, `daily/` | `B` absent, `L` and `R` present, differ | Union merge with empty base |
| Both added, elsewhere | same, not `daily/` | Conflict copy |

The plan is a pure function (`MergePlanner.plan(base:local:remote:)`) with exhaustive tests.

### 8.3 Line union for `daily/`

Same semantics as git's built-in `union` merge driver that the Macs use
(`daily/**/*.md merge=union`, sync v2 §7):

- A three-way, line-based merge of base, remote ("theirs"), and local ("ours").
- Regions changed on only one side take that side.
- Where both sides changed the same region differently, keep **remote lines first, then
  local lines**. This matches the Mac's order during a rebase ("the other device's lines
  come first, then this device's", sync v2 §7.3).
- Never drop a line. Never write conflict markers.
- Byte-exact parity with `git merge-file --union` is a goal, checked in tests on macOS (§14),
  but the hard requirement is the property: **every line of `R` and every line of `L` that
  isn't a removal agreed by both sides is present in the result.**
- A union merge shows the notice **"Merged today's Daily Sticky from two devices. Check the
  order."** (6s) when the path is today's sticky, and **"Merged the Daily Sticky for
  Nov 24 from two devices. Check the order."** otherwise.

Implementation: Myers line diff (`LineDiff`) of base→local and base→remote, then a diff3
walk (`UnionMerge`). Pure Swift in `Shared/`.

### 8.4 Conflict copies (everything outside `daily/`)

When a Library note (or `INDEX.md`, `INBOX.md`) changed on both sides:

1. Write the phone's version to the conflict-copy path made by the existing
   `StickyDocument.conflictURL(for:at:)`: `Note (conflict 2026-11-26 1402).md`, in the same
   folder.
2. Write GitHub's version at the original path.
3. Both go out in step 6 (the copy is a new local file; the original now matches remote).
4. Notice: **"A Library note changed on two devices. Both versions are kept: Note and Note
   (conflict 2026-11-26 1402)."** (8s).

A Mac that later pulls this sees one ordinary new file. Pete or the agent tidies it.

### 8.5 The open document during a run

- Apply happens right after a flush on the main actor (§8.1 step 5d–e), so the document is
  clean. `StickyDocument.reconcileWithDisk()` then does a silent reload.
- The caret is preserved: the editor keeps the selection's offset measured from the end of
  the unchanged prefix, so text inserted above the caret pushes it down instead of
  snapping it to the top. (`SelectionPreserver`, pure, shared with the Mac later.)
- A Library file open read-only reloads silently.
- If the open file was deleted remotely and is unchanged locally, it is deleted and the
  view returns to today's Daily Sticky with the notice "That note was removed on another
  device."

### 8.6 Lost or unreadable manifest

The folder exists but the manifest is missing, unreadable, or for a different repo:

1. Treat `B` as absent for every path (all files "both added").
2. `daily/` files that differ from remote merge by union with an empty base. Because every
   line is kept, this can duplicate lines; the notice says to check the order.
3. Other differing files become conflict copies.
4. Identical files are adopted silently.

This path should never run in normal use. It exists so that no state loss on the phone can
ever turn into note loss.

### 8.7 Commit message and device trailer

Identical to the Macs (sync v2 §6.3):

```
PeteKM backup 2026-11-26 14:02

PeteKM-Device: Pete's iPhone
```

- Subject uses the local time, `yyyy-MM-dd HH:mm`, same formatter as `GitSupport`.
- Device name comes from Settings (D11).
- Author and committer are left to GitHub (the token's owner), as with a normal push.
- One commit per run that has local changes. No squashing (sync v2 §12 decision stands).

### 8.8 The phone never deletes anything on GitHub

No tree the phone builds contains a `sha: null` entry. Reasons:

- The only phone-side deletion is `DailySession.pruneIfBlank` removing a blank Daily
  Sticky. If that file came from GitHub, a Mac may have it open. Pushing the deletion would
  make the Mac's `StickyDocument.reconcileWithDisk()` write its copy back ("deleted or
  moved out from under us"), and the two devices would trade commits.
- So on the phone, `pruneIfBlank` only removes a sticky that **was never synced** (absent
  from the manifest). It reaches this through the `canPrune` hook (§12.2). A blank sticky
  that came from GitHub stays; the Mac prunes it under its own rules.
- If an in-manifest file is ever missing on disk anyway (a bug, a crash), the planner
  restores it from GitHub (§8.2). Missing never means "delete".
- The Library browser offers no delete.

### 8.9 Preserving what the phone doesn't own

- Every tree the phone creates uses `base_tree` = GitHub's current tree, so every path the
  phone doesn't list is kept byte-for-byte: agent files, images, `.gitattributes`,
  `.gitignore`, out-of-scope folders.
- A changed entry keeps the **mode** it has in GitHub's tree (`100644` or `100755`). Only a
  brand-new file gets `100644`.
- Paths are the exact strings from GitHub's tree. Local disk names are mapped back to them
  through the manifest, never re-derived, so Unicode normalization (NFC/NFD) on disk can't
  create a "new" path. A local file with no manifest match is compared under NFC before it
  is treated as new.
- File bytes are written and read unchanged: no newline normalization, no BOM handling, no
  trailing-newline fix-up.

## 9. Triggers and first download

### 9.1 Triggers

| Trigger | When | Notes |
| --- | --- | --- |
| Became active | `scenePhase` → `.active` | Always (arrival) |
| Foreground poll | Every 60s while active | Ref poll with `If-None-Match`; free when unchanged |
| Network regained | `NWPathMonitor` unsatisfied → satisfied | Always |
| Editing idle | No keystroke for **15s** in a Daily Sticky or Library note | Departure; only with local changes |
| Moving to background | `scenePhase` → `.background` | Flush, then a departure run inside `beginBackgroundTask` (iOS allows about 30s). Expiration handler cancels network work; local files are already safe. |
| New day | Opening today with no file yet | Pre-New-Day (§9.2) |
| Background refresh | `BGAppRefreshTask`, opportunistic | Arrival only, best effort; iOS decides when (§9.4) |
| Sync Now | Status popover, Settings | Always shows a notice, ignores back-off |

Editing idle is 15s, not the Mac's 60s: phone sessions are short and the app is often
swiped away right after typing.

### 9.2 Pre-New-Day

Reuses `DailySession`'s existing deferral unchanged (sync v2 §6.5): compose today's text,
show it at once, defer the file write, run an arrival sync. The deferral ends at the first
of: today's file arrives (adopt it), the user types (write), or the budget passes (write).
Budget on the phone is **3s** (cellular is slower than a Mac's Wi-Fi). `DailySession`
reaches the engine through the new `NewDaySyncing` protocol (§12.2), so the Mac and phone
share this logic.

### 9.3 First download

After connecting (§11):

1. Fetch the tree. Count in-scope files.
2. Download in this order, saving the manifest every 25 files so progress survives a kill:
   1. today's and the previous 7 days' Daily Stickies,
   2. `INDEX.md`, `INBOX.md`,
   3. the rest of `daily/`, newest first,
   4. `library/`, by path.
3. Today's Daily Sticky opens and is writable as soon as step 2.1 finishes (or fails). If
   the first download is still running, a thin progress line shows under the header:
   "Downloading Library… 312 of 1,040." Nothing waits on it.
4. Up to 6 blob downloads in parallel.
5. Writes during the first download follow the same merge plan, so typing in today's
   sticky while the rest downloads is safe.

### 9.4 Background refresh

Register `BGAppRefreshTask` (`com.petekm.PeteKM.ios.refresh`). On launch by the system, run
an arrival sync with a 25s budget so the next open is already current. This is a nicety:
iOS may never run it, and nothing depends on it. Departure work is never left to it; it
happens in the background-transition task.

### 9.5 Back-off

| Situation | Automatic behavior | Clears when |
| --- | --- | --- |
| `.offline` | Local saves continue. No requests until `NWPathMonitor` is satisfied or the app becomes active. | Next successful request |
| `.authFailed` | No automatic requests. Status red. | Token replaced in Settings, or Sync Now succeeds |
| `.rateLimited(until:)` | No requests until `until`. | Time passes |
| `.failed` (409, unexpected) | Retry at most once per 5 min, on triggers | Next successful run |

## 10. Screens and status

### 10.1 Today (the main screen)

```
┌─────────────────────────────────┐
│ ‹  Thursday, November 26  ›   ● │  ← date title, prev/next day, sync light
│─────────────────────────────────│
│ # Thursday, November 26, 2026   │
│                                 │
│ ## Work                         │  ← same live styling, markers visible
│ - call Sam about **budget**     │
│                                 │
│                                 │
│─────────────────────────────────│
│ ⇥  ⇤  #  -  **  [ ]  ⌄          │  ← keyboard accessory bar
└─────────────────────────────────┘
  Toolbar: Library · Search · Calendar · Settings
```

- Launches straight into today's Daily Sticky with the keyboard **not** raised (reading is
  common); tap anywhere in the text to type.
- Swipe left/right on the title, or ‹ ›, moves by day. Tapping the title opens a date picker
  (graphical calendar). Days with a sticky show a dot.
- Crossing midnight while open follows `DailySession.handleActivation` (spec §7.7).
- New Day prompt (`dailyStartBehavior == .ask`): a small inline card with the same options
  and copy as the Mac.
- Notices use the same transient notice line under the header, with the same durations.

### 10.2 Editor

- `UITextView` subclass with TextKit 2, wrapped in `UIViewRepresentable`.
- Styling: the **same** `MarkdownSyntaxHighlighter`, made cross-platform (§12.3). Markers
  stay visible (spec §9.1–9.2).
- Auto-close pairs and list-marker continuation from `EditorEdits`, gated by the same
  settings.
- Accessory bar: Indent (⇥), Outdent (⇤), `#` (cycles heading level on the line), `-`
  (toggles a list marker), `**` (wraps selection or inserts a pair), `[ ]` (inserts a task
  marker), dismiss keyboard. Each is a plain text edit, undoable.
- Hardware keyboard on iPad: Tab / Shift-Tab indent, ⌘B / ⌘I wrap selection.
- Table of contents (`MarkdownOutline`) as a toolbar menu listing headings; tap to jump.
- Dynamic Type: the base font size follows the user's setting (`fontSize` default 17 on
  phone), heading ramp from `MarkdownStyle.headingSize`.

### 10.3 Library

- A `NavigationStack` browser over `library/` in the local folder, folders first, then files,
  alphabetical, with `INDEX.md` and `INBOX.md` pinned at the top of the root list.
- Files not yet downloaded appear dimmed with "Not downloaded yet." and download on tap
  (one blob request), then open.
- A note opens **read-only** in the same editor view with live styling. **Edit** in the
  toolbar makes it editable; **Done** returns to read-only. Edits autosave exactly like a
  Daily Sticky (`StickyDocument`).
- `-> library/…` paths written in a sticky are tappable while read-only and open that note.
- No create, rename, move, or delete in v1 (§15).

### 10.4 Status light and copy

- Same 8pt light at the trailing end of the header, same colors and states as sync v2 §8.1.
  Tapping opens a popover/sheet with the status line, "Last checked GitHub: …", "Last from
  <device>: …", **Sync Now**, and **Details…** (last error text).
- Copy is sync v2 §8.4 with the device noun parameterized: "only on this Mac" → "only on
  this iPhone" / "this iPad". `SyncStatusCopy` gains a `deviceNoun` parameter (§13).
- New lines for phone-only states:

| State | Line |
| --- | --- |
| auth failed | "Can't sign in to GitHub. Replace the token in Settings." |
| rate limited | "GitHub asked PeteKM to slow down. Syncing again at 14:30." |
| first download | "Downloading Library… 312 of 1,040." |

- Notices: "Updated from Pete's Work MacBook." (4s) when a run brought changes in; the
  union and conflict-copy notices in §8.3–8.4.

### 10.5 Search

- A search screen using the shared `SearchIndex` + `SearchQuery` (full text) and
  `FuzzyMatch` (filenames), over the local folder.
- Results show file title and the matching line; tapping opens the file at the hit
  (`revealRange`). Empty result: "Nothing found."
- Not-yet-downloaded files are not searchable; the screen says "Searching downloaded notes
  only — Library still downloading." while §9.3 runs.

### 10.6 Settings

- **GitHub**: repository (`owner/name`), branch, token status ("Connected as pete"),
  **Replace Token…**, **Disconnect** (§11.3).
- **Device name**: text field, default "iPhone"/"iPad", used in the commit trailer.
- **Daily Sticky**: start behavior, default headers, show date heading (same keys and copy as
  the Mac's `AppSettings`).
- **Editor**: font size, auto-close pairs, continue list markers.
- **Sync**: status lines, Sync Now, Details.
- **About**: version, a short "How the iPhone syncs" paragraph (§10.7).

### 10.7 Guide copy ("How the iPhone syncs")

> PeteKM on this iPhone keeps a copy of your Daily Stickies and Library notes. It brings in
> changes when you open it and sends yours a few seconds after you stop typing, or when you
> leave the app.
>
> If you wrote in the same day's Daily Sticky on a Mac and here, PeteKM keeps both sets of
> lines. If you edited the same Library note in both places, PeteKM keeps both versions as
> two files.
>
> Images, PDFs, and agent files stay on GitHub and aren't shown here.

## 11. Connecting

### 11.1 Flow

1. **Welcome**: the pixel mark, "PeteKM on iPhone keeps your Daily Sticky and Library in step
   with your Macs through GitHub." **Connect GitHub**.
2. **Repository**: one field, `owner/name`, prefilled hint `pete/notes`.
3. **Token**: a short how-to with a link to `https://github.com/settings/personal-access-tokens/new`:
   - Repository access: **Only select repositories** → this repository.
   - Permissions: **Contents: Read and write** (Metadata: read-only is added automatically).
   - Expiration: the longest offered.
   Paste field, **Connect**.
4. Validation: `GET /repos/{o}/{r}`. Requires `permissions.push == true`. Reads
   `default_branch`. Checks the tree for `daily/` or `library/`; if neither exists:
   "This repository doesn't look like a PeteKM folder. Set it up on your Mac first."
5. **Device name** (prefilled), **Daily start behavior** (same options as the Mac).
6. Land in today's Daily Sticky; the first download runs (§9.3).

Errors are plain and specific: "That token can't see this repository.", "That token can
read but not write. Give it Contents: Read and write.", "No internet connection."

### 11.2 Token storage

- Keychain generic password, service `com.petekm.PeteKM.ios.github`, account `owner/repo`.
- `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`, so background refresh can read it and
  it never leaves the device in a backup.
- Never logged, never shown after entry, never sent anywhere except `api.github.com`.

### 11.3 Disconnect

"Disconnect" removes the token and asks:

> **Remove notes from this iPhone?**
> Notes that haven't reached GitHub yet will be lost.
> [Keep Notes] [Remove]

When unsynced local changes exist, the alert says how many files and offers **Sync Now**
first. **Remove** deletes the local folder, manifest, and index cache.

## 12. Code organization

### 12.1 Targets

| Target | Platform | Holds |
| --- | --- | --- |
| `PeteKM` | macOS | Mac app, unchanged role |
| `PeteKMiOS` | iOS 26+, iPhone + iPad | iOS app (product name "PeteKM", bundle `com.petekm.PeteKM.ios`) |
| `PeteKMTests` | macOS | Existing tests + all shared/sync-engine tests (runs `git` for parity tests) |
| `PeteKMiOSTests` | iOS simulator | iOS-only glue: Keychain store, text view behaviors |
| `PeteKMUITests` | macOS | Unchanged |

Same build settings as the Mac target: `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`,
`SWIFT_APPROACHABLE_CONCURRENCY = YES`.

### 12.2 `Shared/` (compiled into both apps and `PeteKMTests`)

A new file-system-synchronized folder `Shared/`, member of `PeteKM`, `PeteKMiOS`, and the
test target. Files move there unchanged where possible:

- Folder & files: `PeteKMFolder`, `FileWriting`, `DirectoryWatcher`.
- Daily: `DailyDate`, `DailyFiles`, `DailySession`, `StickyDocument`, `NewDayComposer`,
  `MarkdownHeadings`, `NoticeBoard`.
- Editor model: `MarkdownSyntaxHighlighter` (made cross-platform), `EditorEdits`,
  `MarkdownOutline`, `CursorMemory`.
- Search: `SearchIndex`, `SearchQuery`, `FuzzyMatch`.
- Sync copy: `SyncStatus` (moved out of `AutoSync.swift`), `SyncStatusCopy`.
- New sync core: `MirrorScope`, `GitBlobHash`, `SyncManifest`, `LineDiff`, `UnionMerge`,
  `MergePlanner`, `GitHubAPI` (protocol + `URLSessionGitHubAPI`), `PhoneSyncEngine`.
  These are Foundation-only, so the macOS test target covers them.

Seams introduced so `DailySession` is shared. Each is **source-compatible on the Mac**:
every existing call site and test compiles unchanged and behaves the same.

- `protocol NewDaySyncing: AnyObject` with `canDeferNewDay(in:) -> Bool`,
  `requestNewDay() async -> Bool` (true = the run brought changes in), and
  `var newDayBudget: Duration { get }`. `AutoSync` and the iOS coordinator conform.
  `DailySession`'s init keeps the parameter label `autoSync:` (type
  `(any NewDaySyncing)?`) and keeps `newDayBudget:` as an optional override, so
  `DailyStickyTests`' existing calls compile as written. When no override is passed, the
  budget comes from the syncer (Mac: `AutoSync.Timing.newDayBudget`, unchanged 2s).
- `protocol DailyPreferences` with `dailyStartBehavior`, `defaultHeaders`,
  `showDateHeading`. `AppSettings` (Mac) and `PhoneSettings` (iOS) conform. The
  `DailyStartBehavior` enum moves to `Shared/` with the same name and raw values, so
  stored `UserDefaults` values read back identically.
- `DailySession` gains an optional `canPrune: (URL) -> Bool` hook, default `{ _ in true }`.
  The Mac never passes it, so `pruneIfBlank` is unchanged there. The phone passes "not in
  the manifest" (§8.8).

### 12.3 Cross-platform highlighter

- `typealias PlatformFont = NSFont | UIFont`, `PlatformColor = NSColor | UIColor` behind
  `#if canImport(AppKit)` / `#if canImport(UIKit)`.
- Trait conversion goes through a small `PlatformFont.adding(trait:)` helper. **On macOS it
  calls `NSFontManager.shared.convert(_:toHaveTrait:)` exactly as today**; only the iOS
  branch uses font descriptors. Font fallback for a missing family is unchanged.
- Label colors map to `.labelColor` / `.label` and friends. On macOS the typealiases are
  `NSFont`/`NSColor`, so `AppSettings.textColor` and `MarkdownStyle` keep their exact types.
- Mac rendering must be identical before and after: existing `EditorTests` pass unchanged,
  plus a new test that compares the full attribute runs of a fixture sticky against a
  snapshot taken before the change.

### 12.4 iOS-only (`PeteKMiOS/`)

`PhoneApp` (entry, `scenePhase`, background task registration), `PhoneServices`,
`PhoneSettings`, `PhoneSync` (coordinator: triggers, coalescing, back-off, status,
`NewDaySyncing`), `KeychainTokenStore`, `ConnectFlow` views, `TodayView`, `PhoneEditor`
(`UITextView` + representable + accessory bar), `LibraryBrowser`, `SearchView`,
`StatusLight`, `SettingsView`.

## 13. The Mac app: what must not break, and the one fix it needs

The Mac app is the primary product. The iOS work must leave it behaving exactly as it does
in 1.1.1, with one exception (§13.2), which is a fix the phone makes necessary.

### 13.1 Invariants (normative)

1. **Same build output.** The `PeteKM` scheme builds only the Mac target, with the same
   Sparkle linkage, entitlements, Info.plist, and bundle contents. `scripts/release.sh`
   runs unchanged. The iOS target gets its own scheme and its own version numbers.
2. **Same source surface.** Moved files keep their type names, method signatures, and
   defaults. Every existing test compiles and passes with no edits, except the test
   changes this spec lists by name.
3. **Same behavior.** No change to `GitSupport`'s run sequence, `AutoSync` triggers or
   timings, `StickyDocument` save/reconcile/conflict rules, `DailySession` New Day and
   prune rules, search, editor rendering, or any user-facing string, except §13.2 and §13.3.
4. **Same folder contract.** The phone never writes outside its mirror scope, never
   deletes, never changes modes, `.gitattributes`, `.gitignore`, or agent files (§8.8–8.9).
   A Mac pulling a phone commit sees only edited or added Markdown files in `daily/` and
   `library/` and the two root notes.

### 13.2 Required Mac fix: retry a push that lost a race (ships before the phone)

**Problem, present today.** `GitSupport` fetches, rebases, then pushes. If another device
pushes between the fetch and the push, GitHub rejects the push as non-fast-forward. The run
ends `.pushFailed`, so `AutoSync` turns the light red ("Can't send changes to GitHub. Try
Sync Now, or check your Git sign-in.") and stays local-only for 15 minutes. Nothing is
lost, but the message is false (sign-in is fine) and the notes sit unsent.

With two Macs this race is rare. A phone pushes about 15s after every pause in typing, so
the race becomes much likelier. That is a regression the phone would cause, so it gets
fixed first.

**Fix.** In step 7 of the v2 sequence, when the push fails **and** stderr shows a
non-fast-forward rejection (`[rejected]` with `(fetch first)` or `(non-fast-forward)`), do
**one** more fetch → rebase (same guards, marker, union attribute, and reconcile as step 6)
→ push. Only if that second push also fails does the run end `.pushFailed`. Any other push
failure (auth, network, permissions) keeps today's behavior exactly.

- This changes no notice, no timing, and no outcome for every case that fails today for a
  real reason.
- Tests (`GitSyncTests`): a third clone pushes between the Mac's fetch and push (inject via
  the runner) → the run ends `.synced`, all commits present, no force; a rejected push
  for an auth reason still ends `.pushFailed` with no retry; the retry respects the
  sleep/quit deadline (no second network step once the deadline has passed).

### 13.3 Optional Mac copy changes (only with explicit go-ahead)

Two strings say "Macs". Once a phone exists they are slightly wrong. Changing them is
cosmetic, so it is a separate, opt-in change at the end of the iOS work (plan Phase 7),
with the matching test expectations updated in the same commit:

| Where | Today | After |
| --- | --- | --- |
| Union notice (sync v2 §7.3) | "Merged today's Daily Sticky from both Macs. Check the order." | "Merged today's Daily Sticky from two devices. Check the order." |
| Paused line (§8.4) | "Sync paused — the same note changed on two Macs. Nothing was lost." | "Sync paused — the same note changed on two devices. Nothing was lost." |
| Guide "Using two Macs" | — | One added paragraph: "PeteKM on iPhone uses the same GitHub repository. Set it up from the iPhone app." |

Status lines keep "only on this Mac" (`deviceNoun` defaults to `"Mac"`).

### 13.4 Known effects on the Mac that need no code change

| Effect | Why it's acceptable |
| --- | --- |
| "Updated from Pete's iPhone." appears on the Mac. | Reads the phone's trailer, as designed for any device. |
| "Last from <device>" shows the most recent other device, which may be the phone instead of the other Mac (sync v2 §9.3: "show only the most recent one"). | Still an accurate fact. A per-device list is a possible later Mac change, not part of this work. |
| Same Library note edited on the phone and a Mac, **Mac syncs second** → Mac pauses with today's conflict notice. | Existing Mac behavior, unchanged. The phone syncs within seconds of each edit, which makes it rare. |
| More commits in history (one per phone typing pause). | Sync v2 §12 already decided commit count doesn't matter. |
| `otherDeviceLastCommit` scans 100 commits; heavy phone use can push the other Mac's last commit past that, hiding its line. | Line is omitted, never wrong. Acceptable for v1. |

## 14. Tests

**Shared, in `PeteKMTests` (Swift Testing, macOS):**

- `GitBlobHash` equals `git hash-object` for empty, ASCII, UTF-8, CRLF, and binary inputs.
- `MirrorScope`: included/excluded paths, dot components, size limit, modes.
- `LineDiff` + `UnionMerge`: one-sided edits; both sides append; same-line edits; add/add
  with empty base; trailing newline present/absent; CRLF. **Parity:** for a fixture set,
  compare against `git merge-file --union -p local base remote` (with the documented side
  order) and assert equal; the no-lost-line property is asserted on randomized inputs.
- `MergePlanner`: every row of §8.2, plus manifest-lost recovery (§8.6).
- `PhoneSyncEngine` against an in-memory fake GitHub (`FakeGitHub`) with real fast-forward
  semantics: clean, local-only, remote-only, both, 422-then-retry, crash between push and
  manifest save (§6.3), crash mid-apply, rate limit, 401, offline, truncated tree.
- **Mac ↔ phone end-to-end:** `LocalGitHub` implements `GitHubAPI` on a local bare repo
  using git plumbing (`cat-file`, `hash-object -w`, `mktree`, `commit-tree`,
  `update-ref <ref> <new> <old>`). A Mac clone runs the real `GitSupport` sync against the
  same bare repo. Scenarios: phone writes → Mac pulls; Mac writes → phone pulls; both write
  the same day offline → both converge, no line lost, on both sides; both edit the same
  Library note → phone makes a conflict copy, Mac converges without pausing; Mac's
  `DailyFiles.organize` rename → phone follows.
- `DailySession` with a fake `NewDaySyncing`: existing Pre-New-Day tests pass through the
  protocol.

**iOS, in `PeteKMiOSTests`:** Keychain round-trip; accessory bar edits; selection preserved
across a silent reload.

**Manual checklist:** see `context/ios/plan.md`.

## 15. Out of scope (v1)

- Creating, renaming, moving, or deleting Library notes on the phone.
- Images/PDFs/attachments, and rendering images referenced from Markdown.
- Scratch, agents, `/petekm-*` skills, Review Inbox flows.
- Widgets, Share Sheet "add to today", App Intents / Shortcuts, Lock Screen capture. Good
  candidates for v2; the engine already supports them.
- OAuth device flow sign-in (v2 option; replaces the token paste without changing sync).
- Self-hosted GitHub Enterprise; GitLab; non-GitHub remotes.
- Real-time collaboration; push notifications.
- App Store release. Distribution is Xcode install and TestFlight (§16).

## 16. Distribution

- Same Apple Developer team as the Mac app.
- Personal use: run from Xcode on the device, or TestFlight internal testing (up to 100
  internal testers, builds last 90 days).
- `context/DISTRIBUTION.md` gains an iOS section: archive, upload, TestFlight.
