# Distribution & Updates

Spec §20.1–§20.2. PeteKM ships **outside** the Mac App Store: Developer ID signing,
Apple notarization, a `.dmg`, and Sparkle for in-app updates.

## Build settings (already set in `project.pbxproj`)

| Setting | Value | Why |
| --- | --- | --- |
| `ENABLE_APP_SANDBOX` | `NO` | The app shells out to `git`, `code`, and Terminal (§12, §15, §17). |
| `ENABLE_HARDENED_RUNTIME` | `YES` | Required for notarization. |
| `ENABLE_USER_SELECTED_FILES` | `readwrite` | The PeteKM folder is user-chosen and written to. |
| `PRODUCT_BUNDLE_IDENTIFIER` | `com.petekm.PeteKM` | Stable identity for update feeds. |

Release archives must be signed with a **Developer ID Application** certificate, not
the development certificate used for local debug builds.

## Sparkle

Sparkle is added as a Swift Package (`https://github.com/sparkle-project/Sparkle`,
2.x) on the `PeteKM` target. All Sparkle code lives behind `#if canImport(Sparkle)`
in `PeteKM/Settings/UpdateController.swift`, so a checkout without the package still
builds, runs, and captures notes — updates simply report
"This build doesn't check for updates." An update mechanism must never gate capture.

Add these Info.plist keys to the app target (Build Settings → `INFOPLIST_KEY_*`, or a
custom Info.plist) for a release build:

| Key | Value |
| --- | --- |
| `SUFeedURL` | `https://<host>/petekm/appcast.xml` |
| `SUPublicEDKey` | The EdDSA public key printed by Sparkle's `generate_keys` |
| `SUEnableAutomaticChecks` | `YES` (the user can turn it off in Settings → Updates) |

`UpdateController.feedURL` reads `SUFeedURL`; when it is absent or empty the Updates
pane and the "Check for Updates…" menu item stay inert. Updates are never installed
without approval: `automaticallyDownloadsUpdates` is forced to `false` before a check.

## Release

```bash
scripts/release.sh 1.0.0 12        # marketing version, build number
```

The script archives, exports with Developer ID, notarizes, staples, and builds a
`.dmg` into `build/`. It expects:

- `DEVELOPMENT_TEAM` — Apple Developer team ID
- A notarization keychain profile named `petekm-notary`, created once with:

```bash
xcrun notarytool store-credentials petekm-notary \
  --apple-id "<apple-id>" --team-id "<team-id>" --password "<app-specific-password>"
```

After notarization, sign the appcast with Sparkle's `sign_update` and publish the
`.dmg` plus `appcast.xml` at `SUFeedURL`.
