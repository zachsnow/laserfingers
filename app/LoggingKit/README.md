# LoggingKit

A standalone, reusable Swift package for comprehensive logging with in-app log viewing capabilities.

## Features

- **Structured Logging**: Log entries with categories, levels (debug, notice, warning, error), and timestamps
- **Persistent Storage**: JSON-based storage to Application Support directory
- **Thread-Safe**: Actor-based `LogStore` for safe concurrent access
- **Dual Logging**: Logs to both OS Log and custom JSON storage
- **In-App Viewer**: Beautiful SwiftUI view for browsing, searching, filtering, and exporting logs
- **Search & Filter**: Multi-field search across category, message, and level
- **Export**: Copy individual log entries to clipboard (iOS & macOS)
- **Clear Logs**: Destructive action to clear all stored logs

## Requirements

- iOS 17.0+ / macOS 14.0+
- Swift 5.9+

## Installation

### Swift Package Manager

Add LoggingKit as a local package dependency:

1. In Xcode, go to File > Add Package Dependencies
2. Click "Add Local..." and select the `LoggingKit` folder
3. Add `LoggingKit` to your target's dependencies

Or add it to your `Package.swift`:

```swift
dependencies: [
    .package(path: "../LoggingKit")
]
```

### Manual Installation

Simply copy the entire `LoggingKit` folder to your project.

## Usage

### Basic Logging

```swift
import LoggingKit

// Create a logger for your component
let logger = PersistentLogger(
    subsystem: "com.yourcompany.yourapp",
    category: "NetworkManager"
)

// Log at different levels
logger.debug("Fetching user data")
logger.notice("User logged in successfully")
logger.warning("Slow network detected")
logger.error("Failed to connect to server")
```

### Organized Logging with Enum

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

// Usage
AppLog.network.debug("API request started")
AppLog.database.notice("Database initialized")
AppLog.ui.warning("View rendering slow")
```

### In-App Log Viewer

Add the log viewer to your SwiftUI app:

```swift
import SwiftUI
import LoggingKit

struct SettingsView: View {
    var body: some View {
        NavigationLink {
            LogViewerScreen()
        } label: {
            Label("View Logs", systemImage: "doc.text.magnifyingglass")
        }
    }
}
```

### Custom Log File Name

By default, logs are stored in `app-log.json`. You can customize this:

```swift
// Create a custom log store instance
let customLogStore = LogStore(logFileName: "myapp-debug.json")
```

Note: The singleton `LogStore.shared` uses the default filename.

### Accessing Logs Programmatically

```swift
import LoggingKit

// Get all log entries (sorted newest first)
let entries = await LogStore.shared.allEntries()

// Clear all logs
await LogStore.shared.clear()

// Add a log entry directly
await LogStore.shared.append(
    category: "Custom",
    level: "info",
    message: "Custom log message"
)
```

### Environment Variables

- `DISABLE_OSLOG`: Set to any value to disable OS Log output (useful for testing)

## Architecture

### Components

1. **LogEntry**: Codable struct representing a single log entry
   - `id`: UUID
   - `timestamp`: Date
   - `category`: String
   - `level`: String (debug, notice, warning, error)
   - `message`: String

2. **LogStore**: Thread-safe actor for managing log storage
   - Singleton instance (`shared`)
   - JSON persistence to Application Support/Logs/
   - Automatic loading on initialization
   - Atomic file writes

3. **PersistentLogger**: High-level logging interface
   - Dual output to OS Log and LogStore
   - Four log levels: debug, notice, warning, error
   - Configurable subsystem and category

4. **LogViewerScreen**: SwiftUI view for browsing logs
   - List view with search
   - Copy to clipboard
   - Refresh and clear actions
   - Empty and search placeholder states

## File Storage

Logs are stored in JSON format at:
- iOS: `~/Library/Application Support/Logs/app-log.json`
- macOS: `~/Library/Application Support/Logs/app-log.json`

## Example Log Format

```json
[
  {
    "id": "550e8400-e29b-41d4-a716-446655440000",
    "timestamp": "2024-11-13T10:30:45Z",
    "category": "Network",
    "level": "error",
    "message": "Failed to fetch user profile: timeout"
  }
]
```

## License

This package is designed to be easily portable between projects. Feel free to use, modify, and distribute as needed.

## Integration with Your App

To integrate LoggingKit into your app:

1. Add the package to your Xcode project
2. Import `LoggingKit` where needed
3. Create category-specific loggers
4. Add `LogViewerScreen` to your settings or debug menu
5. Start logging!

## Tips

- Use descriptive categories to organize logs by component/feature
- Use appropriate log levels (debug for verbose, error for critical issues)
- Add the log viewer to a settings screen for easy access
- Clear logs periodically in production to avoid large file sizes
- Use `DISABLE_OSLOG=1` in test environments to avoid console spam
