# iOS / watchOS Source

This directory contains SwiftUI source files for three Xcode targets:

```text
Shared/       Models, shared UserDefaults store, HTTP client
iPhoneApp/    iPhone configuration and sync UI
WatchApp/     Apple Watch dashboard
WidgetExtension/ iPhone small and medium Widget
```

## Xcode setup

This directory now includes a ready-to-open Xcode project:

```text
CodingQuota.xcodeproj
```

Before opening Xcode, configure local identifiers from the repo root:

```bash
scripts/configure-ios-identifiers.sh --bundle-id com.yourname.CodexQuota
```

Then choose your Apple Team in Xcode for the iPhone app, Watch app, and Widget
targets. The script updates Bundle IDs, App Group IDs, and background refresh
identifiers; it does not configure signing certificates.

For the full device runbook, see:

```text
../docs/setup.md
```

The manual setup notes below remain useful if you recreate the project from scratch.

1. Create a new Xcode project: iOS App with a watchOS companion app.
2. Add files from `Sources/Shared` to app, Watch, and Widget targets.
3. Add `Sources/iPhoneApp` to the iPhone target.
4. Add `Sources/WatchApp` to the Watch App target.
5. Add `Sources/WidgetExtension` to a Widget Extension target.
6. For first personal-device installs, leave App Groups disabled unless your developer team supports them.
7. If you enable App Groups later, set the same group ID on all targets and edit `AppConstants.appGroupID` in `UsageModels.swift`.
8. Signing: use your Apple ID/team for personal-device install.

## Runtime flow

```text
iPhone app fetches http://Mac-IP:8787/watch
          ↓
Saves compact JSON locally, or to App Group when enabled
          ↓
Sends snapshot to Watch via WatchConnectivity
          ↓
Watch App displays detail

The iPhone Widget reads the same App Group snapshot. It does not fetch from the
Mac Agent directly; iOS decides when Widget timelines reload.

When the pairing config has reached the Watch, the Watch App also tries a
foreground direct refresh from the Mac Agent before falling back to the last
snapshot sent by iPhone.
```

## Reminder

The Watch App tries a direct foreground refresh when it can reach the Mac Agent, then falls back to iPhone/WatchConnectivity and the latest available snapshot.
