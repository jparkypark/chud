#!/usr/bin/env bun

/**
 * chud - Customizable heads-up display for Claude Code
 */

import { loadConfig } from './config';
import { DatabaseClient } from './database';
import { createSegment } from './segments';
import { renderPowerline } from './renderer';
import { UsageSegment } from './segments/usage';
import { PaceSegment } from './segments/pace';

/**
 * Read JSON from stdin
 */
async function readStdin(): Promise<string> {
  const chunks: Uint8Array[] = [];

  for await (const chunk of Bun.stdin.stream()) {
    chunks.push(chunk);
  }

  const buffer = Buffer.concat(chunks);
  return buffer.toString('utf-8');
}

/**
 * Main function
 */
async function main() {
  try {
    // 1. Read input from Claude Code (via stdin)
    const input = await readStdin();
    const sessionData = input ? JSON.parse(input) : {};

    // 2. Load configuration
    const config = loadConfig();

    // 3. Initialize database connection
    const db = new DatabaseClient();

    // Periodically cleanup old sessions (1% probability = ~every 100 renders)
    if (Math.random() < 0.01) {
      db.cleanupOldSessions(7);
    }

    // 4. Create segments and load async data for usage segment
    const segments = config.segments.map((segmentConfig) =>
      createSegment(segmentConfig)
    );

    // Load usage data asynchronously (if usage segment exists)
    await Promise.all(
      segments.map(async (segment) => {
        if ('updateCache' in segment && typeof segment.updateCache === 'function') {
          await segment.updateCache();
        }
      })
    );

    // 5. Persist usage and pace data to database for charts
    for (const segment of segments) {
      if (segment instanceof UsageSegment) {
        const data = segment.getCachedData();
        if (data) {
          db.recordDailyUsage(data.date, data.cost, data.inputTokens, data.outputTokens);
        }
      }
      if (segment instanceof PaceSegment) {
        const pace = segment.getCachedPace();
        if (pace !== null) {
          db.recordPaceSnapshot(pace);
        }
      }
    }

    // 6. Render each segment
    const segmentDataList = segments.map((segment) =>
      segment.render(sessionData, db)
    );

    // 7. Apply powerline styling
    const statusline = renderPowerline(segmentDataList, config.theme);

    // 8. Output to stdout
    console.log(statusline);

    // 9. Close database connection
    db.close();
  } catch (error) {
    // Log errors to stderr (not stdout, to avoid breaking statusline)
    console.error('[chud] Error:', error);

    // Output empty string on error (graceful degradation)
    console.log('');

    process.exit(1);
  }
}

// Run main function
main();
