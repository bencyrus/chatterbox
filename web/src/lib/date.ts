/**
 * Date formatting utilities
 * Uses native Intl API for localization
 */

// ═══════════════════════════════════════════════════════════════════════════
// DATE COMPARISON HELPERS
// ═══════════════════════════════════════════════════════════════════════════

function isSameDay(date1: Date, date2: Date): boolean {
  return (
    date1.getFullYear() === date2.getFullYear() &&
    date1.getMonth() === date2.getMonth() &&
    date1.getDate() === date2.getDate()
  );
}

function isYesterday(date: Date): boolean {
  const yesterday = new Date();
  yesterday.setDate(yesterday.getDate() - 1);
  return isSameDay(date, yesterday);
}

function isToday(date: Date): boolean {
  return isSameDay(date, new Date());
}

// ═══════════════════════════════════════════════════════════════════════════
// DATE FORMATTING
// ═══════════════════════════════════════════════════════════════════════════

/**
 * Get a date group key and label for grouping recordings by date
 * Returns: { key: "2024-01-15", label: "Today" | "Yesterday" | "Jan 15, 2024" }
 */
export function getDateGroupKey(date: Date | string): { key: string; label: string } {
  const d = typeof date === 'string' ? new Date(date) : date;
  
  // Key for sorting (YYYY-MM-DD)
  const key = d.toISOString().split('T')[0];
  
  // Label for display
  let label: string;
  if (isToday(d)) {
    label = 'Today';
  } else if (isYesterday(d)) {
    label = 'Yesterday';
  } else {
    label = new Intl.DateTimeFormat('en-US', {
      month: 'short',
      day: 'numeric',
      year: 'numeric',
    }).format(d);
  }
  
  return { key, label };
}

/**
 * Format a date as a full date string
 * Example: "January 15, 2024"
 */
export function formatDate(date: Date | string): string {
  const d = typeof date === 'string' ? new Date(date) : date;
  
  return new Intl.DateTimeFormat('en-US', {
    month: 'long',
    day: 'numeric',
    year: 'numeric',
  }).format(d);
}

/**
 * Format a time string
 * Example: "2:30 PM"
 */
export function formatTime(date: Date | string): string {
  const d = typeof date === 'string' ? new Date(date) : date;
  
  return new Intl.DateTimeFormat('en-US', {
    hour: 'numeric',
    minute: '2-digit',
    hour12: true,
  }).format(d);
}

/**
 * Format a date and time
 * Example: "Jan 15, 2024 at 2:30 PM"
 */
export function formatDateTime(date: Date | string): string {
  const d = typeof date === 'string' ? new Date(date) : date;
  
  return new Intl.DateTimeFormat('en-US', {
    month: 'short',
    day: 'numeric',
    year: 'numeric',
    hour: 'numeric',
    minute: '2-digit',
    hour12: true,
  }).format(d);
}

// ═══════════════════════════════════════════════════════════════════════════
// DURATION FORMATTING
// ═══════════════════════════════════════════════════════════════════════════

/**
 * Format a duration in seconds to MM:SS format
 * Example: 90 -> "1:30"
 */
export function formatDuration(seconds: number): string {
  const mins = Math.floor(seconds / 60);
  const secs = Math.floor(seconds % 60);
  return `${mins}:${secs.toString().padStart(2, '0')}`;
}

/**
 * Format a duration in milliseconds to MM:SS format
 */
export function formatDurationMs(ms: number): string {
  return formatDuration(ms / 1000);
}

/**
 * Parse a duration string or number to milliseconds
 * Handles formats like: "00:01:30", "1:30", "90", "90.5", or numeric values
 */
export function parseDuration(value: string | number): number {
  if (typeof value === 'number') {
    // If numeric and > 1000, assume it's already milliseconds
    // Otherwise assume seconds and convert to ms
    return value > 1000 ? value : value * 1000;
  }
  
  // Handle string formats
  const str = value.trim();
  
  // Try parsing as a number string first (e.g., "90" or "90.5")
  // But only if it doesn't contain a colon (which indicates time format)
  if (!str.includes(':')) {
    const numValue = parseFloat(str);
    if (!isNaN(numValue)) {
      // It's a plain number string, treat as seconds
      return numValue * 1000;
    }
  }
  
  // Try parsing as time format (HH:MM:SS, MM:SS, or H:MM:SS)
  const parts = str.split(':').map((p) => parseFloat(p));
  
  if (parts.length === 3) {
    // HH:MM:SS
    const [hours, minutes, seconds] = parts;
    return ((hours * 3600) + (minutes * 60) + seconds) * 1000;
  } else if (parts.length === 2) {
    // MM:SS
    const [minutes, seconds] = parts;
    return ((minutes * 60) + seconds) * 1000;
  }
  
  // Fallback: return 0 if unparseable
  return 0;
}

// ═══════════════════════════════════════════════════════════════════════════
// RELATIVE TIME
// ═══════════════════════════════════════════════════════════════════════════

/**
 * Get a relative time string
 * Example: "2 hours ago", "just now"
 */
export function getRelativeTime(date: Date | string): string {
  const d = typeof date === 'string' ? new Date(date) : date;
  const now = new Date();
  const diffMs = now.getTime() - d.getTime();
  const diffMins = Math.floor(diffMs / (1000 * 60));
  const diffHours = Math.floor(diffMs / (1000 * 60 * 60));
  const diffDays = Math.floor(diffMs / (1000 * 60 * 60 * 24));
  
  if (diffMins < 1) return 'just now';
  if (diffMins < 60) return `${diffMins} minute${diffMins === 1 ? '' : 's'} ago`;
  if (diffHours < 24) return `${diffHours} hour${diffHours === 1 ? '' : 's'} ago`;
  if (diffDays < 7) return `${diffDays} day${diffDays === 1 ? '' : 's'} ago`;
  
  return formatDate(d);
}
