# Updating a PeteKM clone on a second machine

How to pull the latest source onto another Mac (for example a work laptop) that
runs PeteKM from a local `git clone` plus a local Xcode build — not from the
`.dmg`/Sparkle channel described in `DISTRIBUTION.md`.

## The short version

```bash
cd /path/to/PeteKM
git fetch origin
git status                       # expect "behind 'origin/main' by N commits"
git pull --ff-only origin main
git log --oneline -3             # expect your latest commit at the top
```

Then rebuild the app (see [Rebuild the app](#rebuild-the-app)). Pulling source does
not change the installed `.app`.

## Why `git status` says "up to date" when it isn't

`git status` does no network access. It compares your local `main` against the
*remote-tracking ref* `origin/main`, which is a cached copy stored in the clone.
That cache only changes when you run `git fetch` (or a command that fetches, such
as `git pull`). Until then, a commit pushed from another machine is invisible:
`git status` and `git log` both report the stale state, even though GitHub has the
commit.

Run `git fetch origin` first; the "behind by N commits" message appears afterward.

## Why `git log` still misses the commit after a fetch

`git fetch` updates `origin/main` only. It never moves your local branch or your
working tree. So:

- `git log` — shows `HEAD`, i.e. your local `main`: still the old commit.
- `git log origin/main` — shows the fetched remote branch: the new commit.

This is expected. The files on disk change only when you merge, rebase, or
fast-forward with `git pull`.

## What `--ff-only` means

A *fast-forward* is possible when your local branch has no commits the remote
lacks. Git then simply slides the branch pointer forward to the remote commit —
no merge commit, no conflicts.

`--ff-only` requires that case and refuses anything else:

```
fatal: Not possible to fast-forward, aborting.
```

That failure means the second machine has local commits of its own. Nothing is
lost; decide deliberately whether to rebase them onto `origin/main`, merge, or
discard them. Plain `git pull` would instead merge or rebase silently, depending
on config — `--ff-only` is the safer default for a machine that is only meant to
consume upstream changes.

Note the two leading dashes. `-ff-only` is not a valid flag and git rejects it.

## If the commit is still missing after fetching

Work through these in order, from the repo directory:

```bash
pwd                                     # correct clone?
git rev-parse --abbrev-ref HEAD         # on main, not detached or another branch
git remote -v                           # same repository you pushed to, not a fork
git ls-remote origin refs/heads/main    # SHA that the remote actually holds
```

Compare the `ls-remote` SHA against the commit SHA shown on GitHub. If they match,
the remote is right and the problem was only the missing fetch. If they differ, the
clone points at a different repository, or the push landed on a different branch.

## Rebuild the app

A source pull leaves the installed `.app` untouched. Rebuild after every pull.

In Xcode: open `PeteKM.xcodeproj`, Product → Clean Build Folder (⇧⌘K), then
Product → Build (⌘B).

From the terminal:

```bash
xcodebuild -scheme PeteKM -configuration Release build
```

Quit the running PeteKM before replacing the app bundle. Use PeteKM → Quit PeteKM with the mouse, or the menu-bar item — keyboard ⌘Q only hides the window.

These local builds are signed with a development certificate, so they are not
notarized and do not receive Sparkle updates. For the shipped, notarized artifact
see `DISTRIBUTION.md`.
