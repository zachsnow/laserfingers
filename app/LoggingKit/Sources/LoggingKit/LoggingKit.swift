import Foundation
import SwiftUI
import os.log

// MARK: - Log Entry Model

public struct LogEntry: Codable, Identifiable {
    public let id: UUID
    public let timestamp: Date
    public let category: String
    public let level: String
    public let message: String

    public init(id: UUID = UUID(), timestamp: Date = Date(), category: String, level: String, message: String) {
        self.id = id
        self.timestamp = timestamp
        self.category = category
        self.level = level
        self.message = message
    }
}

// MARK: - Log Storage

public actor LogStore {
    public static let shared = LogStore()

    private var entries: [LogEntry] = []
    private let fileURL: URL
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    public init(logFileName: String = "app-log.json") {
        encoder.outputFormatting = [.prettyPrinted]
        decoder.dateDecodingStrategy = .iso8601
        encoder.dateEncodingStrategy = .iso8601

        let baseDir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        let logsDir = baseDir.appendingPathComponent("Logs", isDirectory: true)
        try? FileManager.default.createDirectory(at: logsDir, withIntermediateDirectories: true)
        fileURL = logsDir.appendingPathComponent(logFileName)

        if let data = try? Data(contentsOf: fileURL),
           let decoded = try? decoder.decode([LogEntry].self, from: data) {
            entries = decoded
        } else {
            entries = []
        }
    }

    public func append(category: String, level: String, message: String) {
        var trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            trimmed = "<empty>"
        }
        entries.append(LogEntry(category: category, level: level, message: trimmed))
        persist()
    }

    public func allEntries() -> [LogEntry] {
        entries.sorted { $0.timestamp > $1.timestamp }
    }

    public func clear() {
        entries.removeAll()
        persist()
    }

    private func persist() {
        guard let data = try? encoder.encode(entries) else { return }
        try? data.write(to: fileURL, options: [.atomic])
    }
}

// MARK: - Persistent Logger

public struct PersistentLogger {
    private static let shouldUseOSLog: Bool = {
        let env = ProcessInfo.processInfo.environment
        return env["DISABLE_OSLOG"] == nil && env["XCTestConfigurationFilePath"] == nil
    }()

    private let logger: Logger?
    private let category: String

    public init(subsystem: String, category: String) {
        if Self.shouldUseOSLog {
            self.logger = Logger(subsystem: subsystem, category: category)
        } else {
            self.logger = nil
        }
        self.category = category
    }

    public func debug(_ message: String) {
        logger?.debug("\(message, privacy: .public)")
        record(level: "debug", message: message)
    }

    public func notice(_ message: String) {
        logger?.notice("\(message, privacy: .public)")
        record(level: "notice", message: message)
    }

    public func warning(_ message: String) {
        logger?.warning("\(message, privacy: .public)")
        record(level: "warning", message: message)
    }

    public func error(_ message: String) {
        logger?.error("\(message, privacy: .public)")
        record(level: "error", message: message)
    }

    private func record(level: String, message: String) {
        Task {
            await LogStore.shared.append(category: category, level: level, message: message)
        }
    }
}

// MARK: - Log Viewer UI

public struct LogViewerScreen: View {
    @State private var entries: [LogEntry] = []
    @State private var query: String = ""
    @State private var isLoading = false
    @State private var searchText: String = ""

    public init() {}

    public var body: some View {
        Group {
            if entries.isEmpty {
                PlaceholderView(isLoading: isLoading)
            } else if filteredEntries.isEmpty {
                SearchPlaceholder(query: searchText)
            } else {
                List(filteredEntries) { entry in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(entry.category)
                                .font(.subheadline.bold())
                            Spacer()
                            Text(entry.timestamp.formatted(date: .abbreviated, time: .standard))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Text(entry.message)
                            .font(.body)
                        Text(entry.level.uppercased())
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)
                    .contextMenu {
                        Button("Copy") {
                            #if os(iOS)
                            UIPasteboard.general.string = LogViewerScreen.format(entry: entry)
                            #elseif os(macOS)
                            let pasteboard = NSPasteboard.general
                            pasteboard.clearContents()
                            pasteboard.setString(LogViewerScreen.format(entry: entry), forType: .string)
                            #endif
                        }
                    }
                }
                .listStyle(.insetGrouped)
            }
        }
        .navigationTitle("Logs")
        .searchable(text: $searchText, placement: .navigationBarDrawer(displayMode: .always), prompt: "Search logs")
        .toolbar {
            ToolbarItemGroup(placement: .navigationBarTrailing) {
                Button {
                    Task { await refresh() }
                } label: {
                    if isLoading {
                        ProgressView()
                    } else {
                        Image(systemName: "arrow.clockwise")
                    }
                }

                Button(role: .destructive) {
                    Task {
                        await LogStore.shared.clear()
                        await refresh()
                    }
                } label: {
                    Image(systemName: "trash")
                }
            }
        }
        .task { await refresh() }
    }

    private static func format(entry: LogEntry) -> String {
        "[\(entry.timestamp.formatted(date: .abbreviated, time: .standard))] [\(entry.category)] [\(entry.level.uppercased())] \(entry.message)"
    }

    private func refresh() async {
        isLoading = true
        let newEntries = await LogStore.shared.allEntries()
        await MainActor.run {
            entries = newEntries
            isLoading = false
        }
    }

    private var filteredEntries: [LogEntry] {
        let trimmed = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return entries }
        let query = trimmed.lowercased()
        return entries.filter { entry in
            entry.category.lowercased().contains(query)
                || entry.message.lowercased().contains(query)
                || entry.level.lowercased().contains(query)
        }
    }
}

private struct PlaceholderView: View {
    let isLoading: Bool

    var body: some View {
        VStack(spacing: 12) {
            if isLoading {
                ProgressView()
            } else {
                Image(systemName: "doc.text.magnifyingglass")
                    .font(.largeTitle)
                    .foregroundStyle(.secondary)
            }
            Text(isLoading ? "Loading logs…" : "No log entries yet")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        .padding()
    }
}

private struct SearchPlaceholder: View {
    let query: String

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 32))
                .foregroundStyle(.secondary)
            Text("No matching logs")
                .font(.headline)
            let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                Text("Nothing matching \"\(trimmed)\" found.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .padding(.vertical, 48)
        .frame(maxWidth: .infinity, alignment: .center)
    }
}
