# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Laserfingers is an iOS/iPad multitouch game where players dodge sweeping/rotating lasers while holding buttons to "fill gates" and unlock levels. Built with SwiftUI + SpriteKit.

Core mechanic: Touch and hold buttons while avoiding laser beams. If a laser touches your finger, you get zapped. Fill all required buttons to complete the level.

## Build and Development Commands

### Building
```bash
./build.sh
```
Builds for iOS Simulator by default. Falls back to device build if simulator unavailable. Output logged to `build.log`.

The build system injects a `BUILD_TIMESTAMP` environment variable (ISO 8601 format) into the build process, accessible via `BuildInfo.swift`.

### Deploying to Device
```bash
DEVICE_ID=<device-id> ./deploy.sh
```
Builds and installs to a physical iOS device using `devicectl`. Defaults to Debug configuration. Set `CONFIGURATION=Release` to override.

### Running in Simulator
After building, launch with:
```bash
xcrun simctl launch booted com.yourorg.laserfingers
```

### Xcode
Open `app/Laserfingers.xcodeproj` in Xcode for standard development workflow.

## Architecture

### SwiftUI + SpriteKit Hybrid
- **SwiftUI** handles navigation, menus, settings, and HUD overlays
- **SpriteKit** powers all gameplay rendering and physics
- Bridge: `SpriteView` embeds SpriteKit scenes into SwiftUI views

### Key Components

**AppCoordinator** (`AppDelegate.swift`)
- Central navigation controller managing screen transitions
- Owns active game state (`GameRuntime`) and level editor state (`LevelEditorViewModel`)
- Handles level loading, progress tracking, and error states

**Scene Hierarchy**
- `LevelSceneBase` - Base class for rendering levels; handles button/laser geometry, timeline playback, touch detection
- `LaserGameScene` (via `GameScene.swift`) - Gameplay scene; detects laser hits, manages lives/touches, win/lose conditions
- `LevelEditorScene` - Editor scene; delegates taps for placing/selecting buttons and lasers
- `MenuBackgroundScene` - Animated background for menus

**Level System**
- Levels defined as JSON files in `app/Laserfingers/Levels/<Pack Name>/<level>.json`
- `LevelFormat.swift` defines the complete schema: buttons, lasers (sweeper/rotor/segment), hit areas, effects, cadence, timing
- `LevelRepository.swift` loads levels from bundle and user-downloaded packs
- `LevelPack` groups levels by directory; packs appear in level select screen

**Coordinate System**
All level geometry uses `NormalizedPoint` (0-1 range) relative to the shorter screen dimension to support multiple device sizes (iPhone, iPad, iPad Mini).

**Button Logic**
- Buttons have `HitArea` shapes (circle/rectangle/capsule/polygon) and can require `any` or `all` areas to be touched
- Buttons charge over time when touched, drain when released (configurable via `Timing`)
- Buttons can trigger `Effect`s (turn on/off/toggle lasers) on touch/release/turnedOn/turnedOff events
- Required buttons must be filled to win; optional buttons can control level state

**Laser Types**
- `Sweeper`: travels back and forth between two endpoints
- `Rotor`: rotates around a center point at constant speed
- `Segment`: static laser between two points
- All lasers support cadence (blinking on/off patterns)

**Progress & Storage**
- `ProgressStore` tracks completion state and unlocked levels
- Downloaded levels stored in Application Support, excluded from backup
- Settings (sound, haptics, advanced mode) persisted to UserDefaults

**Level Editor**
- In-app editor for creating/modifying levels (enabled via advanced mode)
- `LevelEditorViewModel` manages editing state, serialization to JSON
- `LevelEditorView` provides UI controls for placing/configuring game objects
- Can import/export levels via share sheet

### File Organization
```
app/Laserfingers/
  ├── AppDelegate.swift              # App coordinator, navigation, lifecycle
  ├── GameViewController.swift       # Main SwiftUI views, menus, gameplay UI
  ├── GameScene.swift                # Gameplay scene (LaserGameScene)
  ├── LevelSceneBase.swift          # Shared scene rendering logic
  ├── LevelEditorScene.swift        # Editor scene
  ├── LevelEditorView.swift         # Editor UI
  ├── LevelEditorViewModel.swift    # Editor state management
  ├── LevelFormat.swift             # Level JSON schema
  ├── LevelRepository.swift         # Level loading
  ├── LevelPack.swift               # Level pack metadata
  ├── ProgressStore.swift           # Game progress persistence
  ├── Haptics.swift                 # Haptic feedback
  ├── DeviceProfile.swift           # Device detection (iPhone/iPad)
  ├── TouchCapabilities.swift       # Max simultaneous touches
  └── Levels/                       # Bundled level JSON files
```

## Code Style

- Swift 5.9+, SwiftUI for UI, SpriteKit for rendering
- 4-space indentation
- `camelCase` for properties/functions, `PascalCase` for types
- Prefer `struct` over `class` for value types
- Use `guard let` for optional unwrapping in critical paths
- Keep files under ~300 lines; extract helpers when needed

## Level JSON Format

Levels are declarative JSON files. Key fields:
- `id`, `title`, `description`: metadata
- `devices`: optional array restricting to iPhone/iPad/iPad Mini
- `maxTouches`: optional touch limit override
- `buttons`: array of button definitions with `hitAreas`, `timing`, `effects`
- `lasers`: array of laser definitions (sweeper/rotor/segment)
- `unlocks`: array of level IDs unlocked upon completion

See `LevelFormat.swift` for complete schema with inline documentation.

## Testing

No automated test suite currently exists. Manual testing via simulator/device required for gameplay validation. Verify:
- Touch detection accuracy
- Laser collision detection
- Button fill/drain timing
- Win/lose conditions
- Level progression/unlocking

## Device Support

- iOS 15.0+
- iPhone and iPad (universal binary)
- Multitouch required (tested up to 11 simultaneous touches on iPad Pro)
- Haptics via UIImpactFeedbackGenerator

## Deployment Notes

- Code signing managed by Xcode automatic signing
- Bundle identifier configured in `Info.plist`
- Build timestamp injected via `BUILD_TIMESTAMP` environment variable
- DerivedData path: `<repo>/DerivedData` (gitignored)
