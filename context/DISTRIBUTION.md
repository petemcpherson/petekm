# Distribution & Updates

Spec §20.1–§20.2. PeteKM ships **outside** the Mac App Store, through **Homebrew only**:

- the source lives in the **public** repo `github.com/petemcpherson/petekm`;
- each release is a Developer ID–signed, notarized `.dmg` attached to a **GitHub Release** in that same repo;
- the Homebrew cask lives in the same repo (`Casks/petekm.rb`). There is no separate tap repo;
- users update with `brew upgrade`. There is no in-app updater (see "Sparkle (deferred)" below).

Everything lives in one repo.

---

## Current state checklist (as of 2026-10-06)

| Item | Status |
| --- | --- |
| Paid Apple Developer account | Done |
| `Developer ID Application: Peter McPherson` certificate in keychain | Done |
| `Config/Local.xcconfig` with `PETEKM_DEVELOPMENT_TEAM` | Done |
| Build settings: hardened runtime on, sandbox off, bundle ID `com.petekm.PeteKM` | Done |
| `scripts/release.sh` (archive → export → DMG → notarize → staple) | Done |
| `petekm-notary` notarytool keychain profile | **Missing** (A3) |
| `LICENSE` (MIT), `README.md`, hardcoded-path fix | Done (A1, by Claude; not yet committed) |
| `Casks/petekm.rb` | Created (A4, by Claude). `sha256` is a placeholder until B4 |
| Personal-content skim of `context/` | **Your call** (A1.4) |
| Repo public | **Missing** (A2) |

Build settings already in `project.pbxproj`:

| Setting | Value | Why |
| --- | --- | --- |
| `ENABLE_APP_SANDBOX` | `NO` | The app shells out to `git`, `code`, and Terminal (§12, §15, §17). |
| `ENABLE_HARDENED_RUNTIME` | `YES` | Required for notarization. |
| `ENABLE_USER_SELECTED_FILES` | `readwrite` | The PeteKM folder is user-chosen and written to. |
| `PRODUCT_BUNDLE_IDENTIFIER` | `com.petekm.PeteKM` | Stable app identity. Never change it after release. |
| `MACOSX_DEPLOYMENT_TARGET` | `26.2` | Only Macs on macOS 26.2+ can install. Lower it if you want a wider audience. |

---

# Part A: One-time setup

Do these in order. Steps marked **✅ Done** were completed by Claude on 2026-10-06. Those changes are in the working tree but **not committed yet**: review them, then commit and push before A2.

## A1. Pre-public cleanup ✅ Done (except item 4)

1. ✅ **`LICENSE`** added at the repo root: MIT, "Copyright (c) 2026 Pete McPherson". Anyone may use, modify and redistribute.
2. ✅ **Hardcoded home path removed** from `context/design-system/gen-appicon-layer.py:2`. `ROOT` is now derived from the script's own location.
3. ✅ **`README.md`** added. It covers what PeteKM is, features, the brew install commands, building from source and the license. Optional: add a screenshot (for example `docs/screenshot.png`, referenced from the README).
4. ✅ **You: skim `context/`** (spec, design, plans) for anything you would not want public. Claude's scans of the full history (2026-10-06) found no credentials, keys, phone numbers or street addresses. A human read is still the only check for personal anecdotes.

✅ Then commit and push:

```bash
git add LICENSE README.md Casks/petekm.rb context/
git commit -m "Prepare for public release: license, README, Homebrew cask"
git push
```

## A2. Make the repo public

Optional first: hide your personal email on future commits. On GitHub, go to Settings → Emails, then turn on "Keep my email addresses private". Copy the `…@users.noreply.github.com` address it shows, then run:

```bash
git config user.email "<id>+petemcpherson@users.noreply.github.com"
```

Existing commits keep `pnm326@gmail.com`. That is fine to leave.

Flip visibility:

```bash
gh repo edit petemcpherson/petekm --visibility public --accept-visibility-change-consequences
```

Treat this as permanent. Clones and forks of a public repo can't be recalled.

## A3. Create the notarization keychain profile

`release.sh` notarizes using a stored credential named `petekm-notary`.

1. Create an **app-specific password**: go to <https://account.apple.com>, open Sign-In and Security → App-Specific Passwords, and click +. Name it "petekm-notary".
2. Find your **Team ID**: <https://developer.apple.com/account> → Membership details. It is the same value as `PETEKM_DEVELOPMENT_TEAM` in `Config/Local.xcconfig`.
3. Store it (one time; the password goes into your login keychain):

```bash
xcrun notarytool store-credentials petekm-notary \
  --apple-id "<your Apple ID email>" \
  --team-id "<TEAMID>" \
  --password "<app-specific password>"
```

4. Verify with `xcrun notarytool history --keychain-profile petekm-notary`. It should print an empty history, not an error.

## A4. Homebrew cask in this repo ✅ Done

Homebrew can tap any git repo when you give it the URL explicitly. The tap only has to contain a `Casks/` folder, so no `homebrew-petekm` repo is needed.

`Casks/petekm.rb` now contains the following. Its `sha256` is a placeholder until the first release (B4):

```ruby
cask "petekm" do
  version "1.0.0"
  sha256 "REPLACE_WITH_SHA256_OF_RELEASE_DMG"

  url "https://github.com/petemcpherson/petekm/releases/download/v#{version}/PeteKM-#{version}.dmg"
  name "PeteKM"
  desc "Markdown daily notes and personal library"
  homepage "https://github.com/petemcpherson/petekm"

  livecheck do
    url :url
    strategy :github_latest
  end

  depends_on macos: ">= :tahoe"

  app "PeteKM.app"

  zap trash: [
    "~/Library/Application Support/PeteKM",
    "~/Library/Caches/com.petekm.PeteKM",
    "~/Library/Preferences/com.petekm.PeteKM.plist",
  ]
end
```

Notes:
- The cask has no `auto_updates true`, so plain `brew upgrade` updates PeteKM. Add that line only if Sparkle is ever added.
- `zap` only removes app support files. It never touches the user's PeteKM folder of notes.
- The trade-off of tapping the main repo: `brew tap` clones the whole repo (~3 MB today). That's fine.

---

# Part B: Every release

Example values: version `1.0.0`, build `1`. Increase the build number every release.

## B1. Prepare

```bash
git status                      # clean, on main, pushed
xcodebuild -scheme PeteKM test  # green
```

## B2. Build, sign, notarize

```bash
DEVELOPMENT_TEAM=<TEAMID> scripts/release.sh 1.0.0 1
```

Use the same Team ID as `Config/Local.xcconfig`, or export `DEVELOPMENT_TEAM` in your shell profile.

Output: `build/PeteKM-1.0.0.dmg`, signed, notarized and stapled. Notarization usually takes 1–10 minutes.

Sanity check:

```bash
spctl -a -t open --context context:primary-signature -v build/PeteKM-1.0.0.dmg   # "accepted"
```

## B3. Publish the GitHub Release

```bash
git tag v1.0.0 && git push origin v1.0.0
gh release create v1.0.0 build/PeteKM-1.0.0.dmg --title "PeteKM 1.0.0" --notes "First public release."
```

The DMG URL is now `https://github.com/petemcpherson/petekm/releases/download/v1.0.0/PeteKM-1.0.0.dmg`, which matches the cask `url` pattern. The tag must be `v<version>` and the file must be named `PeteKM-<version>.dmg`.

## B4. Update the cask

```bash
shasum -a 256 build/PeteKM-1.0.0.dmg
```

In `Casks/petekm.rb`, set `version "1.0.0"` and `sha256 "<that hash>"`. Then:

```bash
git add Casks/petekm.rb
git commit -m "Release 1.0.0"
git push
```

Once this push lands, `brew upgrade` delivers the new version to existing users.

## B5. Verify

```bash
brew untap petemcpherson/petekm 2>/dev/null
brew tap petemcpherson/petekm https://github.com/petemcpherson/petekm
brew audit --cask --strict petemcpherson/petekm/petekm   # style/URL checks
brew install --cask petekm
open -a PeteKM
```

The app should open with no Gatekeeper warning. From the second release on, also test the upgrade path: keep the previous version installed, push the new cask, then run `brew update && brew upgrade petekm`.

---

# Part C: What users run

Install (the tap line runs once; it needs the full URL because the repo isn't named `homebrew-petekm`):

```bash
brew tap petemcpherson/petekm https://github.com/petemcpherson/petekm
brew install --cask petekm
```

Update:

```bash
brew upgrade
```

The DMG on the Releases page also works for a manual install, but those users get no update notices. Advertise the brew commands.

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
4. Each release:
   1. Run `~/Tools/Sparkle/bin/sign_update build/PeteKM-<v>.dmg`. It prints `edSignature` and `length`.
   2. Add an `<item>` to `appcast.xml` at the repo root. Fill in `sparkle:version` (the build number), `sparkle:shortVersionString`, `sparkle:minimumSystemVersion` 26.2, and an `enclosure` with the Release DMG URL plus the signature and length from step 1.
   3. Commit `appcast.xml`.
5. Add `auto_updates true` to the cask.

---

# Later (optional)

- **Official `homebrew/cask`.** When PeteKM is notable enough, submit a PR so users can run plain `brew install --cask petekm` without tapping. Homebrew requires meaningful GitHub stars, forks and watchers, with a higher bar for self-submitted apps. Then delete `Casks/` from this repo.
- **Automate B3–B4.** Extend `release.sh` to call `gh release create` and rewrite the cask's `version`/`sha256`.

---

# Troubleshooting

| Symptom | Cause / fix |
| --- | --- |
| `No Keychain password item found for profile: petekm-notary` | A3 not done, or done on a different Mac. |
| Notarization "Invalid" | Run `xcrun notarytool log <submission-id> --keychain-profile petekm-notary`. It is usually an unsigned nested binary or hardened runtime turned off. |
| `brew install` SHA mismatch | The cask `sha256` came from a different DMG than the one on the Release. Recompute it from the uploaded file. |
| `brew install` 404 | The tag isn't `v<version>`, or the DMG filename doesn't match `PeteKM-<version>.dmg`. |
| `brew upgrade` doesn't see the new version | The user needs `brew update` first, which normally runs automatically. Also check that the cask commit was pushed to `main`. |
| Gatekeeper warns on first launch | The DMG wasn't notarized or stapled. Re-run `release.sh` and check the `stapler validate` output. |
