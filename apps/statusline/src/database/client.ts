/**
 * Database client for querying Claude's statusline-usage.db
 */

import { Database } from 'bun:sqlite';
import { homedir } from 'os';
import { join } from 'path';
import { existsSync } from 'fs';
import type { DailySummary, UsageRecord, PaceSnapshot, UsageSnapshot } from './types';

const DB_PATH = join(homedir(), '.claude', 'statusline-usage.db');

export class DatabaseClient {
  private db: Database | null = null;

  constructor(dbPath?: string) {
    const path = dbPath || DB_PATH;

    // Check if database exists
    if (!existsSync(path)) {
      console.error(`[chud] Database not found at ${path}`);
      return;
    }

    try {
      // Open with write access for session tracking
      this.db = new Database(path, {
        create: true,
        readwrite: true
      });
      this.initializeSessionsTable();
    } catch (error) {
      console.error(`[chud] Failed to open database: ${error}`);
    }
  }

  /**
   * Initialize hud_sessions table for session tracking
   */
  private initializeSessionsTable(): void {
    if (!this.db) return;

    try {
      this.db.exec(`
        CREATE TABLE IF NOT EXISTS hud_sessions (
          session_id TEXT PRIMARY KEY,
          initial_cwd TEXT NOT NULL,
          git_branch TEXT,
          status TEXT DEFAULT 'unknown',
          is_root_at_start INTEGER NOT NULL,
          first_seen_at INTEGER NOT NULL,
          last_seen_at INTEGER NOT NULL
        )
      `);
    } catch (error) {
      console.error(`[chud] Failed to create hud_sessions table: ${error}`);
    }

    // Migration: add new columns if they don't exist (ignore errors)
    try {
      this.db.exec(`ALTER TABLE hud_sessions ADD COLUMN git_branch TEXT`);
    } catch (_) { /* Column already exists */ }

    try {
      this.db.exec(`ALTER TABLE hud_sessions ADD COLUMN status TEXT DEFAULT 'unknown'`);
    } catch (_) { /* Column already exists */ }

    // Initialize usage history tables for charts
    this.initializeUsageHistoryTables();
  }

  /**
   * Initialize tables for usage cost and pace history charts
   */
  private initializeUsageHistoryTables(): void {
    if (!this.db) return;

    try {
      // Daily usage totals (one row per day)
      this.db.exec(`
        CREATE TABLE IF NOT EXISTS usage_daily (
          date TEXT PRIMARY KEY,
          cost REAL NOT NULL,
          input_tokens INTEGER NOT NULL,
          output_tokens INTEGER NOT NULL,
          updated_at INTEGER NOT NULL
        )
      `);

      // Pace snapshots (sampled every ~5 minutes)
      this.db.exec(`
        CREATE TABLE IF NOT EXISTS pace_snapshots (
          timestamp INTEGER PRIMARY KEY,
          pace REAL NOT NULL
        )
      `);

      // Usage snapshots (cumulative cost at point in time, sampled every ~5 minutes)
      this.db.exec(`
        CREATE TABLE IF NOT EXISTS usage_snapshots (
          timestamp INTEGER PRIMARY KEY,
          cost REAL NOT NULL
        )
      `);

      // Index for efficient time-range queries
      this.db.exec(`
        CREATE INDEX IF NOT EXISTS idx_pace_timestamp ON pace_snapshots(timestamp)
      `);
      this.db.exec(`
        CREATE INDEX IF NOT EXISTS idx_usage_timestamp ON usage_snapshots(timestamp)
      `);
    } catch (error) {
      console.error(`[chud] Failed to create usage history tables: ${error}`);
    }
  }

  /**
   * Get daily summary for a specific date
   * Note: Calculates from sessions table for accuracy (matches ccusage)
   */
  getDailySummary(date: string): DailySummary | null {
    if (!this.db) {
      return null;
    }

    try {
      // Calculate from sessions table using start_time (when API call happened)
      // This gives accurate daily totals even with long-running sessions
      const query = this.db.query<{
        total_cost: number;
        total_input_tokens: number;
        total_output_tokens: number;
        total_cache_tokens: number;
      }, [string]>(`
        SELECT
          COALESCE(SUM(cost), 0) as total_cost,
          COALESCE(SUM(input_tokens), 0) as total_input_tokens,
          COALESCE(SUM(output_tokens), 0) as total_output_tokens,
          COALESCE(SUM(cache_tokens), 0) as total_cache_tokens
        FROM sessions
        WHERE date(start_time, 'localtime') = ?
      `);

      const result = query.get(date);

      if (!result) {
        return null;
      }

      return {
        date,
        total_sessions: 0,  // Not calculated
        total_input_tokens: result.total_input_tokens,
        total_output_tokens: result.total_output_tokens,
        total_cache_tokens: result.total_cache_tokens,
        total_cost: result.total_cost,
        models_used: '[]',  // Not calculated
      };
    } catch (error) {
      console.error(`[chud] Failed to query daily summary: ${error}`);
      return null;
    }
  }

  /**
   * Get today's date in YYYY-MM-DD format
   */
  static getTodayDate(): string {
    const now = new Date();
    const year = now.getFullYear();
    const month = String(now.getMonth() + 1).padStart(2, '0');
    const day = String(now.getDate()).padStart(2, '0');
    return `${year}-${month}-${day}`;
  }

  /**
   * Get session root status (whether session started in git root)
   * Caches initial state for session persistence
   */
  getSessionRootStatus(
    sessionId: string,
    currentCwd: string,
    gitRoot: string
  ): boolean {
    if (!this.db) {
      // Fallback: return current state if db unavailable
      return currentCwd === gitRoot;
    }

    try {
      // Check if session exists
      const selectQuery = this.db.query<
        { is_root_at_start: number },
        [string]
      >('SELECT is_root_at_start FROM hud_sessions WHERE session_id = ?');

      const existing = selectQuery.get(sessionId);

      if (existing) {
        // Update last_seen_at timestamp
        const updateQuery = this.db.query(
          'UPDATE hud_sessions SET last_seen_at = ? WHERE session_id = ?'
        );
        updateQuery.run(Date.now(), sessionId);

        return existing.is_root_at_start === 1;
      }

      // New session: compute and cache initial state
      const isRootAtStart = currentCwd === gitRoot;
      const now = Date.now();

      const insertQuery = this.db.query(`
        INSERT INTO hud_sessions (
          session_id,
          initial_cwd,
          is_root_at_start,
          first_seen_at,
          last_seen_at
        ) VALUES (?, ?, ?, ?, ?)
      `);

      insertQuery.run(
        sessionId,
        currentCwd,
        isRootAtStart ? 1 : 0,
        now,
        now
      );

      return isRootAtStart;
    } catch (error) {
      console.error(`[chud] Failed to get session root status: ${error}`);
      // Fallback on error
      return currentCwd === gitRoot;
    }
  }

  /**
   * Cleanup old sessions from hud_sessions table
   * @param daysOld Number of days after which to delete sessions (default: 7)
   * @returns Number of sessions deleted
   */
  cleanupOldSessions(daysOld: number = 7): number {
    if (!this.db) return 0;

    try {
      const cutoffTime = Date.now() - daysOld * 24 * 60 * 60 * 1000;
      const deleteQuery = this.db.query(
        'DELETE FROM hud_sessions WHERE last_seen_at < ?'
      );

      const result = deleteQuery.run(cutoffTime);
      return result.changes;
    } catch (error) {
      console.error(`[chud] Failed to cleanup old sessions: ${error}`);
      return 0;
    }
  }

  /**
   * Record daily usage totals (upsert)
   */
  recordDailyUsage(date: string, cost: number, inputTokens: number, outputTokens: number): void {
    if (!this.db) return;

    try {
      const query = this.db.query(`
        INSERT INTO usage_daily (date, cost, input_tokens, output_tokens, updated_at)
        VALUES (?, ?, ?, ?, ?)
        ON CONFLICT(date) DO UPDATE SET
          cost = excluded.cost,
          input_tokens = excluded.input_tokens,
          output_tokens = excluded.output_tokens,
          updated_at = excluded.updated_at
      `);
      query.run(date, cost, inputTokens, outputTokens, Date.now());
    } catch (error) {
      console.error(`[chud] Failed to record daily usage: ${error}`);
    }
  }

  /**
   * Record pace snapshot (sampled periodically)
   * Only records if last snapshot is older than 1 minute
   */
  recordPaceSnapshot(pace: number): void {
    if (!this.db) return;

    try {
      const now = Date.now();
      const oneMinuteAgo = now - 60 * 1000;

      // Check if we have a recent snapshot
      const checkQuery = this.db.query<{ timestamp: number }, []>(
        'SELECT timestamp FROM pace_snapshots ORDER BY timestamp DESC LIMIT 1'
      );
      const latest = checkQuery.get();

      if (latest && latest.timestamp > oneMinuteAgo) {
        return; // Skip if last snapshot is recent
      }

      // Insert new snapshot
      const insertQuery = this.db.query(
        'INSERT INTO pace_snapshots (timestamp, pace) VALUES (?, ?)'
      );
      insertQuery.run(now, pace);

      // Cleanup old snapshots (keep last 7 days)
      const cutoff = now - 7 * 24 * 60 * 60 * 1000;
      this.db.exec(`DELETE FROM pace_snapshots WHERE timestamp < ${cutoff}`);
    } catch (error) {
      console.error(`[chud] Failed to record pace snapshot: ${error}`);
    }
  }

  /**
   * Record usage snapshot (cumulative cost at point in time)
   * Only records if last snapshot is older than 1 minute
   */
  recordUsageSnapshot(cost: number): void {
    if (!this.db) return;

    try {
      const now = Date.now();
      const oneMinuteAgo = now - 60 * 1000;

      // Check if we have a recent snapshot
      const checkQuery = this.db.query<{ timestamp: number }, []>(
        'SELECT timestamp FROM usage_snapshots ORDER BY timestamp DESC LIMIT 1'
      );
      const latest = checkQuery.get();

      if (latest && latest.timestamp > oneMinuteAgo) {
        return; // Skip if last snapshot is recent
      }

      // Insert new snapshot
      const insertQuery = this.db.query(
        'INSERT INTO usage_snapshots (timestamp, cost) VALUES (?, ?)'
      );
      insertQuery.run(now, cost);

      // Cleanup old snapshots (keep last 7 days)
      const cutoff = now - 7 * 24 * 60 * 60 * 1000;
      this.db.exec(`DELETE FROM usage_snapshots WHERE timestamp < ${cutoff}`);
    } catch (error) {
      console.error(`[chud] Failed to record usage snapshot: ${error}`);
    }
  }

  /**
   * Get daily usage for the last N days
   */
  getDailyUsage(days: number): UsageRecord[] {
    if (!this.db) return [];

    try {
      const cutoffDate = new Date();
      cutoffDate.setDate(cutoffDate.getDate() - days);
      const cutoffStr = cutoffDate.toISOString().split('T')[0];

      const query = this.db.query<UsageRecord, [string]>(`
        SELECT date, cost, input_tokens, output_tokens
        FROM usage_daily
        WHERE date >= ?
        ORDER BY date ASC
      `);
      return query.all(cutoffStr);
    } catch (error) {
      console.error(`[chud] Failed to get daily usage: ${error}`);
      return [];
    }
  }

  /**
   * Get pace snapshots for the last N days
   */
  getPaceSnapshots(days: number): PaceSnapshot[] {
    if (!this.db) return [];

    try {
      const cutoffMs = Date.now() - days * 24 * 60 * 60 * 1000;

      const query = this.db.query<PaceSnapshot, [number]>(`
        SELECT timestamp, pace
        FROM pace_snapshots
        WHERE timestamp >= ?
        ORDER BY timestamp ASC
      `);
      return query.all(cutoffMs);
    } catch (error) {
      console.error(`[chud] Failed to get pace snapshots: ${error}`);
      return [];
    }
  }

  /**
   * Get usage snapshots for the last N days
   */
  getUsageSnapshots(days: number): UsageSnapshot[] {
    if (!this.db) return [];

    try {
      const cutoffMs = Date.now() - days * 24 * 60 * 60 * 1000;

      const query = this.db.query<UsageSnapshot, [number]>(`
        SELECT timestamp, cost
        FROM usage_snapshots
        WHERE timestamp >= ?
        ORDER BY timestamp ASC
      `);
      return query.all(cutoffMs);
    } catch (error) {
      console.error(`[chud] Failed to get usage snapshots: ${error}`);
      return [];
    }
  }

  /**
   * Close the database connection
   */
  close(): void {
    if (this.db) {
      this.db.close();
      this.db = null;
    }
  }

  /**
   * Check if database is connected
   */
  isConnected(): boolean {
    return this.db !== null;
  }
}
