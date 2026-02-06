/**
 * Pace segment - displays extrapolated hourly cost rate
 */

import type { ClaudeCodeInput, PaceSegmentConfig } from '../config';
import type { DatabaseClient } from '../database';
import { Segment, type SegmentData } from './base';
import { calculatePace } from '../usage/hourly-calculator';

export class PaceSegment extends Segment {
  protected config: PaceSegmentConfig;
  private cachedPace: number | null = null;

  constructor(config: PaceSegmentConfig) {
    super(config);
    this.config = config;
  }

  render(input: ClaudeCodeInput, db: DatabaseClient): SegmentData {
    const { display, colors } = this.config;

    const parts: string[] = [];

    // Add icon if enabled
    if (display.icon) {
      parts.push('△');  // Alchemical symbol for fire
    }

    // Add pace (extrapolated $/hr)
    const pace = this.cachedPace || 0;
    parts.push(`$${pace.toFixed(2)}/hr`);

    return {
      text: parts.join(' '),
      colors,
    };
  }

  /**
   * Update cached pace (call this before render)
   */
  async updateCache(): Promise<void> {
    const hourlyUsage = await calculatePace({
      halfLifeMinutes: this.config.display.halfLifeMinutes,
    });
    this.cachedPace = hourlyUsage.pace;
  }

  /**
   * Get the cached pace for persistence to database
   */
  getCachedPace(): number | null {
    return this.cachedPace;
  }
}
