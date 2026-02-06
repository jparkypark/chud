import Foundation
import SQLite3

/// Represents a single cell in the activity heatmap
struct HeatmapCell {
    let dayOfWeek: Int  // 0 = Sunday, 6 = Saturday
    let hour: Int       // 0-23
    let count: Int
}

/// Represents time spent on a project
struct ProjectTime {
    let cwd: String
    let totalMinutes: Int
}

/// Represents daily usage cost
struct DailyUsage {
    let date: String
    let cost: Double
    let inputTokens: Int
    let outputTokens: Int
}

/// Represents a pace snapshot
struct PaceSnapshot {
    let timestamp: Int64
    let pace: Double
}

/// Represents a usage snapshot (cumulative cost at point in time)
struct UsageSnapshot {
    let timestamp: Int64
    let cost: Double
}

/// Client for reading session data from the shared SQLite database.
/// Uses the SQLite3 C API directly for maximum compatibility.
class DatabaseClient {
    private var db: OpaquePointer?
    private let dbPath: String

    init() {
        let homeDir = FileManager.default.homeDirectoryForCurrentUser
        dbPath = homeDir.appendingPathComponent(".claude/statusline-usage.db").path
    }

    /// Opens a connection to the database.
    /// - Returns: `true` if successful, `false` otherwise.
    func open() -> Bool {
        guard sqlite3_open(dbPath, &db) == SQLITE_OK else {
            print("[chud] Failed to open database at \(dbPath)")
            return false
        }
        return true
    }

    /// Closes the database connection.
    func close() {
        if db != nil {
            sqlite3_close(db)
            db = nil
        }
    }

    /// Deletes sessions with last_seen_at older than the given timestamp.
    /// - Parameter timestampMs: Unix timestamp in milliseconds
    /// - Returns: Number of rows deleted
    @discardableResult
    func deleteSessionsOlderThan(_ timestampMs: Int64) -> Int {
        guard open() else { return 0 }
        defer { close() }

        let query = "DELETE FROM hud_sessions WHERE last_seen_at < ?"
        var statement: OpaquePointer?

        guard sqlite3_prepare_v2(db, query, -1, &statement, nil) == SQLITE_OK else {
            print("[chud] Failed to prepare delete query")
            return 0
        }
        defer { sqlite3_finalize(statement) }

        sqlite3_bind_int64(statement, 1, timestampMs)

        if sqlite3_step(statement) == SQLITE_DONE {
            let deleted = Int(sqlite3_changes(db))
            if deleted > 0 {
                print("[chud] Cleaned up \(deleted) stale session(s)")
            }
            return deleted
        }
        return 0
    }

    /// Retrieves all sessions from the database, ordered by most recent activity.
    /// - Returns: Array of Session objects, empty if database cannot be opened or query fails.
    func getAllSessions() -> [Session] {
        guard open() else { return [] }
        defer { close() }

        var sessions: [Session] = []
        let query = """
            SELECT cwd, git_branch, status, first_seen_at, last_seen_at
            FROM hud_sessions
            ORDER BY last_seen_at DESC
        """

        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, query, -1, &statement, nil) == SQLITE_OK else {
            print("[chud] Failed to prepare query")
            return []
        }
        defer { sqlite3_finalize(statement) }

        while sqlite3_step(statement) == SQLITE_ROW {
            // Column 0: cwd (TEXT PRIMARY KEY)
            let cwd = String(cString: sqlite3_column_text(statement, 0))

            // Column 1: git_branch (TEXT, can be NULL)
            let gitBranch: String?
            if let gitBranchPtr = sqlite3_column_text(statement, 1) {
                gitBranch = String(cString: gitBranchPtr)
            } else {
                gitBranch = nil
            }

            // Column 2: status (TEXT, defaults to "unknown")
            let status: String
            if let statusPtr = sqlite3_column_text(statement, 2) {
                status = String(cString: statusPtr)
            } else {
                status = "unknown"
            }

            // Column 3: first_seen_at (INTEGER NOT NULL)
            let firstSeenAt = sqlite3_column_int64(statement, 3)

            // Column 4: last_seen_at (INTEGER NOT NULL)
            let lastSeenAt = sqlite3_column_int64(statement, 4)

            let session = Session(
                cwd: cwd,
                gitBranch: gitBranch,
                status: status,
                firstSeenAt: firstSeenAt,
                lastSeenAt: lastSeenAt
            )
            sessions.append(session)
        }

        return sessions
    }

    /// Returns hourly activity counts for the past N days
    /// Groups prompt events by day-of-week and hour for heatmap visualization
    func getActivityHeatmap(days: Int = 28) -> [HeatmapCell] {
        guard open() else { return [] }
        defer { close() }

        var results: [HeatmapCell] = []
        let cutoffMs = (Int64(Date().timeIntervalSince1970) - Int64(days * 86400)) * 1000

        let query = """
            SELECT
              CAST(strftime('%w', timestamp/1000, 'unixepoch', 'localtime') AS INTEGER) as day_of_week,
              CAST(strftime('%H', timestamp/1000, 'unixepoch', 'localtime') AS INTEGER) as hour,
              COUNT(*) as count
            FROM session_events
            WHERE timestamp > ? AND event_type = 'prompt'
            GROUP BY day_of_week, hour
            ORDER BY day_of_week, hour
        """

        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, query, -1, &statement, nil) == SQLITE_OK else {
            print("[chud] Failed to prepare heatmap query")
            return []
        }
        defer { sqlite3_finalize(statement) }

        sqlite3_bind_int64(statement, 1, cutoffMs)

        while sqlite3_step(statement) == SQLITE_ROW {
            let dayOfWeek = Int(sqlite3_column_int(statement, 0))
            let hour = Int(sqlite3_column_int(statement, 1))
            let count = Int(sqlite3_column_int(statement, 2))
            results.append(HeatmapCell(dayOfWeek: dayOfWeek, hour: hour, count: count))
        }

        return results
    }

    /// Returns total session time per project (cwd) for the past N days
    /// Calculates duration by pairing start and end events per session
    func getProjectBreakdown(days: Int = 28) -> [ProjectTime] {
        guard open() else { return [] }
        defer { close() }

        var results: [ProjectTime] = []
        let cutoffMs = (Int64(Date().timeIntervalSince1970) - Int64(days * 86400)) * 1000

        // Calculate duration between start and end events, grouped by cwd
        // If no end event, use last prompt as proxy for session end
        let query = """
            WITH session_durations AS (
              SELECT
                cwd,
                session_id,
                MIN(CASE WHEN event_type = 'start' THEN timestamp END) as start_time,
                COALESCE(
                  MAX(CASE WHEN event_type = 'end' THEN timestamp END),
                  MAX(CASE WHEN event_type = 'prompt' THEN timestamp END)
                ) as end_time
              FROM session_events
              WHERE timestamp > ? AND cwd IS NOT NULL AND cwd != ''
              GROUP BY session_id, cwd
            )
            SELECT
              cwd,
              SUM(CASE WHEN end_time > start_time THEN (end_time - start_time) / 60000 ELSE 0 END) as total_minutes
            FROM session_durations
            WHERE start_time IS NOT NULL
            GROUP BY cwd
            ORDER BY total_minutes DESC
        """

        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, query, -1, &statement, nil) == SQLITE_OK else {
            print("[chud] Failed to prepare project breakdown query")
            return []
        }
        defer { sqlite3_finalize(statement) }

        sqlite3_bind_int64(statement, 1, cutoffMs)

        while sqlite3_step(statement) == SQLITE_ROW {
            let cwd = String(cString: sqlite3_column_text(statement, 0))
            let totalMinutes = Int(sqlite3_column_int(statement, 1))
            results.append(ProjectTime(cwd: cwd, totalMinutes: totalMinutes))
        }

        return results
    }

    /// Returns daily usage costs for the past N days
    func getDailyUsage(days: Int = 28) -> [DailyUsage] {
        guard open() else { return [] }
        defer { close() }

        var results: [DailyUsage] = []

        // Calculate cutoff date
        let calendar = Calendar.current
        guard let cutoffDate = calendar.date(byAdding: .day, value: -days, to: Date()) else {
            return []
        }
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        let cutoffStr = dateFormatter.string(from: cutoffDate)

        let query = """
            SELECT date, cost, input_tokens, output_tokens
            FROM usage_daily
            WHERE date >= ?
            ORDER BY date ASC
        """

        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, query, -1, &statement, nil) == SQLITE_OK else {
            print("[chud] Failed to prepare daily usage query")
            return []
        }
        defer { sqlite3_finalize(statement) }

        sqlite3_bind_text(statement, 1, cutoffStr, -1, nil)

        while sqlite3_step(statement) == SQLITE_ROW {
            let date = String(cString: sqlite3_column_text(statement, 0))
            let cost = sqlite3_column_double(statement, 1)
            let inputTokens = Int(sqlite3_column_int(statement, 2))
            let outputTokens = Int(sqlite3_column_int(statement, 3))
            results.append(DailyUsage(date: date, cost: cost, inputTokens: inputTokens, outputTokens: outputTokens))
        }

        return results
    }

    /// Returns pace snapshots for the past N days
    func getPaceSnapshots(days: Int = 28) -> [PaceSnapshot] {
        guard open() else { return [] }
        defer { close() }

        var results: [PaceSnapshot] = []
        let cutoffMs = (Int64(Date().timeIntervalSince1970) - Int64(days * 86400)) * 1000

        let query = """
            SELECT timestamp, pace
            FROM pace_snapshots
            WHERE timestamp >= ?
            ORDER BY timestamp ASC
        """

        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, query, -1, &statement, nil) == SQLITE_OK else {
            print("[chud] Failed to prepare pace snapshots query")
            return []
        }
        defer { sqlite3_finalize(statement) }

        sqlite3_bind_int64(statement, 1, cutoffMs)

        while sqlite3_step(statement) == SQLITE_ROW {
            let timestamp = sqlite3_column_int64(statement, 0)
            let pace = sqlite3_column_double(statement, 1)
            results.append(PaceSnapshot(timestamp: timestamp, pace: pace))
        }

        return results
    }

    /// Returns usage snapshots for the past N days
    func getUsageSnapshots(days: Int = 28) -> [UsageSnapshot] {
        guard open() else { return [] }
        defer { close() }

        var results: [UsageSnapshot] = []
        let cutoffMs = (Int64(Date().timeIntervalSince1970) - Int64(days * 86400)) * 1000

        let query = """
            SELECT timestamp, cost
            FROM usage_snapshots
            WHERE timestamp >= ?
            ORDER BY timestamp ASC
        """

        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, query, -1, &statement, nil) == SQLITE_OK else {
            print("[chud] Failed to prepare usage snapshots query")
            return []
        }
        defer { sqlite3_finalize(statement) }

        sqlite3_bind_int64(statement, 1, cutoffMs)

        while sqlite3_step(statement) == SQLITE_ROW {
            let timestamp = sqlite3_column_int64(statement, 0)
            let cost = sqlite3_column_double(statement, 1)
            results.append(UsageSnapshot(timestamp: timestamp, cost: cost))
        }

        return results
    }
}
