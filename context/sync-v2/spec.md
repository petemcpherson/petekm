# Sync v2 Specification: Automatic Sync Across Devices

**Status:** Draft for implementation. Written 2026-10-05.

**Supersedes** these parts of `context/sync/spec.md` (v1):
- §4.2's rule "No automatic full Sync ever runs unattended". The user reversed this decision on 2026-10-05.
- §4.3 (once-per-process launch check plus banner). It is replaced by arrival triggers (§5.1) and the status indicator (§8).
- §6 rule 1 ("Commit before any network operation") is reworded. §6 rule 3 ("Never resolve a conflict automatically") gains one narrow exception for `daily/` (§7).
- §8's "No background retry timer" and §9's touch-point table.

**Keeps from v1 unchanged:**
- §3: the agent-side `/petekm-process` git steps.
- §5: the conflict core (commit first, abort on conflict, never force-push).
- §5.3: the `SyncOutcome` notices for **manual** Sync.
- §7: setting a remote, and the rule that PeteKM manages no auth.

---

## 1. Problem

Pete writes on two Macs, a personal laptop and a work laptop. The PeteKM folder on each is a clone of one GitHub repository. GitHub is the only shared storage, and that stays true.

Today the app does almost nothing automatically:

- Sync (commit → fetch → pull --rebase → push) runs only when clicked.
- The launch check fetches **once per app process**. PeteKM stays running in the background and hides instead of quitting, so a process can live for days. Wake the other laptop after a weekend and the check is stale or long gone. No banner appears, and Pete types into an out-of-date Library and Daily Sticky.
- `DailySession.create` writes today's file **the moment the window opens**. If laptop A already pushed today's sticky, laptop B creates its own competing copy before any pull. The next Sync then hits a guaranteed conflict on the most-edited file in the system.

## 2. Goal

Moving between Macs should need no thought. Open the lid, summon PeteKM, and the notes are current. Close the lid or hide the window, and the notes reach GitHub. Sync is something the user sees only when something needs them.

Measured outcome: the "Changes to sync." banner and manual Sync become rare. Manual Sync stays as an override and never becomes a required step.

## 3. Principles (normative)

1. **One engine, many triggers.** Every automatic run calls the same sync routine as the manual Sync button. Triggers decide *when*; they never change *what* happens.
2. **Capture never blocks** (main spec §17.4). No trigger may delay opening, typing into, or saving a Daily Sticky by more than the bounded wait in §6. Most add no delay at all.
3. **Quiet when fine, visible when not.** A successful automatic run shows nothing, except one short line when it brought in changes from the other Mac (§8.3). Offline is normal for a laptop and is never an error.
4. **No data loss, ever.** All v1 integrity rules hold, with the single amendment in §7.
5. **Be honest about physics.** A Mac cannot see work that another Mac never pushed. PeteKM must not imply otherwise (§9).

## 4. The setting

**Settings → Folder → Git → "Sync automatically"** (toggle).

- New key: `petekm.syncAutomatically`, `Bool`, default **on**.
- Caption: "Keeps this Mac and GitHub in step: brings in changes when you open PeteKM and sends yours when you step away."
- The toggle is shown only when the folder is a Git repository with a remote. With no repository or no remote, automatic sync is inert, and the existing Initialize Repository / Set Remote rows explain what's missing.
- **Off** restores v1 exactly: the launch check, the "Changes to sync." banner, and manual Sync only. `SyncLaunchCheck` survives for this path.

## 5. Triggers

Every trigger asks the coordinator (§10.1) for a run. The coordinator coalesces, so a trigger that fires during a run sets a "run again" flag and does not start a second run. At most one run is ever in flight.

### 5.1 Arrival triggers: bring changes in

| Trigger | Source | Condition |
| --- | --- | --- |
| Folder becomes ready | `FolderStore.State` → `.ready` (launch, recovery, new folder) | Always |
| System wake | `NSWorkspace.didWakeNotification` | Always. Wait until the network path is satisfied, up to 20s, then run |
| Window summoned | `.peteKMDidSummon` | Only if the last **successful fetch** is older than 5 min |
| Network regained | `NWPathMonitor` status goes from unsatisfied to satisfied | Always |
| Presence poll | Timer, **only while the sticky window is visible** | Every 5 min |

The presence poll exists so that two Macs open side by side converge without anyone touching them. While the window is hidden there is no polling. The summon trigger covers that case on return.

### 5.2 Departure triggers: send changes out

A departure trigger runs only when **local changes exist**: the working tree is dirty, or the branch is ahead of upstream. Without local changes it does nothing, so hide/summon cycles stay free.

| Trigger | Source | Notes |
| --- | --- | --- |
| Window hidden | New `.peteKMDidHide` posted from `StickyWindowController.hide()` and from `windowShouldClose` | 2s debounce, so a quick hide/summon flicker does not run twice |
| Editing idle | No keystroke in any editor (sticky or Library file) for **60s** while the window is visible | Main protection for "wrote notes, walked to the other Mac without hiding the window" |
| System will sleep | `NSWorkspace.willSleepNotification` | Best effort, see §5.3 |
| App quit | `applicationShouldTerminate` | See §9.2 |

Edits made only in Scratch never trigger anything. Scratch is gitignored and never syncs (map Layer 3b).

### 5.3 Sleep is best effort

macOS gives a sleeping app only a few seconds. On `willSleep`:

1. Flush the open document and commit locally. This is local and takes milliseconds, and it always completes.
2. Attempt fetch/rebase/push with a hard 5s budget. If it doesn't finish, kill the git process. A killed fetch or push leaves the repository consistent. A killed rebase must be followed by `git rebase --abort` on the next run (§6.4).

How the budget applies (a deadline, not a blanket cap):

- **Network steps** (`fetch`, `push`) get `min(30s, time left)`. Once the deadline has passed they are not started, and the run ends as `.offline`.
- **Local steps** get `min(15s, max(time left, 1s))`. The 1s floor means step 1 always completes, even when the budget is already spent. Without it, an expired deadline would make every local command fail and misreport the folder as having no git or no remote.
- **`git rebase --abort`** after a failed rebase ignores the deadline. Leaving a rebase half-done is worse than a slightly late sleep. If the abort itself fails, the marker stays, and the next run's guard finishes the job.
3. The wake trigger (§5.1) retries on the next open. Nothing depends on step 2 succeeding.

### 5.4 Pre-New-Day trigger

See §6.5. This is the trigger that prevents the guaranteed conflict from §1.

### 5.5 Manual Sync

Palette → Sync, Settings → Sync, and the new "Sync Now" menu item (§8.2) call the same engine. Manual runs differ in exactly two ways:

- They always show the v1 `SyncOutcome` notice, including "Synced." and "Already up to date."
- They ignore the back-off rules in §6.6.

A manual run never ends in silence. When the guard (§6.4) skips a manual run, it shows:

| Outcome | Manual notice |
| --- | --- |
| `.busy` (another tool holds the folder right now) | "Another Git tool is using this folder. Try Sync again in a moment." |
| `.stuck` (the same, for over 10 min) | "Sync is stuck — another Git tool is mid-operation in this folder." (§8.4 line) |

Automatic runs stay silent on both.

## 6. The run

### 6.1 Sequence

Network work happens first. Working-tree changes are then squeezed into the shortest possible window, so a person typing during a run almost never collides with it.

```
0. Guard (§6.4). If git is busy or the repo is mid-operation, skip silently and retry on the next trigger.
1. [main actor] Flush: StickyDocument.saveNow() on the open document.
2. git add -A; if `git status --porcelain` is non-empty → git commit (message §6.3).
3. git fetch                         ← network; slow; never touches the working tree
4. If no remote → .noRemote.  If fetch failed → .offline.
5. ahead/behind = rev-list --left-right --count HEAD...@{upstream}
6. If behind > 0:
     a. [main actor] Flush again; add -A; commit again if dirty.   ← catches typing during step 3
     b. git rebase --autostash @{upstream}     ← local only, fast, no network
        On failure → git rebase --abort → .pullConflict (§7 makes this rare for daily/).
     c. [main actor] Reconcile the open document with disk immediately (§6.2).
7. If ahead > 0 (recomputed after step 6) → git push (with --set-upstream the first time, as in v1).
     Failure → .pushFailed.
8. Return outcome; update SyncStatus (§8.1).
```

Changes from v1's `GitSupport.sync`:

- `pull --rebase` becomes `fetch` + `rebase @{upstream}`. The fetch already happened, so a second network round trip is wasted. Splitting them makes step 6 purely local, so it finishes in milliseconds.
- There is a second flush-and-commit (6a) just before the rebase.
- The push runs only when ahead. v1 also pushed when even, which was a harmless no-op.

### 6.2 The open document during a run

`StickyDocument.reconcileWithDisk()` already reloads silently when the document is clean and raises the Keep Mine / Keep Disk / Keep Both alert when it is dirty (§8.5, §19.4). Sync v2 relies on that unchanged. It shrinks the window where the alert can fire:

- Step 6a flushes on the main actor, steps 6b–6c run back to back, and 6b is local. The gap between "last flush" and "reconcile" is the duration of a local rebase, normally well under 100ms.
- If the user types inside that gap and the rebase changed the open file, the existing conflict alert appears. That is the correct, already-built fallback, and no new conflict UI is designed.
- The engine also posts the same reconcile to any Library file open in the editor (`DailySession.document` covers both, since Library files open in the same editor).

### 6.3 Commit message and device name

`PeteKM backup 2026-10-05 14:02` stays the subject. Add a trailer naming the Mac:

```
PeteKM backup 2026-10-05 14:02

PeteKM-Device: Pete's Work MacBook
```

- The device name comes from `Host.current().localizedName` (the Sharing pane's Computer Name), read once per process.
- Write the trailer with `git commit -m <subject> --trailer "PeteKM-Device: <name>"`. This needs git ≥ 2.32; Apple's bundled git is newer. If `--trailer` fails, retry without it, so a commit is never lost to a formatting feature.
- §9.3 uses the trailer to say which Mac sent the latest changes and when.

### 6.4 Guards: coexisting with the agent and other tools

Claude Code, `/petekm-process`, and VS Code's git integration share the repository. Before step 1, and again before step 6b, skip the run (outcome `.busy`, silent, retried on the next trigger) if any of these exist in `.git/`:

- `index.lock`
- `rebase-merge/` or `rebase-apply/`
- `MERGE_HEAD` or `CHERRY_PICK_HEAD`

**Never delete a lock file.** If a lock is older than 10 min, show the status as "Sync is stuck" (§8.1). The user, their agent, or VS Code resolves it.

One exception: if `rebase-merge/` exists **and was left by PeteKM itself**, run `git rebase --abort` and continue. PeteKM marks this by writing `.git/petekm-rebase` before step 6b and removing it after. This only happens when a sleep (§5.3) or a crash killed PeteKM's own rebase. Leaving the user stranded mid-rebase would break v1 rule 4.

### 6.5 Pre-New-Day: never create today's file blind

Today `DailySession.open(date:)` → `create` writes the file immediately. The new rule applies when **all** of these hold:

- Automatic sync is on.
- The folder has an upstream.
- The opened date is today.
- Today's file does not exist on disk.

When they hold:

1. Compose the opening text as today, show it in the editor at once, and put the cursor in place. Capture is not delayed.
2. **Defer the file write.** Run an arrival sync now with a **2s budget**.
3. The deferral ends at the first of three events:
   - **The sync brings in today's file.** If the user hasn't typed, adopt the disk file and discard the composed text. Nothing was written, so nothing is lost.
   - **The user types.** Write the composed text plus the keystrokes immediately (normal autosave). Any later collision with the other Mac's copy is handled by §7.
   - **2s passes, offline, or failure.** Write the composed text as today.
4. With `dailyStartBehavior == .ask`, the New Day prompt is already a natural wait. Start the sync when the prompt appears. When the user answers, use the fresh state. If today's file arrived meanwhile, skip the prompt and open the file.

Carry-forward (`.carryForwardHeaders`) reads the most recent prior sticky. Running the sync first also means carry-forward reads the other Mac's yesterday, not a stale one. This is a real correctness gain, not only conflict avoidance.

`pruneIfBlank` is unchanged. A deferred, never-written blank sticky simply never reaches disk.

### 6.6 Back-off

| Situation | Automatic behavior | Clears when |
| --- | --- | --- |
| `.offline` | Keep committing locally on departure triggers. No network attempts until `NWPathMonitor` reports satisfied, or a summon/wake trigger fires. | Next successful fetch |
| `.pushFailed` (auth, permissions, rejected) | Retry at most once per 15 min, and only on triggers | Next successful push |
| `.pullConflict` (paused) | Departure triggers still commit locally. **No automatic rebase attempts.** Fetch still runs so status stays accurate. While still behind, no push either: GitHub would reject it, so the run ends `.pullConflict` again. Once not behind (someone resolved it), the run pushes normally. | Local `HEAD` or `@{upstream}` changes, meaning someone resolved it or new commits arrived. Then retry once. |
| `.busy` | Silent | Next trigger |
| `.gitUnavailable` / `.notARepository` / `.noRemote` | Automatic sync inert; toggle hidden (§4) | Settings change |

Manual Sync ignores back-off and always tries the full sequence.

### 6.7 Process hardening (needed before anything runs unattended)

`GitSupport.run` today has no timeout and inherits whatever environment the app has. An unattended run that hangs on a credential prompt would block every later run forever. Before automatic sync ships:

- **Environment** for every git invocation:
  - `GIT_TERMINAL_PROMPT=0`: fail instead of prompting for a username or password.
  - `GIT_SSH_COMMAND="ssh -o BatchMode=yes -o ConnectTimeout=10"`: fail instead of prompting for a passphrase or host key.
  - Keep `HOME` and `PATH` so the user's credential helper (osxkeychain, `gh`) and SSH agent still work.
- **Timeout** per invocation: 30s for `fetch`/`push`, 15s for everything else, 5s total in the sleep path. On timeout, terminate the process and return failure. A timed-out fetch maps to `.offline` and a timed-out push to `.pushFailed`.
- **Read stderr** instead of discarding it, kept in memory for the last run only, for the "Details" affordance in §8.2. It is never written to disk or shown unprompted.
- **Run off the main actor**, as today. Only the flush (steps 1, 6a) and the reconcile (6c) hop to the main actor.

## 7. Daily Stickies merge by union

### 7.1 Why

Pete's own scenario (§9) ends with the same day's sticky edited on both Macs. Pre-New-Day (§6.5) avoids this when both Macs are online. It cannot avoid it when one Mac wrote offline, or wrote and closed the lid before the push finished. Under v1 rules that is a `pullConflict`, which pauses sync and sends the user to a terminal over a file that is almost always "two lists of lines, keep both."

### 7.2 Rule

The app writes this line to `.gitattributes` in the PeteKM folder:

```
daily/*.md merge=union
```

`union` is a **built-in** git merge driver, so no `git config` is needed and it travels with the repository to every clone. Per the git docs it runs a 3-way merge but, where the two sides conflict, it keeps **lines from both versions** instead of writing conflict markers. It applies to the 3-way merges that `git rebase` performs, so step 6b uses it automatically. The agent-side `/petekm-process` pull gets the same behavior for free.

### 7.3 What the user sees

When both Macs added lines to the same day, the merged sticky contains both sets of lines. Within a conflicting region, the upstream (other Mac's) lines come first, then this Mac's lines. Lines outside conflicting regions merge normally. Duplicated headings are possible when both Macs started the day independently.

Nothing is dropped. The worst case is a sticky that needs a few seconds of tidying. To make that visible, when a run merged a `daily/` file that had changes on both sides, show the notice: **"Merged today's Daily Sticky from both Macs. Check the order."** (6s). Detect it by comparing the paths touched by the local and the upstream commits before the rebase (`git diff --name-only <merge-base> HEAD` vs `… @{upstream}`) and intersecting the `daily/` paths.

### 7.4 Amendment to v1 §6 rule 3

> **Never resolve a conflict automatically**, with one exception: `daily/*.md` merges by line union. Union never chooses a side and never removes a line. It only decides order. All other paths, including all of `library/`, `INDEX.md`, `INBOX.md`, and the agent files, keep v1 behavior: abort, restore, pause, ask.

The `daily/` immutability rule (AI never writes `daily/`) is untouched. Union is git combining two human-written versions; no agent is involved.

### 7.5 Shipping the attribute

- Add `PeteKMFolder.gitattributes` and an `AgentTemplates.gitattributes` template containing the line above plus a one-line comment.
- Add `FolderInitializer.ensureDailyUnionMerge(_:)`, modeled exactly on `ensureScratchIgnored`. It appends the line if missing, never replaces user content, and runs on window open. Existing folders are repaired without a prompt.
- The file is **tracked** (not gitignored), so the next sync carries it to the other Mac. Until the other Mac also has it, a conflict there still pauses safely. Rollout is self-healing.
- A rebase reads attributes from the files it checks out, which are the remote's. So before every rebase the engine also writes the line to the repository-local `.git/info/attributes` (never committed, applies whatever is checked out). Without it, the first v2 sync on a Mac conflicts on same-day stickies until `.gitattributes` has reached the remote. A Mac still on v1 has neither, and still pauses safely.
- Update the generated folder shape lists in `context/map.md` and spec §5, and mention `.gitattributes` in `CLAUDE.md`/`AGENTS.md` templates as "not yours to edit."

## 8. Status and visibility

### 8.1 `SyncStatus`

One observable value, owned by the coordinator:

| State | Meaning | Window light |
| --- | --- | --- |
| `.off` | Toggle off, or no repo/remote | None |
| `.synced(at:)` | Last run succeeded; tree clean; even with upstream | Green |
| `.syncing` | A run is in flight | Keeps the previous color and pulses (grey before the first result) |
| `.pending(since:)` | Local changes not on GitHub yet | Yellow, from the first keystroke |
| `.offline(since:)` | Last fetch failed for network reasons | Grey |
| `.paused` | `pullConflict` back-off | Red |
| `.failing` | `pushFailed` back-off, or a stuck lock | Red |

**Revised 2026-10-06.** The first build hid the light whenever sync was working. In use that meant the user never saw it and had no way to tell that notes reached GitHub or that updates came in. The light is now always on while automatic sync is on, so a working sync is as visible as a broken one.

**The 2-minute rule** now applies only to the menu-bar badge. Pending for less than 2 min is the normal state between typing and the next departure trigger. After 2 min it means something didn't go out, and the user should know before they walk away.

### 8.2 Where it shows

**Window: one small light.** An 8pt circle at the trailing end of the sticky header, colored as in §8.1. A run pulses it for at least 1.2s, so even a fast run is visible. Hovering for 0.3s shows a card with the status line (§8.4), when GitHub was last checked for updates, and the newest change from another Mac. Problems are shown in red text. Click opens a small popover with the same lines plus actions:

```
Not synced yet — changes from 14:02 are only on this Mac.
Last checked GitHub for updates: today 14:01.
Last from Pete's Personal MacBook: today 09:15.

[Sync Now]        Details…
```

"Details…" reveals the last run's stderr in a selectable monospaced text box, for the rare case it is needed. It is the only place git output ever appears.

**Menu-bar item.**
- A disabled status row at the top of the menu, using the §8.4 copy, plus a **Sync Now** item. Hide both when status is `.off`.
- The glyph gains a small badge dot when the user should act: paused or failing at once, and pending (or offline with pending) after 2 min. The pixel mark is a template image, so add a second template asset `PixelMarkBadge` and swap the image.
- If the user has hidden the menu-bar item (§8.8), the window dot is the only indicator, which is enough.

**Settings → Folder → Git.** The same status lines under the toggle.

**Problems repeat.** While paused or failing, each summon of the window shows the status line again in the notice line (8s), until the problem clears.

The v1 "Changes to sync." banner is **not shown** while automatic sync is on. The dot replaces it.

### 8.3 Notices (the existing transient notice line)

| When | Notice | Duration |
| --- | --- | --- |
| Automatic run brought in changes from the other Mac | "Updated from Pete's Personal MacBook." | 4s |
| Automatic run merged a `daily/` file by union (§7.3) | "Merged today's Daily Sticky from both Macs. Check the order." | 6s |
| Automatic run hit `pullConflict` (once per conflict, not per retry) | v1 `pullConflict` notice, unchanged | 15s |
| Wake/launch arrival found this Mac's own changes still unpushed from before (§9.2) | "Notes from earlier on this Mac haven't reached GitHub yet." | 8s |
| Any other automatic outcome | Nothing | — |
| Manual Sync | v1 `SyncOutcome.notice`, unchanged | as v1 |

"Updated from …" uses the device trailer from the newest incoming commit. If that commit has no trailer (agent-made, or made before v2), the notice is "Updated from GitHub."

### 8.4 Status-line copy

The copy is terse and plain, with no git words (DESIGN §2, §39). Times are relative under an hour ("2 min ago"), clock times today ("14:02"), and dates beyond today.

| State | Line |
| --- | --- |
| synced | "Synced 2 min ago." |
| syncing | "Syncing…" |
| pending | "Not synced yet — changes from 14:02 are only on this Mac." |
| offline + pending | "Offline — changes from 14:02 are only on this Mac." |
| offline, nothing pending | "Offline. Nothing waiting to sync." |
| paused | "Sync paused — the same note changed on two Macs. Nothing was lost." |
| failing (push) | "Can't send changes to GitHub. Try Sync Now, or check your Git sign-in." |
| failing (lock) | "Sync is stuck — another Git tool is mid-operation in this folder." |

A second line appears in the popover and Settings only, when known: **"Last from <other Mac>: <time>."** (§9.3).

## 9. Unsynced work on another Mac: the honest answer

### 9.1 The scenario

> I take some notes on the Daily Sticky on Mac A, immediately switch to Mac B and open PeteKM.

**Case 1: Mac A was online and Pete hid the window, closed the lid, or simply stopped typing for 60s.** The departure triggers pushed within seconds. Mac B's arrival trigger (launch, wake, or summon) pulls it. If Mac B had not yet created today's file, §6.5 adopts Mac A's version. Pete sees "Updated from Mac A." and nothing else. **This is the common case, and it needs no warning because nothing is wrong.**

**Case 2: Mac A did not get the push out.** Mac A was offline, the lid closed mid-push, or Pete switched within 60s without hiding the window.

**Mac B cannot know about this.** The unpushed notes exist only on Mac A's disk. GitHub has never seen them, and Mac B can only ask GitHub. Any app that claims to warn you on Mac B about something Mac A never published is guessing. PeteKM doesn't guess. Instead it does three honest things.

### 9.2 What Mac A does (the side that *can* know)

1. **Before you leave.** The window dot appears once changes are pending for 2 min, and the menu-bar badge too. If you look at either before walking away, you know.
2. **When you quit with the mouse.** Run the departure sync with a 5s budget (`.terminateLater`). If changes are still not on GitHub, show one alert:
   > **Some notes haven't reached GitHub yet.**
   > They're safe on this Mac and will sync the next time PeteKM is open and online.
   >
   > [Quit Anyway] [Cancel]

   Show the alert only for a user-initiated Quit. Logout, shutdown, restart, and Sparkle relaunch get the best-effort sync and no alert. Detect these by the `kAEQuitApplication` event's `keyAEQuitReason`, or by Sparkle's own will-relaunch callback. Keyboard ⌘Q already hides instead of quitting, so it is a departure trigger, not a quit.
3. **When Mac A next wakes or launches.** The arrival run pushes the backlog (rebasing onto Mac B's work if needed; `daily/` unions per §7). If, at the start of that run, local commits are older than the wake time, meaning they survived a sleep unpushed, show **"Notes from earlier on this Mac haven't reached GitHub yet."** while the run proceeds. That notice is replaced by "Synced" status, or by "Merged today's Daily Sticky from both Macs. Check the order.", when the run finishes.

### 9.3 What Mac B does (the side that *can't* know)

Mac B shows the one true fact it has: **when the other Mac last sent anything.**

- **"Last from Pete's Personal MacBook: today 09:15."** appears in the status popover, the menu row's tooltip, and Settings.
- **How to compute it.** From `git log -n 100 @{upstream} --format='%ct%x09%(trailers:key=PeteKM-Device,valueonly,separator=)'`, take the newest commit whose device differs from this Mac's.
- **Several other Macs.** Show only the most recent one. Two Macs is the design target; more work but get no extra UI.
- **No trailers yet.** If no commit carries a trailer, as with pre-v2 history, omit the line.

If Pete knows he wrote on Mac A at 11:00 and Mac B says "Last from Mac A: 09:15", he knows those notes haven't arrived. That is the warning: an accurate fact instead of a guess.

### 9.4 What Pete can do on Mac B, in plain terms

This goes in Settings → Guide as a short "Using two Macs" section, in the same words.

1. **Keep writing.** This is the default and it is safe. Nothing on either Mac will be overwritten. When Mac A next comes online, it sends its notes. If both Macs wrote in the same day's Daily Sticky, PeteKM keeps both sets of lines (§7) and says so.
2. **If you need those notes right now,** open Mac A's lid on a network. It sends them within a few seconds of waking. Then summon PeteKM on Mac B, or choose **Sync Now**.
3. **If you edited the same Library note on both Macs,** sync on whichever Mac comes second pauses and says so. Nothing is lost. Open a terminal in your PeteKM folder and ask PeteKM to help sort it out, or open the folder in VS Code (v1 §5.4, unchanged).

## 10. Implementation touch points

### 10.1 New: `PeteKM/Files/AutoSync.swift`

`@MainActor @Observable final class AutoSync`. Lives in `AppServices` beside `SyncLaunchCheck`. It owns:

- `status: SyncStatus` (§8.1), `lastFetchAt`, `lastRunStderr`, `otherDeviceLast: (name: String, at: Date)?`.
- `request(_ trigger: Trigger)`: the single entry point. It coalesces into one in-flight run plus a "run again" flag (§5), applies back-off (§6.6), and checks the departure precondition (local changes exist).
- Run execution: hops to `Task.detached(priority: .utility)` for git steps, back to the main actor for flush/reconcile (§6.1). It needs a weak handle to the active `DailySession` for flush/reconcile, registered by `DailyStickyView` on appear.
- Observers: `NWPathMonitor` (§5.1), the wake/sleep `NSWorkspace` notifications, `.peteKMDidSummon`, `.peteKMDidHide`, the presence timer (started and stopped with window visibility), and the editing-idle timer (reset by an `AutoSync.noteEdit()` call from the editor's text-change path).
- Reads `AppSettings.syncAutomatically`. Off means: tear down observers and timers, `status = .off`, and the view shows the v1 banner path.

### 10.2 Changes to existing files

| File | Change |
| --- | --- |
| `GitSupport.swift` | Timeouts + env + stderr capture in `run` (§6.7). Split `sync` into the v2 sequence (§6.1) with main-actor flush/reconcile callbacks injected as closures so the sequence stays testable. Add `.busy` and `.stuck` outcomes (no automatic notice; manual lines in §5.5). `busyReason(_:)` lock checks (§6.4). Device trailer in `commit` (§6.3). `otherDeviceLastCommit(_:thisDevice:)` (§9.3). `dailyPathsChangedOnBothSides(_:)` (§7.3). |
| `SyncLaunchCheck.swift` | Unchanged; used only when automatic sync is off. |
| `AppServices.swift` | Construct and hold `AutoSync`. |
| `AppDelegate.swift` | Wire wake/sleep observers into `AutoSync`. `applicationShouldTerminate`: run the quit departure sync and the §9.2 alert, preserving the existing keyboard-⌘Q-hides branch and the never-alert paths (logout, Sparkle). |
| `StickyWindowController.swift` | Post a new `.peteKMDidHide` from `hide()` and `windowShouldClose`. Expose visibility for the presence timer. |
| `DailySession.swift` | Deferred first write for today's sticky (§6.5): a pending-create state holding composed text, resolved by sync-arrival, first keystroke, or the 2s timeout. `.ask` path starts the sync when the prompt shows. |
| `StickyDocument.swift` | Support for an unwritten document whose first write is deferred, e.g. a `deferredCreate` flag that makes `scheduleSave`/`saveNow` create the file. `reconcileWithDisk` is unchanged. |
| `DailyStickyView.swift` | Register the session with `AutoSync`. Status dot + popover (§8.2). Route automatic-run notices (§8.3). Show the v1 banner only when automatic sync is off. |
| `MarkdownEditor.swift` / `MarkdownTextView.swift` | Call `AutoSync.noteEdit()` on text change, for sticky and Library documents only. Scratch must not call it. |
| `MenuBarController.swift` | Status row + Sync Now; badge glyph swap; `refresh()` on status change. |
| `AppSettings.swift` | `syncAutomatically` key, default `true`. |
| `FolderSettingsView.swift` | Toggle + caption + status line in `GitSettingsSection` (§4, §8.2). |
| `GuideSettingsView.swift` | "Using two Macs" section (§9.4). |
| `PeteKMFolder.swift` / `AgentTemplates.swift` / `FolderInitializer.swift` | `.gitattributes` path, template, and `ensureDailyUnionMerge` (§7.5). Agent templates mention `.gitattributes`. |
| `PaletteCommand.swift` | No new command. "Sync" stays the manual path. |
| `Assets.xcassets` | `PixelMarkBadge` template imageset. |

### 10.3 Constants (one place, `AutoSync.Timing`)

| Name | Value |
| --- | --- |
| `summonStaleness` | 5 min |
| `presencePoll` | 5 min |
| `editIdle` | 60s |
| `hideDebounce` | 2s |
| `pendingSignalAfter` | 2 min |
| `newDayBudget` | 2s |
| `wakeNetworkWait` | 20s |
| `sleepBudget` / `quitBudget` | 5s |
| `networkTimeout` / `localTimeout` | 30s / 15s |
| `pushFailedRetry` | 15 min |
| `staleLock` | 10 min |

## 11. Tests

**Unit tests (`PeteKMTests`, Swift Testing).** Use real temporary git repositories: a bare "GitHub" repo plus two clones standing in for Mac A and Mac B. These are local `file://` remotes, so no network is needed.

- Sequence: clean/ahead/behind/diverged paths produce the right outcomes; push runs only when ahead; the second flush-commit (6a) captures a write made after step 2.
- Union: both clones append to the same `daily/` file → rebase succeeds, every line from both sides is present, and the "merged daily" detector fires. Both clones edit the same `library/` line → `.pullConflict`, the tree is byte-identical to before, and no rebase is in progress.
- Add/add: both clones create today's sticky with different bodies → union keeps all lines.
- Guards: `index.lock` present → `.busy`, nothing touched. PeteKM-marked stale rebase → aborted and run continues. Unmarked rebase → `.busy`.
- Hardening: a remote URL that would prompt (an `https://` URL with no credentials) fails within the timeout instead of hanging, with `GIT_TERMINAL_PROMPT=0` verified.
- Trailer: commit carries `PeteKM-Device`; `otherDeviceLastCommit` picks the newest commit from a different device and ignores trailer-less commits.
- Coordinator: triggers during a run coalesce to exactly one follow-up run; departure trigger with no local changes does nothing; back-off states suppress and clear as in §6.6. Inject a fake clock and a fake git runner.
- Pre-New-Day: incoming today's file + no keystroke → adopted, composed text discarded, nothing written. Keystroke before arrival → composed text written immediately. Timeout → written.
- `ensureDailyUnionMerge`: appends to an existing `.gitattributes`, creates when missing, idempotent.

**Manual two-Mac checklist** (append to a v2 `plan.md`):

1. Write on A, hide the window, open B → B shows "Updated from A." and today's sticky matches.
2. Write on A, keep the window up, wait 60s, open B → same.
3. Turn off A's Wi-Fi, write, close the lid. Open B and write in today's sticky. Reopen A online → A shows "Merged today's Daily Sticky from both Macs. Check the order."; both Macs converge; no lines lost.
4. Same note in `library/` edited on both while A is offline → A pauses with the v1 conflict notice, orange dot; B unaffected; resolving in a terminal clears the dot on the next trigger.
5. A offline with pending changes for over 2 min → dot appears; mouse Quit → alert; Cancel keeps the app; Quit Anyway quits; relaunch online → pushes, and the earlier-notes notice shows.
6. B: status popover shows "Last from A: <time>" matching A's last push.
7. Turn the toggle off → v1 behavior exactly (banner, manual only).
8. Run `/petekm-process` in a terminal while the app is open and typing → no lock errors surface; the app skips and catches up.

## 12. Out of scope

- **Real-time sync** (sub-minute convergence while both Macs are actively typing in the same note). Git over GitHub is the store; the presence poll's 5 min is the floor while both windows are idle-open.
- **Any server, push notification, or GitHub webhook** to tell Mac B that Mac A has changes. It would also not solve §9, since unpushed work is invisible to any server.
- **Union or any automatic merge for `library/`**. Library notes are curated documents where line order carries meaning.
- **A conflict-resolution UI.** v1 §5.4 stands.
- **Squashing the more frequent automatic commits**, including folding unpushed local commits into one before push. History grows faster, roughly one commit per writing pause (on the order of 10k commits per year). Commit count does not matter here: git and GitHub handle it easily, and every commit is a restore point. Local squashing would add a history-rewrite step (`reset --soft`) that must avoid the agent's own `/petekm-process` commits and the device trailer, which is complexity and risk for no user-visible gain. Decided 2026-10-05.
- **GitHub auth management, repo creation** (v1 §7, §8 unchanged).
- **iOS or any third device type.**

## 13. Decisions made in this spec

Each could be revisited, but none blocks implementation.

1. Automatic sync defaults **on** for folders with a remote.
2. A single engine for manual and automatic runs; v1's one-button principle (§4.4) extends to triggers.
3. `daily/*.md merge=union` is shipped and auto-repaired into existing folders. This is the only automatic conflict resolution in the system.
4. No warning on the receiving Mac about the other Mac's unpushed work, because it is impossible to know. "Last from <Mac>: <time>" plus sender-side signals (dot, quit alert, wake notice) replace it.
5. The window indicator is a dot that appears only when something is wrong or waiting. No persistent "synced" chrome.
6. Editing-idle departure is 60s, trading more commits for a smaller unsynced window.
7. A manual Sync always answers, including when skipped as busy or stuck (§5.5). Automatic runs stay silent.
8. The sleep/quit budget is a deadline that skips network steps once spent but always lets the local commit and a rebase abort finish (§5.3).
9. A paused run that is still behind does not push (§6.6): the push could only be rejected.
