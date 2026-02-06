/**
 * Database types
 */

export interface DailySummary {
  date: string;
  total_sessions: number;
  total_input_tokens: number;
  total_output_tokens: number;
  total_cache_tokens: number;
  total_cost: number;
  models_used: string; // JSON array
  updated_at?: string;
}

/**
 * Session status for menu bar app
 */
export type SessionStatus = 'working' | 'waiting' | 'unknown';

/**
 * Extended session data for menu bar sharing
 */
export interface HudSession {
  session_id: string;
  initial_cwd: string;
  git_branch: string | null;
  status: SessionStatus;
  is_root_at_start: boolean;
  first_seen_at: number;
  last_seen_at: number;
}

/**
 * Daily usage record for charts
 */
export interface UsageRecord {
  date: string;
  cost: number;
  input_tokens: number;
  output_tokens: number;
}

/**
 * Pace snapshot for charts
 */
export interface PaceSnapshot {
  timestamp: number;
  pace: number;
}

/**
 * Usage snapshot for charts (cumulative cost at a point in time)
 */
export interface UsageSnapshot {
  timestamp: number;
  cost: number;
}
