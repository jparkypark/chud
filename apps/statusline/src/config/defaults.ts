/**
 * Default configuration for chud
 */

import type { Config } from './types';

export const DEFAULT_CONFIG: Config = {
  segments: [
    {
      type: 'directory',
      display: {
        icon: true,
        pathMode: 'parent',
        rootWarning: false,
      },
      colors: {
        fg: '#ffffff',
        bg: '#ef4444',  // red-500
      },
    },
    {
      type: 'git',
      display: {
        icon: true,
        branch: true,
        status: true,
        ahead: true,
        behind: true,
      },
      colors: {
        fg: '#ffffff',
        bg: '#f97316',  // orange-500
      },
    },
    {
      type: 'pr',
      display: {
        icon: true,
        number: true,
      },
      colors: {
        fg: '#ffffff',
        bg: '#eab308',  // yellow-500
      },
    },
    {
      type: 'usage',
      display: {
        icon: true,
        cost: true,
        tokens: false,
        period: 'today',
        cacheTtlMinutes: 1,  // Cache ccusage results for 1 minute
      },
      colors: {
        fg: '#ffffff',
        bg: '#22c55e',  // green-500
      },
    },
    {
      type: 'pace',
      display: {
        icon: true,
        period: 'hourly',
        halfLifeMinutes: 60,  // ~87 minute effective window - good for daily cost projection
      },
      colors: {
        fg: '#ffffff',
        bg: '#06b6d4',  // cyan-500
      },
    },
    {
      type: 'context',
      display: {
        icon: true,
        mode: 'used',  // Show context window used percentage
      },
      colors: {
        fg: '#ffffff',
        bg: '#3b82f6',  // blue-500
      },
    },
    {
      type: 'time',
      display: {
        icon: true,
        format: '12h',
        seconds: false,
      },
      colors: {
        fg: '#ffffff',
        bg: '#6366f1',  // indigo-500
      },
    },
    {
      type: 'thoughts',
      display: {
        icon: true,
        quotes: false,
      },
      colors: {
        fg: '#ffffff',
        bg: '#8b5cf6',  // violet-500
      },
      useApiQuotes: true,
    },
  ],
  theme: {
    powerline: true,
    separatorStyle: 'angled',
    colorMode: 'text',
    themeMode: 'auto',
  },
};
