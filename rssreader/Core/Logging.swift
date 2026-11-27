import os

/// Shared loggers. Use `privacy: .public` only for values that are safe to read in a sysdiagnose
/// (error descriptions, counts); leave URLs, hosts, and account names at the default private level.
nonisolated enum Log {
    private static let subsystem = "com.seferdesign.rssreader"

    static let network = Logger(subsystem: subsystem, category: "network")
    static let storage = Logger(subsystem: subsystem, category: "storage")
    static let sync = Logger(subsystem: subsystem, category: "sync")
}
