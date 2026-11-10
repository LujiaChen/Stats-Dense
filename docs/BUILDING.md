# Building Stats Dense

## Prerequisites

- macOS and a full Xcode installation with the macOS SDK.
- Xcode command-line tools selected with `xcode-select`.
- No additional package manager or third-party dependency is required for Dense.

The source retains Stats' macOS 12 minimum. Local validation used Xcode 27.0, macOS 27.3, and an Apple M5 MacBook Air. Other SDKs, macOS releases, and hardware have not all been tested.

## Local app

From the repository root:

```sh
./Scripts/build-dense.sh
```

Optional arguments select the derived-data directory and output directory:

```sh
./Scripts/build-dense.sh /tmp/stats-dense-build /tmp/stats-dense-output
```

The output is `Stats Dense.app`, `LICENSE`, `LICENSE-LevelDB.txt`, and `NOTICE.md`. The script refuses to overwrite an existing app. It builds the existing Xcode project, removes the optional WidgetKit extension from this local preview package, sets the Dense bundle identity, signs ad hoc, and verifies the result. It does not alter the project signing team, install a privileged helper, change macOS permissions, or edit launch-at-login settings.

The raw Xcode product is still named `Stats.app`. Use the helper's output for the independent Dense identity and fork-specific update behavior.

## Xcode

Open `Stats.xcodeproj` and select the **Stats** scheme. Dense is a display mode in the existing application, not a separate data collection target. Upstream code and assets remain under their original target names.

## Presentation tests

```sh
xcodebuild -project Stats.xcodeproj -scheme Stats   -configuration Debug -destination 'platform=macOS'   -derivedDataPath .build/tests CODE_SIGNING_ALLOWED=NO   -only-testing:Tests/CombinedTests test
```

The tests cover missing values, 9%/10%/100% transitions, fixed allocation, complete percentage rendering, label grouping, row bounds, Light/Dark rendering, unit preferences, mode persistence, and snapshot delivery. The live hardware case skips unless `STATS_DENSE_HARDWARE_TEST=1` is provided to the test host and CPU/GPU/RAM/Sensors are configured. Use an isolated test profile for live tests; do not overwrite a user's preferences.

## Release packaging

```sh
cd dist
ditto -c -k --sequesterRsrc --keepParent 'Stats Dense.app' Stats-Dense.app.zip
```

Include the provided license and notice files when distributing binaries. A distributable release should state its signing/notarization status explicitly. The project's preview is ad-hoc signed, not notarized. Do not reuse upstream's Developer ID, signing credentials, or notarization configuration.

The repository workflow compiles the app and test targets. Real sensor availability, native popup interaction, and energy measurements still require a physical Mac; a CI build is not evidence of those behaviors.
