# Sync Specification: Multi-Device Git Sync + Unified Process

**Status:** Final — no open decisions. Ready for implementation planning.
**Supersedes:** `context/spec.md` §17 (Git and Version History) in full. Amends §12, §13, §14, §15 wherever they name `Git Sync`, `petekm-process-today`, or `petekm-process-date`.
**Does not change:** §2.5 (Daily Stickies immutable to AI), §8.5/§19.4 (external-change conflict system), §2.2 (Markdown-on-disk is the only canonical store).

---

## 0. Problem statement

The user runs PeteKM on two machines (personal laptop, work laptop) and wants the same PeteKM folder usable on both, staying in sync via GitHub, without:

- ever losing or silently altering a note,
- git jargon or manual conflict surgery in the common case,
- sync work interrupting capture (§17.4's "never block capture" rule extends to this whole document).

Today's `Git Sync` is push-only (commit + push, never pull). That's incompatible with multi-device use — a device can never learn about changes made elsewhere. This spec makes Sync two-way and adds a small number of automatic touch points, while keeping the manual command as the primary, always-available path.

---

## 1. Naming decisions (final)

| Concept | Name | Why |
| --- | --- | --- |
| The act of running the AI agent to file Daily Stickies into the Library | **Process** | Already the underlying vocabulary — the shipped skills are named `petekm-process-today` / `petekm-process-date`. No new word needed; just promote it to the user-facing verb and stop having two verbs for one action (see §3). |
| The organized knowledge store the agent maintains | **Library** | Already fixed by `DESIGN.md` §2. No new word needed — "brain" was never adopted, don't reintroduce it. |
| The combined commit/pull/push action | **Sync** | Replaces "Git Sync." Drop "Git" from the user-facing name — the user shouldn't need to know it's Git to use it (§5). Internal code/types may keep `Git`-prefixed names. |

No new persona name is introduced. §13.1 ("No persona") stands.

---

## 2. Scope split: two independent sync implementations

This is the single most important architectural clarification in this document.

The app (Swift) and the agent (Claude Code, running in a user's terminal) are **separate processes that never coordinate directly.** The app has no way to know when the user runs Process in a terminal, and the agent has no way to invoke Swift code. So "sync before/after Process" cannot be implemented as the app calling into the agent, or vice versa. It's implemented twice, once on each side, using the same safety rules (§6) but different mechanics:

1. **App-side Sync** — Swift code in `GitSupport.swift`, invoked by the user (palette/Settings, §4) or by the app itself at launch (§4.3, fetch-only). This is the primary, always-visible mechanism.
2. **Agent-side sync** — plain shell commands the *skill instructions* tell the agent to run, at the start and end of a Process run (§3.3). This is the agent pulling fresh Library state before it writes, and publishing its own writes promptly after. It reuses the same git commands and the same conflict posture (never force, never silently resolve) but is just markdown instructing an LLM to run shell commands — there's no shared Swift code path.

Both must independently satisfy §6 (data-integrity rules). They are described separately below and should be implemented and tested separately.

---

## 3. Unified "Process"

### 3.1 Problem with the current split

`/petekm-process-today` and `/petekm-process-date` run **identical procedures**; the only difference is how the target date is resolved. This already forces `/petekm-process-date` to support ranges ("if asked for a range of dates, process them oldest-first"). There is no reason to keep two entry points, and the split fails the exact scenario in the user's question: Daily Stickies dropped into `daily/` by hand (backfilled from a week of paper notes, e.g.) aren't "today" and aren't a single named date — nobody would think to run `/petekm-process-date` for seven different dates.

### 3.2 New behavior

One skill, one slash command: **`/petekm-process`**.

- **No argument (default, and the common case):** scan `.petekm-state.json`'s `lastProcessedDailyNote`, list every `daily/*.md` file whose date is newer than that marker — regardless of whether the app ever opened it, whether it's "today," or how the file got there — and process them **oldest-first**, so later days can build on Library files earlier days created. This is exactly today's `/petekm-process-date` range behavior, promoted to the default path.
- **One argument (a date, filename, or plain-language date):** process only that day, regardless of the state marker. This is today's `/petekm-process-date` single-day behavior, kept as an explicit override for the case the user described earlier — re-running one specific day after changing filing rules.
- **State advancement rule is unchanged:** update `lastProcessedDailyNote` only when the run processes a note **newer** than the currently recorded one. Backfilling or reprocessing an older day never moves the marker backward *or* falsely forward.

This directly answers the user's question: manually-dropped Daily Stickies for a past week are picked up automatically by plain `/petekm-process`, oldest-first, no special handling required. Nothing distinguishes an app-created Daily Sticky from a hand-created one — both are just `daily/YYYY-MM-DD.md` files, which is exactly the point of §2.2 (files are the only source of truth).

### 3.3 Sync folded into Process (agent-side, per §2)

`AGENTS.md` and the `petekm-process` `SKILL.md` are updated to add two steps, shell commands the agent runs directly (it already has shell access — it's Claude Code in a terminal):

**Before processing (step 0, new):**
```bash
git rev-parse --is-inside-work-tree >/dev/null 2>&1 && git pull --rebase --autostash
```
If this is not a Git repository, or Git isn't installed, skip silently and proceed — Process must never be blocked by the absence of Git (mirrors §17.4/§6.5 below). If the pull reports a conflict, **stop Process entirely, do not process anything, and report the conflict plainly** ("Sync conflict — couldn't pull latest changes before processing. Resolve it (ask me, or run `git status` yourself), then run `/petekm-process` again."). Never processes against a repo mid-conflict, never guesses which side is right.

**After processing (final step, replaces the old "report" step's silence on Git):**
```bash
git add -A && git commit -m "PeteKM: processed <dates>" && git pull --rebase --autostash && git push
```
Rationale for pulling *again* here, not just pushing: the app or the other device could have pushed something in the minutes the agent spent processing. Same conflict posture — if this second pull conflicts, the agent's local commit is **not lost** (it's a real commit, sitting on the local branch); report "Processed successfully and committed locally, but couldn't sync — conflict pulling latest changes. Run Sync from the app, or ask me." Never force-push, never skip the pull to "just push anyway."

If there's no remote configured, the commit still happens; the agent reports "Processed and committed locally. No GitHub remote is set, so nothing was pushed." Same as `.noRemote` in §6.5.

This is the *only* place a Process run touches Git. The agent does not need to know about `SyncOutcome` or Swift types — it's plain shell + plain-language reporting, matching the existing style of every other skill in `AgentTemplates.swift`.

### 3.4 File/skill renames

- `.claude/skills/petekm-process-today/` and `.claude/skills/petekm-process-date/` → single `.claude/skills/petekm-process/`.
- `petekm-status` is updated to reference `/petekm-process` instead of the two old names, and its report (§13 item 6 today) gains one line: ahead/behind counts relative to the remote, worded plainly — "3 commits not yet pushed" / "2 new commits on GitHub, not yet pulled" / "Up to date with GitHub." (Uses `git rev-list --left-right --count HEAD...@{upstream}`; if there's no upstream, omit the line rather than error.)
- `petekm-organize` and `petekm-rebuild-index` are untouched — they're already single-purpose and don't have a today/date split.
- `INDEX.md`, `CLAUDE.md`, `AGENTS.md` template text in `AgentTemplates.swift` (currently listing `/petekm-process-today` and `/petekm-process-date` as two bullets) collapse to one bullet: `` `/petekm-process` — file new Daily Stickies into the Library; pass a date to reprocess one day. ``

### 3.5 Migration for existing folders (Refresh Agent Files)

Existing PeteKM folders already have `.claude/skills/petekm-process-today/SKILL.md` and `.../petekm-process-date/SKILL.md` on disk. `FolderInitializer.refreshAgentFiles` (§6.5's `.backUpThenReplace` policy) is extended so that, specifically for this rename, it:

1. If `petekm-process-today/SKILL.md` or `petekm-process-date/SKILL.md` exists, back each up individually via the existing `FileWriting.backUp(_:into:)` convention (preserves any hand-edits the user made, same as every other tracked file) — the whole directory doesn't need backing up, only the one file it contains.
2. Remove the now-empty `petekm-process-today/` and `petekm-process-date/` directories.
3. Write the new `petekm-process/SKILL.md`.

This runs once, gated the same way the existing out-of-date notice is (`agentTemplatesFingerprint`, `settings.agentFilesNoticeShownFor`) — a user who already refreshed after this version ships doesn't see it again.

---

## 4. Unified "Sync" (app-side)

One command, one verb, replacing `Git Sync` everywhere it appears (palette, Settings → Folder, and every explanatory string in `SettingsView.swift`, `GuideSettingsView.swift`, `PeteKMFolder.swift`, `ScratchStore.swift`). Internal Swift symbol names may keep `Git*` (e.g. `GitSupport`) since that's implementation, not user-facing copy.

### 4.1 What it does

`Sync` = commit anything dirty → pull (rebase) → push, in that fixed order, always all three steps attempted (each may no-op). Never a partial menu of "just push" or "just pull" in the UI — see §4.4 for why one button is correct here.

### 4.2 Touch points

1. **Command palette → "Sync"** (renamed from "Git Sync"). Same availability gate as today (`isGitRepository`). This is the primary, always-available manual path.
2. **Settings → Folder → Git section → "Sync" button.** Same as today's `sync()` in `GitSettingsSection`, calling the same unified function.
3. **App launch / new session — passive check only, §4.3.** Not a full Sync; a cheap read-only check that prompts the user to run one of the two buttons above.

No automatic full Sync ever runs unattended (i.e., never on save, never on a timer, never on quit). The user explicitly rejected that, and §17.4-style "capture never blocks" reasoning applies just as much to "capture never gets interrupted for network I/O."

Process (§3.3) has its own git steps and does **not** call this app-side function — see §2.

### 4.3 Launch / new-session check

Once per app process lifetime, the first time `FolderStore.State` becomes `.ready` (app launch, or recovering from `.missing`, or a fresh folder pick) — **not** every time the sticky window is summoned via the global hotkey, since the app is background-resident and hides rather than closes (§8.7); re-summoning is not a "new session."

Runs, off the main actor, best-effort:

```bash
git fetch
git rev-list --left-right --count HEAD...@{upstream}
```

- If Git is unavailable, this isn't a repository, there's no remote, or `fetch` fails (offline, auth failure) — **do nothing, show nothing.** This check is never allowed to produce an error state; offline is the normal case for a laptop, not a problem to report.
- If the counts show the local branch is even with upstream — do nothing.
- If local is ahead, behind, or both (diverged) — show one non-modal, dismissible banner in the Daily Sticky window: **"Changes to sync."** with a single button, **"Sync."** No commit counts, no "ahead/behind," no Git terms — the number doesn't help a non-technical user decide anything; the existence of a difference is the only fact that matters. Clicking it runs the exact same unified Sync as §4.1.
- The banner is dismissible (an "×"), and once dismissed or once Sync is run, it does not reappear for the rest of that app session even if the check could theoretically run again — it only ever runs once per session, so this is naturally satisfied.
- `git fetch` never touches the working tree, so this check carries zero conflict risk and is safe to run unconditionally and silently.

### 4.4 Why one button, not separate Pull/Push

The user asked whether splitting Pull and Push would be easier to implement. It would not meaningfully simplify the implementation (both are a few lines of `GitSupport.run`), and it reintroduces exactly the decision-making PeteKM is designed to remove from the user (§2.1, §2.4): "should I pull first?" is not a question a non-technical user should ever have to answer. One button that always does the safe full sequence is both simpler to build correctly (one code path to get right, not two, plus their interaction) and better UX. Decision: single button, final.

---

## 5. Conflict handling — the data-integrity core

This section is the direct answer to "how do we never lose or alter anything, ever."

### 5.1 Sequence, precisely

`GitSupport.sync(_:)` (app-side; the agent-side sequence in §3.3 follows the same shape) does, in order:

1. **`git add -A`**, then if `git status --porcelain` is non-empty, **`git commit -m "PeteKM backup <timestamp>"`**. This step is unconditional and comes first, always — before any network operation. Nothing that exists on disk is ever left uncommitted while a pull is attempted. This is the single most important integrity guarantee in this design: a commit is a safe, local, undo-able checkpoint, and it exists *before* anything risky happens.
2. **`git fetch`.** If this fails (no network, auth failure), stop here and return `.offline` — the commit from step 1 already happened, so the user's edits are safe on the local branch even though nothing reached GitHub yet. Nothing is lost; it just isn't published yet.
3. If there's no remote configured (`git remote` empty), stop here and return `.noRemote` — same reasoning, local commit already safe.
4. If the local branch is already even with `@{upstream}` and step 1 committed nothing, return `.nothingToSync` ("Already up to date.").
5. **`git pull --rebase --autostash`** (only if local is behind). `--autostash` is defense-in-depth, not the primary safety mechanism — step 1 already committed everything, so there should be nothing to stash under normal operation; it only matters if something wrote to disk in the narrow window between steps 1 and 5 (e.g. the 600ms-debounced autosave firing on an open file). If this reports a conflict:
   - **Immediately run `git rebase --abort`.** This is unconditional and automatic — never prompt the user to resolve inline, never leave the repository in a conflicted state.
   - `git rebase --abort` restores the working tree and branch to exactly their pre-pull state, byte for byte. Nothing on disk changed; nothing was lost or altered. The attempt simply didn't happen.
   - Return `.pullConflict`.
6. **`git push`** (or `git push --set-upstream <remote> <branch>` the first time, matching today's logic for a branch with no upstream). If this fails, return `.pushFailed` — the pull in step 5 (if it ran) already succeeded and is safe locally; only publishing failed.
7. Otherwise, return `.synced`.

### 5.2 Why a conflict can never lose data

Every branch of §5.1 either (a) does nothing to the working tree beyond what's already safely committed, or (b) fully reverts an attempted operation before reporting failure. There is no code path where PeteKM chooses a side of a conflict, discards a version of a file, or force-pushes. The worst outcome of any Sync is "nothing got published this time" — never "something got overwritten."

### 5.3 `SyncOutcome` (replaces the current enum)

```swift
enum SyncOutcome: Equatable {
    case gitUnavailable
    case notARepository
    case offline
    case noRemote
    case pullConflict
    case pushFailed
    case nothingToSync
    case synced
}
```

Notices (plain language, no Git terms except where the user already sees "Git" elsewhere in Settings):

| Case | Notice |
| --- | --- |
| `gitUnavailable` | "Git isn't available." |
| `notARepository` | "This PeteKM folder isn't a Git repository." |
| `offline` | "Saved locally. Couldn't reach GitHub." |
| `noRemote` | "Saved locally. No GitHub remote is set." |
| `pullConflict` | "Sync paused — the same note changed on two devices. Nothing was lost or changed. [See §5.4]" |
| `pushFailed` | "Saved and up to date locally, but couldn't publish to GitHub. Try Sync again." |
| `nothingToSync` | "Already up to date." |
| `synced` | "Synced." |

`offline` and `noRemote` both replace what today's `committedNotPushed` conflated; splitting them means the toast can say something a non-technical user immediately understands ("no internet" vs. "not set up yet") instead of a Git-flavored compound sentence.

### 5.4 What the user actually does on `pullConflict`

This is deliberately the only case that asks anything of the user, because it is the only case where automatic resolution is unsafe. The toast (shown for a longer duration than the default 6s — use 15s, matching the existing pattern for the agent-files-out-of-date notice) reads:

> "Sync paused — the same note changed on two devices. Nothing was lost or changed. Ask PeteKM (in a terminal) to help sort it out, or open the folder in [VS Code] yourself."

Two paths, both already exist in the app:
- **Open Terminal in PeteKM Folder** (existing palette command) → the user's Claude Code agent, if invoked, can look at `git status`/`git diff` and explain the conflicting lines in plain language. No new skill is required for v1 of this spec — the agent already has full shell + filesystem access and can be asked ad hoc ("there's a sync conflict, help me sort it out"). A dedicated `petekm-resolve-sync-conflict` skill is a plausible future addition (flagged in §8) but is explicitly **not required** for this spec, since ad hoc agent help already covers it and adding a skill is pure polish.
- **Open PeteKM Folder in VS Code** (existing palette command) → manual resolution for a user who prefers that.

Rare in practice: `daily/` files are dated and typically edited on one device per day, and Library edits from Process runs are naturally serialized by §3.3's pull-before/push-after. Real conflicts should be an edge case, not a routine occurrence — this design optimizes for that edge case being safe, not smooth, which is the right tradeoff for a "never lose data" priority.

### 5.5 Interaction with the existing open-file conflict system

A successful (non-conflicting) pull can rewrite a file that's currently open in the editor with unsaved changes. This is **not a new problem** — `DirectoryWatcher` + `StickyDocument`'s existing `Conflict(diskText:)` / `ConflictChoice` machinery (§8.5, §19.4 of the main spec) already exists precisely for "the file changed on disk while open," driven by FSEvents, which does not care whether the change came from VS Code, Finder, or a `git pull`. No new conflict UI is designed here — implementation should simply **verify** (not redesign) that a git-driven rewrite trips the same watcher path as any other external edit. If it does not currently, that is a pre-existing gap this spec surfaces but does not fix — flag as a required verification step in the implementation plan, not a new feature.

---

## 6. Data-integrity rules (summary, normative)

These are the non-negotiable rules for both the app-side and agent-side implementations, restated compactly because they're the whole point:

1. **Commit before any network operation.** Nothing is ever exposed to a pull/rebase while uncommitted.
2. **Never force-push.** Not in any code path, not as a fallback, not ever.
3. **Never resolve a conflict automatically.** Not "pick newer," not "pick longer," not "merge and hope." A conflict always aborts the operation and asks the human (§5.4).
4. **An aborted operation fully restores prior state.** `git rebase --abort` after any conflict, unconditionally, before returning control.
5. **A failed publish (push) is not a failed save.** The distinction between "safe locally" and "visible on GitHub" is always preserved in the reported outcome (§5.3) — never conflate them into one generic "sync failed."
6. **Sync/Process never blocks capture.** Every failure mode degrades to a plain notice; none may prevent opening or saving today's Daily Sticky (extends §17.4).

---

## 7. Connecting a remote (new, small addition)

Today there is no in-app way to attach a GitHub remote — only `GitSettingsSection`'s read-only display of an existing one, plus "Initialize Repository." For the stated goal of a smooth, non-technical setup, `GitSettingsSection` gains one small addition, shown only when `isRepository && remote == nil`:

- A single-line text field ("GitHub URL") and a "Set Remote" button, running `git remote add origin <url>`.
- No validation beyond "non-empty" and letting Git itself reject a bad URL (surfaced as a plain "Couldn't add that remote — check the URL." on failure).
- No authentication UI. PeteKM relies entirely on the system's existing Git credential setup (SSH key or the OS/keychain-backed HTTPS credential helper the user already has configured, e.g. via `gh auth login` or Xcode's own Git support). This is an explicit non-goal — PeteKM does not manage GitHub auth, tokens, or SSH keys. If a push fails for an auth reason, it surfaces as the plain `pushFailed` notice (§5.3) like any other push failure; the user resolves auth in a real Git tool, per §17.3's existing philosophy.

Creating the actual GitHub repository (the empty remote to point at) is also out of scope — the user creates it on github.com (or via `gh repo create` in "Open Terminal in PeteKM Folder") themselves. PeteKM only wires the local repo to a URL the user already has.

---

## 8. Explicitly out of scope for this spec (decided, not deferred-by-omission)

- **A dedicated conflict-resolution skill/UI.** Ad hoc agent help + existing external-editor commands cover it (§5.4). Worth revisiting only if real conflicts turn out to be more common than expected in practice.
- **GitHub authentication/token management.** Relies on the user's existing system Git config (§7).
- **Automatic repo creation on GitHub.** User's responsibility (§7).
- **Selective/partial sync** (e.g., syncing `library/` but not `daily/`, or excluding specific files beyond the existing Scratch `.gitignore` exclusion). Everything tracked stays tracked; no new exclusions introduced.
- **Any change to the Scratch file's exclusion from Git** (§ Layer 3b of `context/map.md`). Scratch remains untracked and unsynced, unchanged by this spec.
- **Conflict resolution UI for the rare `daily/` file conflict beyond the existing keepMine/keepDisk/keepBoth alert** (§5.5) — reused as-is, not redesigned.
- **Full offline queueing / retry scheduling** beyond "the next manual or launch-triggered Sync will naturally retry." No background retry timer.

---

## 9. Summary of every touch point (for the implementation plan)

| Trigger | Actor | Operation | Can it block anything? |
| --- | --- | --- | --- |
| Palette → "Sync" | App (Swift) | Full commit→pull→push (§4.1/§5.1) | No — async, off main actor, toast on completion |
| Settings → Folder → "Sync" | App (Swift) | Same as above | No |
| App launch / new session | App (Swift) | `fetch` + ahead/behind check only (§4.3) | No — read-only, silent on any failure |
| Start of `/petekm-process` | Agent (shell, via skill instructions) | `pull --rebase --autostash`; abort Process on conflict (§3.3) | Blocks *that Process run only*, never the app/capture |
| End of `/petekm-process` | Agent (shell, via skill instructions) | `commit` → `pull --rebase --autostash` → `push` (§3.3) | No — commit already safe regardless of pull/push outcome |
| Settings → Folder → "Set Remote" | App (Swift) | `remote add origin <url>` (§7) | No — one-time manual setup action |

Nothing in this table introduces a new background timer, a new blocking dialog on the capture path, or a new persisted setting beyond what already exists (`agentTemplatesFingerprint`-style once-per-version gating is reused for the skill-rename migration notice, §3.5; the launch check needs no persisted state at all, §4.3).
