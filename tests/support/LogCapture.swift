import Foundation
import Logging

/// swift-log handler that keeps every emitted record so tests can assert on it.
public final class LogCapture: LogHandler, @unchecked Sendable {
    public struct Entry: Equatable {
        public let level: Logger.Level
        public let message: String
        public let metadata: [String: String]

        public init(level: Logger.Level, message: String, metadata: [String: String] = [:]) {
            self.level = level
            self.message = message
            self.metadata = metadata
        }
    }

    private let lock = NSLock()
    private var recorded: [Entry] = []
    public var metadata: Logger.Metadata = [:]
    public var logLevel: Logger.Level = .trace

    public init() {}

    public var entries: [Entry] {
        lock.withLock { recorded }
    }

    public var logger: Logger {
        Logger(label: "test") { _ in self }
    }

    public subscript(metadataKey key: String) -> Logger.Metadata.Value? {
        get { metadata[key] }
        set { metadata[key] = newValue }
    }

    public func log(event: LogEvent) {
        let merged = metadata.merging(event.metadata ?? [:]) { _, new in new }
        let entry = Entry(
            level: event.level,
            message: event.message.description,
            metadata: merged.mapValues(\.description)
        )
        lock.withLock { recorded.append(entry) }
    }
}
