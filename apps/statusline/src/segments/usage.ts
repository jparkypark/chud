/**
 * Usage segment - displays daily cost and token usage
 * Combines Claude Code (ccusage) and Codex CLI (@ccusage/codex) usage
 */

import type { ClaudeCodeInput, UsageSegmentConfig } from '../config';
import type { DatabaseClient } from '../database';
import { Segment, type SegmentData } from './base';
import { loadDailyUsageData } from 'ccusage/data-loader';
import { existsSync, readFileSync, writeFileSync, mkdirSync } from 'fs';
import { join } from 'path';
import { homedir } from 'os';

// Default cache TTL (can be overridden in config)
const DEFAULT_CACHE_TTL_MINUTES = 1;
const CACHE_DIR = join(homedir(), '.cache', 'chud');
const CLAUDE_CACHE_FILE = join(CACHE_DIR, 'claude-usage.json');
const CODEX_CACHE_FILE = join(CACHE_DIR, 'codex-usage.json');

interface UsageCacheData {
  date: string;
  cost: number;
  inputTokens: number;
  outputTokens: number;
  timestamp: number;
}

/**
 * Format token count with K/M suffix
 */
function formatTokens(tokens: number): string {
  if (tokens >= 1_000_000) {
    return `${(tokens / 1_000_000).toFixed(1)}M`;
  } else if (tokens >= 1_000) {
    return `${(tokens / 1_000).toFixed(1)}K`;
  }
  return tokens.toString();
}

/**
 * Get today's date in YYYY-MM-DD format (local timezone)
 */
function getTodayDate(): string {
  const now = new Date();
  const year = now.getFullYear();
  const month = String(now.getMonth() + 1).padStart(2, '0');
  const day = String(now.getDate()).padStart(2, '0');
  return `${year}-${month}-${day}`;
}

/**
 * Detect system timezone (best effort)
 */
function getSystemTimezone(): string {
  try {
    return Intl.DateTimeFormat().resolvedOptions().timeZone;
  } catch {
    return 'UTC';
  }
}

/**
 * Load cached data if valid (same date and not expired)
 */
function loadCache(cacheFile: string, today: string, cacheTtlMs: number): UsageCacheData | null {
  try {
    if (!existsSync(cacheFile)) return null;

    const cached: UsageCacheData = JSON.parse(
      readFileSync(cacheFile, 'utf-8')
    );

    // Check if cache is valid (same date and not expired)
    const now = Date.now();
    if (cached.date === today && now - cached.timestamp < cacheTtlMs) {
      return cached;
    }

    return null;
  } catch {
    return null;
  }
}

/**
 * Save data to cache
 */
function saveCache(cacheFile: string, data: UsageCacheData): void {
  try {
    if (!existsSync(CACHE_DIR)) {
      mkdirSync(CACHE_DIR, { recursive: true });
    }
    writeFileSync(cacheFile, JSON.stringify(data));
  } catch {
    // Ignore cache write errors
  }
}

interface CodexDailyData {
  daily: Array<{
    date: string;
    costUSD: number;
    inputTokens: number;
    outputTokens: number;
    totalTokens: number;
  }>;
  totals: {
    costUSD: number;
    inputTokens: number;
    outputTokens: number;
  };
}

/**
 * Fetch today's Codex usage via @ccusage/codex CLI (with caching)
 */
async function loadCodexTodayData(timezone: string, cacheTtlMs: number): Promise<{
  cost: number;
  inputTokens: number;
  outputTokens: number;
}> {
  const today = getTodayDate();

  // Check cache first
  const cached = loadCache(CODEX_CACHE_FILE, today, cacheTtlMs);
  if (cached) {
    return {
      cost: cached.cost,
      inputTokens: cached.inputTokens,
      outputTokens: cached.outputTokens,
    };
  }

  try {
    // Run ccusage-codex with JSON output, filtering to today only
    const proc = Bun.spawn(
      ['bunx', '@ccusage/codex@latest', 'daily', '--json', '--since', today, '--timezone', timezone],
      { stdout: 'pipe', stderr: 'pipe' }
    );

    // Set a 5 second timeout
    const timeoutPromise = new Promise<null>((resolve) =>
      setTimeout(() => {
        proc.kill();
        resolve(null);
      }, 5000)
    );

    const resultPromise = (async () => {
      const output = await new Response(proc.stdout).text();
      const exitCode = await proc.exited;
      if (exitCode !== 0) return null;
      return output;
    })();

    const output = await Promise.race([resultPromise, timeoutPromise]);
    if (!output) {
      return { cost: 0, inputTokens: 0, outputTokens: 0 };
    }

    const data: CodexDailyData = JSON.parse(output);

    const result = {
      cost: data.totals?.costUSD || 0,
      inputTokens: data.totals?.inputTokens || 0,
      outputTokens: data.totals?.outputTokens || 0,
    };

    // Cache the result
    saveCache(CODEX_CACHE_FILE, {
      date: today,
      ...result,
      timestamp: Date.now(),
    });

    return result;
  } catch {
    return { cost: 0, inputTokens: 0, outputTokens: 0 };
  }
}

/**
 * Load today's Claude Code usage via ccusage (with caching)
 * Cache TTL is configurable to balance freshness vs performance
 */
async function loadClaudeTodayData(timezone: string, cacheTtlMs: number): Promise<{
  cost: number;
  inputTokens: number;
  outputTokens: number;
}> {
  const today = getTodayDate();

  // Check cache first - this is the key optimization
  const cached = loadCache(CLAUDE_CACHE_FILE, today, cacheTtlMs);
  if (cached) {
    return {
      cost: cached.cost,
      inputTokens: cached.inputTokens,
      outputTokens: cached.outputTokens,
    };
  }

  try {
    // Suppress ccusage logging
    const originalStderr = console.error;
    const originalConsoleLog = console.log;
    const originalConsoleInfo = console.info;
    const originalConsoleWarn = console.warn;
    const originalProcessStderrWrite = process.stderr.write;
    const originalProcessStdoutWrite = process.stdout.write;

    console.error = () => {};
    console.log = () => {};
    console.info = () => {};
    console.warn = () => {};
    process.stderr.write = () => true;
    process.stdout.write = () => true;

    try {
      // Load data using ccusage (slow but accurate)
      const data = await loadDailyUsageData({
        offline: false,
        timezone,
      });

      // Find today's data
      const todayData = data.find((d) => d.date === today);

      const result = todayData
        ? {
            cost: todayData.totalCost,
            inputTokens: todayData.inputTokens,
            outputTokens: todayData.outputTokens,
          }
        : { cost: 0, inputTokens: 0, outputTokens: 0 };

      // Cache the result for 5 minutes
      saveCache(CLAUDE_CACHE_FILE, {
        date: today,
        ...result,
        timestamp: Date.now(),
      });

      return result;
    } finally {
      // Restore console methods
      console.error = originalStderr;
      console.log = originalConsoleLog;
      console.info = originalConsoleInfo;
      console.warn = originalConsoleWarn;
      process.stderr.write = originalProcessStderrWrite;
      process.stdout.write = originalProcessStdoutWrite;
    }
  } catch (error) {
    console.error('[chud] Failed to load usage data from ccusage:', error);
    return { cost: 0, inputTokens: 0, outputTokens: 0 };
  }
}

export class UsageSegment extends Segment {
  protected config: UsageSegmentConfig;
  private cachedData: { date: string; cost: number; tokens: number } | null =
    null;

  constructor(config: UsageSegmentConfig) {
    super(config);
    this.config = config;
  }

  /**
   * Get cache TTL in milliseconds from config
   */
  private getCacheTtlMs(): number {
    const minutes = this.config.display.cacheTtlMinutes ?? DEFAULT_CACHE_TTL_MINUTES;
    return minutes * 60 * 1000;
  }

  /**
   * Load today's data from ccusage (with disk caching)
   */
  async loadTodayData(): Promise<{
    cost: number;
    inputTokens: number;
    outputTokens: number;
  }> {
    const timezone = getSystemTimezone();
    return loadClaudeTodayData(timezone, this.getCacheTtlMs());
  }

  render(input: ClaudeCodeInput, db: DatabaseClient): SegmentData {
    const { display, colors } = this.config;

    const parts: string[] = [];

    if (display.icon) {
      parts.push('Σ');
    }

    if (display.cost) {
      const cost = this.cachedData?.cost || 0;
      parts.push(`$${cost.toFixed(2)}`);
    }

    if (display.tokens) {
      const totalTokens = this.cachedData?.tokens || 0;
      parts.push(formatTokens(totalTokens));
    }

    if (display.period) {
      parts.push(display.period);
    }

    return {
      text: parts.join(' '),
      colors,
    };
  }

  /**
   * Update cached data (call this before render)
   * Fetches both Claude Code and Codex usage in parallel
   */
  async updateCache(): Promise<void> {
    const timezone = getSystemTimezone();
    const cacheTtlMs = this.getCacheTtlMs();

    // Fetch Claude Code and Codex usage in parallel
    const [claudeData, codexData] = await Promise.all([
      this.loadTodayData(),
      loadCodexTodayData(timezone, cacheTtlMs),
    ]);

    // Combine costs and tokens
    this.cachedData = {
      date: getTodayDate(),
      cost: claudeData.cost + codexData.cost,
      tokens:
        claudeData.inputTokens +
        claudeData.outputTokens +
        codexData.inputTokens +
        codexData.outputTokens,
    };
  }
}
