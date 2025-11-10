# Repository Guidelines

## Project Structure & Module Organization
Top-level assets live in `laserfingers/`; the active Xcode project sits in `laserfingers/laserfingers.xcodeproj`, and all SpriteKit source files reside under `laserfingers/laserfingers`. `GameViewController.swift` bootstraps the app, `GameScene.swift` owns gameplay logic, and the `.sks` scene files in the same directory store layout metadata that should remain synchronized with the corresponding Swift nodes. Place new textures in `Assets.xcassets`, and keep localized resources in `Base.lproj` so Interface Builder can pick them up automatically.

## Build, Test, and Development Commands
Use Xcode for day-to-day work, or run headless builds from the repo root:
```
cd laserfingers/laserfingers
xcodebuild -project laserfingers.xcodeproj -scheme laserfingers -sdk iphonesimulator build
```
Run the app in a simulator with `xcrun simctl launch booted com.yourorg.laserfingers` after building. If you add command-line previews, prefer `swift run --package-path laserfingers/laserfingers` so dependencies stay localized.

## Coding Style & Naming Conventions
Write Swift 5.9 code using Xcode’s default 4-space indentation and `camelCase` for properties/functions (`laserBeamCount`), `PascalCase` for types (`LaserBladeManager`), and uppercase snake case for constants bridged into Obj-C (`LASER_NODE_KEY`). Favor `struct` over `class` when state can stay value-type, and gate SpriteKit node lookups with `guard let` to fail fast during development builds. Keep files under ~300 lines by extracting scene helpers into dedicated files within the same directory.

## Testing Guidelines
There is no XCTest target yet, so gameplay tweaks must be covered with manual simulator passes that verify spawn timing, touch input, and frame rate. When you add tests, follow the `FeatureNameTests` naming (e.g., `LaserComboTests`) and drive them via `xcodebuild test -scheme laserfingers -destination 'platform=iOS Simulator,name=iPhone 15'`. Snapshot tests should save fixtures under `Tests/__Snapshots__` to keep sprite reference images version-controlled.

## Commit & Pull Request Guidelines
Commits should mirror the existing history: a short imperative subject under 50 characters (“Add combo meter HUD”), followed by detail if needed. Reference issue IDs (`Fix #12`) whenever closing bugs. Pull requests must describe gameplay impact, any asset changes (screenshots of new sprites help reviewers), and manual test notes. Request reviews from another SpriteKit contributor before merging; keep branches up to date with `main` and squash when the diff is ready.

## Security & Configuration Tips
Do not commit signing certificates or provisioning profiles; let Xcode manage them via automatic signing tied to your personal team ID. Keep bundle identifiers in sync between `Info.plist` and the Simulator command above. If you add analytics or network calls, guard credentials with Xcode build settings and document the required `.xcconfig` entries in this file.
