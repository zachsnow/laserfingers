# LoggingKit Integration Guide

This guide shows you how to integrate LoggingKit into another Swift/SwiftUI app.

## Quick Start (5 minutes)

### Step 1: Copy the Package

Copy the entire `LoggingKit` folder to your new project directory.

```bash
cp -r /path/to/gernal/app/LoggingKit /path/to/your-app/
```

### Step 2: Add to Xcode

1. Open your Xcode project
2. Go to **File > Add Package Dependencies...**
3. Click **Add Local...** button
4. Select the `LoggingKit` folder you just copied
5. Make sure your app target is selected
6. Click **Add Package**

### Step 3: Use in Your Code

Create a logging configuration file (e.g., `Logging.swift`):

```swift
import LoggingKit

enum AppLog {
    static let network = PersistentLogger(
        subsystem: "com.yourcompany.yourapp",
        category: "Network"
    )
    static let database = PersistentLogger(
        subsystem: "com.yourcompany.yourapp",
        category: "Database"
    )
    static let ui = PersistentLogger(
        subsystem: "com.yourcompany.yourapp",
        category: "UI"
    )
}
```

### Step 4: Start Logging

```swift
// Anywhere in your code
AppLog.network.debug("Starting API request")
AppLog.network.notice("API request completed")
AppLog.network.warning("API request slow")
AppLog.network.error("API request failed")
```

### Step 5: Add Log Viewer to Your App

In your settings screen or debug menu:

```swift
import SwiftUI
import LoggingKit

struct SettingsView: View {
    var body: some View {
        NavigationView {
            List {
                // ... other settings ...

                NavigationLink {
                    LogViewerScreen()
                } label: {
                    Label("View Logs", systemImage: "doc.text.magnifyingglass")
                }
            }
            .navigationTitle("Settings")
        }
    }
}
```

## Complete Example App

Here's a minimal SwiftUI app with LoggingKit integrated:

```swift
import SwiftUI
import LoggingKit

// 1. Define your loggers
enum AppLog {
    static let app = PersistentLogger(
        subsystem: "com.example.myapp",
        category: "App"
    )
}

// 2. Main app
@main
struct MyApp: App {
    init() {
        AppLog.app.notice("App launched")
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}

// 3. Main view
struct ContentView: View {
    var body: some View {
        NavigationView {
            VStack(spacing: 20) {
                Text("My App")
                    .font(.largeTitle)

                Button("Log Something") {
                    AppLog.app.debug("Button tapped")
                }

                NavigationLink("View Logs") {
                    LogViewerScreen()
                }
            }
            .navigationTitle("Home")
        }
    }
}
```

## Advanced Usage

### Custom Log File Name

If you want to use a different log file name (default is `app-log.json`):

Note: The default `LogStore.shared` uses `app-log.json`. To customize, you'd need to modify the LoggingKit source or use the initializer parameter.

### Multiple Subsystems

You can organize logs by subsystem for larger apps:

```swift
enum CoreLog {
    static let auth = PersistentLogger(
        subsystem: "com.example.myapp.core",
        category: "Authentication"
    )
    static let storage = PersistentLogger(
        subsystem: "com.example.myapp.core",
        category: "Storage"
    )
}

enum UILog {
    static let navigation = PersistentLogger(
        subsystem: "com.example.myapp.ui",
        category: "Navigation"
    )
    static let animations = PersistentLogger(
        subsystem: "com.example.myapp.ui",
        category: "Animations"
    )
}
```

### Accessing Logs Programmatically

```swift
import LoggingKit

// Get all entries
Task {
    let entries = await LogStore.shared.allEntries()
    print("Total logs: \(entries.count)")
}

// Clear logs
Task {
    await LogStore.shared.clear()
}

// Add custom entry
Task {
    await LogStore.shared.append(
        category: "Custom",
        level: "info",
        message: "Something happened"
    )
}
```

### Disable OS Log in Tests

Set the `DISABLE_OSLOG` environment variable in your test scheme:

1. Edit your test scheme
2. Go to **Arguments** tab
3. Add environment variable: `DISABLE_OSLOG = 1`

## Customization

### Change Log File Location

Edit `LogStore.swift` in LoggingKit to change the storage location:

```swift
// Current location: ~/Library/Application Support/Logs/app-log.json

// Example: Change to a custom folder
let logsDir = baseDir.appendingPathComponent("MyAppLogs", isDirectory: true)
```

### Add New Log Levels

Edit `PersistentLogger.swift` to add custom log levels:

```swift
public func critical(_ message: String) {
    logger?.critical("\(message, privacy: .public)")
    record(level: "critical", message: message)
}
```

### Customize UI

The `LogViewerScreen` is fully customizable. You can:
- Modify colors and fonts
- Add filters by category or level
- Add export to file functionality
- Customize the toolbar

## Troubleshooting

### Build Errors

**Error: No such module 'LoggingKit'**
- Make sure you added LoggingKit as a package dependency to your target
- Clean build folder (Cmd+Shift+K) and rebuild

**Error: Cannot find 'LogViewerScreen' in scope**
- Make sure you've imported LoggingKit: `import LoggingKit`
- Check that LoggingKit is added to your target's frameworks

### Runtime Issues

**Logs not appearing in viewer**
- Check that you're actually logging (add a test log)
- Verify the log file exists at: `~/Library/Application Support/Logs/app-log.json`
- Try refreshing the log viewer

**OS Log not appearing in Console.app**
- Check that `DISABLE_OSLOG` environment variable is not set
- Verify you're not running tests (OS Log is auto-disabled in tests)

## File Structure

```
LoggingKit/
├── Package.swift
├── README.md
├── INTEGRATION_GUIDE.md (this file)
└── Sources/
    └── LoggingKit/
        └── LoggingKit.swift
```

All functionality is in a single file (`LoggingKit.swift`) for maximum portability.

## What's Included

The `LoggingKit.swift` file contains:

1. `LogEntry` - Data model for log entries
2. `LogStore` - Actor-based storage manager
3. `PersistentLogger` - High-level logging interface
4. `LogViewerScreen` - SwiftUI view for browsing logs
5. Helper views - Placeholder and search empty states

Total: ~260 lines of well-documented Swift code

## License

This package is designed to be freely portable and reusable. Use it in any project without restriction.
