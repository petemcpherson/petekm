# Distribution & Updates

Spec §20.1–§20.2. PeteKM ships **outside** the Mac App Store, through **Homebrew only**. Everything lives in one public repo, `github.com/petemcpherson/petekm`:

- **Source code.**
- **Releases.** Each release is a Developer ID–signed, notarized `.dmg` attached to a GitHub Release.
- **Homebrew cask.** `Casks/petekm.rb` in this repo acts as the tap. There is no separate `homebrew-petekm` repo.

Users update with `brew upgrade`. There is no in-app updater (see "Sparkle (deferred)").

**Coming back after a break? Read "Ship a new release" first.** It is the whole job. The rest of this file is reference.

---

# Ship a new release

About 20 minutes, most of it waiting on tests and Apple's notary service. Run every command from the repo root.

## 0. Pre-flight (30 seconds)

These are the things that silently expire or go missing between releases:

```bash
# Signing certificate present and not expired (current one expires Feb 2031)
security find-certificate -c "Developer ID Application" -p | openssl x509 -noout -enddate

# Notary credential works (an empty list or a history is fine; an error is not)
xcrun notarytool history --keychain-profile petekm-notary | head -5

# Team ID file exists (gitignored, per machine)
cat Config/Local.xcconfig

# Logged in to GitHub CLI
gh auth status

# What was the last release? You need its version and build number.
gh release list -R petemcpherson/petekm --limit 3
```

If any of these fail, see "New Mac or broken credentials" below. Also make sure the paid Apple Developer membership hasn't lapsed (<https://developer.apple.com/account>); notarization fails without it.

## 1. Pick the numbers

Look at the **Release log** at the bottom of this file.

- **Version** (`MARKETING_VERSION`, what users see): bump it semver-style. Bug fixes only: `1.0.0` → `1.0.1`. New features: `1.0.0` → `1.1.0`.
- **Build** (`CURRENT_PROJECT_VERSION`): the previous build number + 1. It never goes down and never repeats.

You don't edit these in Xcode. `release.sh` stamps both into the build. The `1.0`/`1` values in `project.pbxproj` only affect Debug builds.

Set them once for the rest of this runbook:

```bash
V=1.0.1   # new version
B=2       # new build number
```

## 2. Clean tree + tests

```bash
git status    # clean, on main, pushed
xcodebuild -scheme PeteKM test -only-testing:PeteKMTests -parallel-testing-enabled NO   # must be green, ~90 s
```

Any failure is a blocker. Tests are a manual gate only. `release.sh` does not run them.

**Run the unit tests serially, and don't run the plain `xcodebuild -scheme PeteKM test`.** In parallel, the git-sync tests spawn many `git` processes at once. They fail at random with `The operation couldn't be completed. Bad file descriptor`, even though every one passes alone. The serial run was green twice in a row on 2026-10-08 (243 tests).

The UI tests (`PeteKMUITests`) are not part of the gate. On the dev Mac, `testClosingTheWindowHidesTheAppWithoutQuitting` fails at line 65 every time, at v1.0.0 as well, so the failure is not a regression. Use the smoke test in step 3 instead.

## 3. Build, sign, notarize

```bash
export DEVELOPMENT_TEAM=$(sed -n 's/^PETEKM_DEVELOPMENT_TEAM *= *//p' Config/Local.xcconfig)
scripts/release.sh "$V" "$B"
spctl -a -t open --context context:primary-signature -v "build/PeteKM-$V.dmg"   # must say "accepted"
```

Output: `build/PeteKM-$V.dmg`, signed, notarized and stapled. Notarization usually takes 1–10 minutes. Ignore the script's last line about Sparkle and the appcast; it doesn't apply while Sparkle is deferred.

Optional smoke test: open the DMG, drag the app somewhere temporary, launch it, and click around before publishing.

## 4. Publish the GitHub Release

```bash
git tag "v$V" && git push origin "v$V"
gh release create "v$V" "build/PeteKM-$V.dmg" --title "PeteKM $V" --notes "What changed, in a line or two."
```

Use `--generate-notes` instead of `--notes` for an automatic list of commits since the last tag.

Naming is load-bearing. The tag **must** be `v<version>` and the file **must** be `PeteKM-<version>.dmg`, because the cask builds its download URL from those.

## 5. Update the cask

```bash
shasum -a 256 "build/PeteKM-$V.dmg"
```

In `Casks/petekm.rb`, change only two lines: `version "<V>"` and `sha256 "<that hash>"`. Add a row to the **Release log** at the bottom of this file. Then:

```bash
git add Casks/petekm.rb context/DISTRIBUTION.md
git commit -m "Release $V"
git push
```

Once this push lands on `main`, `brew upgrade` delivers the new version to everyone.

## 6. Verify the upgrade path

On your own Mac, which still has the previous version installed through brew:

```bash
brew update
brew upgrade --cask petekm
brew audit --cask --strict petemcpherson/petekm/petekm
open -a PeteKM          # About PeteKM should show the new version; no Gatekeeper warning
```

If the upgrade doesn't see the new version, check that step 5 was pushed to `main`, then run `brew update` again.

Done.

---

# How the pieces fit

```
Xcode project ──release.sh──▶ build/PeteKM-<v>.dmg (signed + notarized)
                                     │
                         gh release create v<v>
                                     ▼
          GitHub Release v<v>  ◀── download URL ──  Casks/petekm.rb (version + sha256)
                                                          │
                                         brew tap / brew upgrade reads it from main
```

| Thing | Where | Committed? |
| --- | --- | --- |
| Release script | `scripts/release.sh` | Yes |
| Homebrew cask | `Casks/petekm.rb` | Yes |
| Team ID | `Config/Local.xcconfig` (`PETEKM_DEVELOPMENT_TEAM`) | No, gitignored, per Mac |
| Signing certificate + private key | login keychain, "Developer ID Application: Peter McPherson" | No |
| Notary credential | login keychain, profile `petekm-notary` | No |
| Build output | `build/` (wiped on each `release.sh` run) | No |

Build settings in `project.pbxproj` that distribution depends on:

| Setting | Value | Why |
| --- | --- | --- |
| `ENABLE_APP_SANDBOX` | `NO` | The app shells out to `git`, `code`, and Terminal (§12, §15, §17). |
| `ENABLE_HARDENED_RUNTIME` | `YES` | Required for notarization. |
| `ENABLE_USER_SELECTED_FILES` | `readwrite` | The PeteKM folder is user-chosen and written to. |
| `PRODUCT_BUNDLE_IDENTIFIER` | `com.petekm.PeteKM` | Stable app identity. **Never change it.** |
| `MACOSX_DEPLOYMENT_TARGET` | `26.2` | Only macOS 26.2+ can install. If you lower it, also change `depends_on macos:` in the cask. |

---

# New Mac or broken credentials

The repo has everything except three per-machine secrets. On a new Mac (or if pre-flight fails), restore whichever is missing.

## Signing certificate

- **Moving Macs:** on the old Mac, open Keychain Access, find "Developer ID Application: Peter McPherson", expand it so the private key shows, select both, then File → Export Items as `.p12`. Double-click the `.p12` on the new Mac.
- **Lost or expired:** Xcode → Settings → Accounts → your team → Manage Certificates → + → Developer ID Application. Apple allows only a few of these per account; revoke stale ones at <https://developer.apple.com/account/resources/certificates>.

## `Config/Local.xcconfig`

```
PETEKM_DEVELOPMENT_TEAM = <TEAMID>
```

The Team ID is at <https://developer.apple.com/account> → Membership details.

## Notary credential (`petekm-notary`)

1. Create an **app-specific password**: <https://account.apple.com> → Sign-In and Security → App-Specific Passwords → +. Name it "petekm-notary".
2. Store it in the keychain:

```bash
xcrun notarytool store-credentials petekm-notary \
  --apple-id "<your Apple ID email>" \
  --team-id "<TEAMID>" \
  --password "<app-specific password>"
```

3. Verify: `xcrun notarytool history --keychain-profile petekm-notary` prints a history, not an error.

Changing your Apple ID password revokes all app-specific passwords. Redo this section if that happens.

---

# What users run

Install. The tap line runs once. It needs the full URL because the repo isn't named `homebrew-petekm`. Homebrew 7 refuses casks from third-party taps until they are trusted. Installing by the fully qualified name (`petemcpherson/petekm/petekm`) trusts the cask automatically. A bare `brew install --cask petekm` fails with `Refusing to load cask … from untrusted tap`.

```bash
brew tap petemcpherson/petekm https://github.com/petemcpherson/petekm
brew install --cask petemcpherson/petekm/petekm
```

Update:

```bash
brew upgrade
```

The DMG on the Releases page also works for a manual install, but those users get no update notices. Advertise the brew commands.

---

# Release log

Add a row every release. The build number must always increase.

| Version | Build | Date | Notes |
| --- | --- | --- | --- |
| 1.0.0 | 1 | 2026-10-06 | First public release. |
| 1.0.1 | 2 | 2026-10-08 | Sync fix for a new Daily Sticky on both Macs; legible text on custom backgrounds. |

---

# History: first-time setup (done 2026-10-06)

Recorded for reference. None of this needs redoing for a normal release.

1. **Pre-public cleanup.** Added `LICENSE` (MIT, "Copyright (c) 2026 Pete McPherson") and `README.md`. Removed a hardcoded home path from `context/design-system/gen-appicon-layer.py`. Scanned the full git history and `context/` for credentials and personal content.
2. **Made the repo public:** `gh repo edit petemcpherson/petekm --visibility public --accept-visibility-change-consequences`. Older commits carry `pnm326@gmail.com`; to hide it on new commits, turn on "Keep my email addresses private" on GitHub and set `git config user.email` to the `…@users.noreply.github.com` address.
3. **Created the `petekm-notary` keychain profile** (see "New Mac or broken credentials").
4. **Wrote `Casks/petekm.rb`.** Homebrew can tap any git repo given its URL, as long as the repo has a `Casks/` folder. Trade-off: `brew tap` clones the whole repo (~3 MB). The cask has no `auto_updates true`, so plain `brew upgrade` updates PeteKM; add that line only if Sparkle is added. `zap` removes only app support files, never the user's PeteKM notes folder.
5. **Released 1.0.0** with the runbook above and verified a clean `brew install` on the dev Mac.

---

# Sparkle (deferred)

Sparkle (<https://sparkle-project.org>) is the standard in-app auto-updater for Mac apps outside the App Store. It was **deliberately skipped** for launch, because Homebrew's `brew upgrade` covers updates.

**State:** the package is not added. The code is already written behind `#if canImport(Sparkle)`: `PeteKM/Settings/UpdateController.swift`, the Settings → Updates pane, the "Check for Updates…" menu item, and the relaunch hook. Today it compiles out, and the Updates pane says "This build doesn't check for updates."

**Adding it later is safe for brew users:** they receive the Sparkle-enabled version through `brew upgrade` and get in-app updates from then on. Setup takes about 30–60 minutes once, plus about 2 minutes per release:

1. In Xcode, open File → Add Package Dependencies…. Add `https://github.com/sparkle-project/Sparkle` (2.x) to the **PeteKM** target only. Commit `Package.resolved`, and remove `Package.resolved` from `.gitignore`.
2. Download the matching Sparkle release tarball and extract it to `~/Tools/Sparkle/`. Run `bin/generate_keys` **once ever**. It stores the private key in your keychain and prints the public key. Back up the private key with `generate_keys -x <file>` to your password manager. Losing it means existing installs can't accept updates.
3. Create `Config/Info.plist`, a partial plist that Xcode merges with the generated one. Put it in `Config/`, not in the synced `PeteKM/` folder. It needs these keys:
   - `SUFeedURL`: `https://raw.githubusercontent.com/petemcpherson/petekm/main/appcast.xml`
   - `SUPublicEDKey`: the public key from step 2
   - `SUEnableAutomaticChecks`: `true`

   Set the PeteKM target's `INFOPLIST_FILE` to `Config/Info.plist` and keep `GENERATE_INFOPLIST_FILE = YES`. `INFOPLIST_KEY_*` build settings can't hold these custom keys.
4. Each release, after step 3 of the runbook:
   1. Run `~/Tools/Sparkle/bin/sign_update build/PeteKM-<v>.dmg`. It prints `edSignature` and `length`.
   2. Add an `<item>` to `appcast.xml` at the repo root. Fill in `sparkle:version` (the build number), `sparkle:shortVersionString`, `sparkle:minimumSystemVersion` 26.2, and an `enclosure` with the Release DMG URL plus the signature and length from step 1.
   3. Commit `appcast.xml` with the cask change.
5. Add `auto_updates true` to the cask.

---

# Later (optional)

- **Official `homebrew/cask`.** When PeteKM is notable enough, submit a PR so users can run plain `brew install --cask petekm` without tapping. Homebrew requires meaningful GitHub stars, forks and watchers, with a higher bar for self-submitted apps. Then delete `Casks/` from this repo.
- **Automate steps 4–5.** Extend `release.sh` to call `gh release create` and rewrite the cask's `version`/`sha256`.

---

# Troubleshooting

| Symptom | Cause / fix |
| --- | --- |
| `No Keychain password item found for profile: petekm-notary` | Notary credential missing on this Mac, or revoked by an Apple ID password change. See "New Mac or broken credentials". |
| `release.sh` fails at archive/export with a signing error | Developer ID certificate missing or expired, or `DEVELOPMENT_TEAM` empty. Run the pre-flight checks. |
| Notarization "Invalid" | Run `xcrun notarytool log <submission-id> --keychain-profile petekm-notary`. It is usually an unsigned nested binary or hardened runtime turned off. |
| Notarization rejected for agreements/membership | Apple Developer membership lapsed or a new agreement needs accepting at <https://developer.apple.com/account>. |
| Many git-sync tests fail with `Bad file descriptor` | The suite ran in parallel. Rerun with `-parallel-testing-enabled NO` (step 2). |
| UI tests hang ~60 s then fail | PeteKM is running. Quit every copy and rerun. UI tests are not part of the release gate. |
| `brew install` SHA mismatch | The cask `sha256` came from a different DMG than the one on the Release. Recompute it from the uploaded file. |
| `Refusing to load cask … from untrusted tap` | The install used the bare name. Run `brew install --cask petemcpherson/petekm/petekm` instead, which trusts the cask. Alternatively, run `brew trust petemcpherson/petekm` once. |
| `brew install` 404 | The tag isn't `v<version>`, or the DMG filename doesn't match `PeteKM-<version>.dmg`. |
| `brew upgrade` doesn't see the new version | The user needs `brew update` first, which normally runs automatically. Also check that the cask commit was pushed to `main`. |
| Gatekeeper warns on first launch | The DMG wasn't notarized or stapled. Re-run `release.sh` and check the `stapler validate` output. |
