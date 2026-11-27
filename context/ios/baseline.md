# Mac baseline for the iOS work

Recorded 2026-11-26 in Phase 0 (`context/ios/plan.md` §0.1). The Mac regression gate
compares every later phase against this file. Keep it unchanged; add a dated section if a
baseline has to be re-taken (for example after an Xcode or macOS update).

- Base commit: `9bfba7f` (Release 1.1.1), Xcode 26.2 (17C52), macOS SDK 26.2.
- Scheme `PeteKM` is now shared (`PeteKM.xcodeproj/xcshareddata/xcschemes/PeteKM.xcscheme`).
  It builds `PeteKM` and tests `PeteKMTests` + `PeteKMUITests`, the same as the
  auto-created scheme it replaces.

## Tests

Command (the release gate, `context/DISTRIBUTION.md` §2):

```bash
xcodebuild -scheme PeteKM test -only-testing:PeteKMTests -parallel-testing-enabled NO
```

| When | Passing tests |
|---|---|
| Before Phase 0 (1.1.1 as shipped) | 252 in 14 suites |
| After Phase 0 (push-race retry + highlighter snapshot) | **259** in 14 suites |

Phase 0 added 7 tests: 6 in `GitSyncTests` (push-race retry) and
`highlighterMatchesTheRecordedBaseline` (`HighlighterSnapshotTests`, fixture
`PeteKMTests/Fixtures/highlighter-baseline.json`). Later phases compare against 259.

## Release archive

Command: `xcodebuild -scheme PeteKM -configuration Release archive -archivePath <outside the repo>`.
Version 1.1.1 (6). Archive kept outside the repo.

Sparkle: **not embedded** — it is deferred (`context/DISTRIBUTION.md`). The gate's
"Sparkle still embedded" check reads "Sparkle still absent" until that changes.

### `.app` file list (`find PeteKM.app -type f | sort`)

```
PeteKM.app/Contents/_CodeSignature/CodeResources
PeteKM.app/Contents/Info.plist
PeteKM.app/Contents/MacOS/PeteKM
PeteKM.app/Contents/PkgInfo
PeteKM.app/Contents/Resources/AppIcon.icns
PeteKM.app/Contents/Resources/Assets.car
```

### `plutil -p Contents/Info.plist`

```
{
  "BuildMachineOSBuild" => "25D125"
  "CFBundleDevelopmentRegion" => "en"
  "CFBundleExecutable" => "PeteKM"
  "CFBundleIconFile" => "AppIcon"
  "CFBundleIconName" => "AppIcon"
  "CFBundleIdentifier" => "com.petekm.PeteKM"
  "CFBundleInfoDictionaryVersion" => "6.0"
  "CFBundleName" => "PeteKM"
  "CFBundlePackageType" => "APPL"
  "CFBundleShortVersionString" => "1.1.1"
  "CFBundleSupportedPlatforms" => [
    0 => "MacOSX"
  ]
  "CFBundleVersion" => "6"
  "DTCompiler" => "com.apple.compilers.llvm.clang.1_0"
  "DTPlatformBuild" => "25C57"
  "DTPlatformName" => "macosx"
  "DTPlatformVersion" => "26.2"
  "DTSDKBuild" => "25C57"
  "DTSDKName" => "macosx26.2"
  "DTXcode" => "2620"
  "DTXcodeBuild" => "17C52"
  "LSMinimumSystemVersion" => "26.2"
}
```

### Entitlements (`codesign -d --entitlements -`)

```
[Dict]
	[Key] com.apple.security.files.user-selected.read-write
	[Value]
		[Bool] true
```

### Linked libraries (`otool -L`, arm64 slice; x86_64 is identical)

```
/System/Library/Frameworks/Foundation.framework/Versions/C/Foundation (compatibility version 300.0.0, current version 4201.0.0)
/usr/lib/libobjc.A.dylib (compatibility version 1.0.0, current version 228.0.0)
/usr/lib/libSystem.B.dylib (compatibility version 1.0.0, current version 1356.0.0)
/System/Library/Frameworks/AppKit.framework/Versions/C/AppKit (compatibility version 45.0.0, current version 2685.30.107)
/System/Library/Frameworks/Carbon.framework/Versions/A/Carbon (compatibility version 2.0.0, current version 170.0.0)
/System/Library/Frameworks/CoreFoundation.framework/Versions/A/CoreFoundation (compatibility version 150.0.0, current version 4201.0.0)
/System/Library/Frameworks/CryptoKit.framework/Versions/A/CryptoKit (compatibility version 1.0.0, current version 1.0.0)
/System/Library/Frameworks/Network.framework/Versions/A/Network (compatibility version 1.0.0, current version 5569.60.39)
/System/Library/Frameworks/SwiftUI.framework/Versions/A/SwiftUI (compatibility version 1.0.0, current version 7.2.5)
/usr/lib/swift/libswiftCore.dylib (compatibility version 0.0.0, current version 0.0.0)
/usr/lib/swift/libswiftCoreFoundation.dylib (compatibility version 1.0.0, current version 120.100.0)
/usr/lib/swift/libswiftCoreImage.dylib (compatibility version 1.0.0, current version 2.2.0, weak)
/usr/lib/swift/libswiftDarwin.dylib (compatibility version 1.0.0, current version 347.40.2)
/usr/lib/swift/libswiftDispatch.dylib (compatibility version 1.0.0, current version 56.0.0)
/usr/lib/swift/libswiftIOKit.dylib (compatibility version 1.0.0, current version 1.0.0, weak)
/usr/lib/swift/libswiftMetal.dylib (compatibility version 1.0.0, current version 370.64.2, weak)
/usr/lib/swift/libswiftOSLog.dylib (compatibility version 1.0.0, current version 10.0.0, weak)
/usr/lib/swift/libswiftObjectiveC.dylib (compatibility version 1.0.0, current version 951.1.0)
/usr/lib/swift/libswiftObservation.dylib (compatibility version 1.0.0, current version 0.0.0)
/usr/lib/swift/libswiftQuartzCore.dylib (compatibility version 1.0.0, current version 5.0.0, weak)
/usr/lib/swift/libswiftSpatial.dylib (compatibility version 1.0.0, current version 1.0.0, weak)
/usr/lib/swift/libswiftUniformTypeIdentifiers.dylib (compatibility version 1.0.0, current version 877.2.4, weak)
/usr/lib/swift/libswiftXPC.dylib (compatibility version 1.0.0, current version 105.0.14, weak)
/usr/lib/swift/libswift_Builtin_float.dylib (compatibility version 1.0.0, current version 0.0.0, weak)
/usr/lib/swift/libswift_Concurrency.dylib (compatibility version 1.0.0, current version 0.0.0)
/usr/lib/swift/libswiftos.dylib (compatibility version 1.0.0, current version 1076.40.2)
/usr/lib/swift/libswiftsimd.dylib (compatibility version 1.0.0, current version 23.0.0, weak)
```

Universal binary: `x86_64` + `arm64`.
