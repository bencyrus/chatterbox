/**
 * Application constants
 */

// ═══════════════════════════════════════════════════════════════════════════
// API CONFIGURATION
// ═══════════════════════════════════════════════════════════════════════════

export const API_BASE_URL = '/api';

// ═══════════════════════════════════════════════════════════════════════════
// AUTH CONFIGURATION
// ═══════════════════════════════════════════════════════════════════════════

/** Cooldown period after requesting a magic link (in milliseconds) */
export const MAGIC_LINK_COOLDOWN_MS = 60 * 1000; // 60 seconds

// ═══════════════════════════════════════════════════════════════════════════
// POLLING CONFIGURATION
// ═══════════════════════════════════════════════════════════════════════════

/** Interval for polling transcription status (in milliseconds) */
export const TRANSCRIPTION_POLL_INTERVAL_MS = 5000; // 5 seconds

// ═══════════════════════════════════════════════════════════════════════════
// UI CONFIGURATION
// ═══════════════════════════════════════════════════════════════════════════

/** Default number of cues to fetch */
export const DEFAULT_CUE_COUNT = 50;

/** Toast auto-dismiss duration (in milliseconds) */
export const TOAST_DURATION_MS = 5000; // 5 seconds

// ═══════════════════════════════════════════════════════════════════════════
// AUDIO CONFIGURATION
// ═══════════════════════════════════════════════════════════════════════════

/** Audio recording MIME type */
export const AUDIO_MIME_TYPE = 'audio/webm;codecs=opus';

/** Fallback MIME type if WebM is not supported */
export const AUDIO_MIME_TYPE_FALLBACK = 'audio/mp4';

/** MIME type to send to backend */
export const AUDIO_UPLOAD_MIME_TYPE = 'audio/mp4';

// ═══════════════════════════════════════════════════════════════════════════
// ROUTES
// ═══════════════════════════════════════════════════════════════════════════

export const ROUTES = {
  // Public routes
  HOME: '/',
  LOGIN: '/login',
  MAGIC_LINK: '/auth/magic',
  PRIVACY: '/privacy',
  ACCOUNT_RESTORE: '/request-account-restore',
  REQUEST_ACCOUNT_RESTORE: '/request-account-restore',
  // Protected routes (under /app)
  APP: '/app',
  CUES: '/app/cues',
  CUE_DETAIL: '/app/cues/:cueId',
  HISTORY: '/app/history',
  RECORDING_DETAIL: '/app/history/:recordingId',
  SETTINGS: '/app/settings',
} as const;

// ═══════════════════════════════════════════════════════════════════════════
// LANGUAGE DISPLAY NAMES
// ═══════════════════════════════════════════════════════════════════════════

export const LANGUAGE_NAMES: Record<string, string> = {
  en: 'English',
  de: 'German',
  fr: 'French',
  es: 'Spanish',
  it: 'Italian',
  pt: 'Portuguese',
  nl: 'Dutch',
  pl: 'Polish',
  ru: 'Russian',
  ja: 'Japanese',
  zh: 'Chinese',
  ko: 'Korean',
};

export function getLanguageDisplayName(code: string): string {
  return LANGUAGE_NAMES[code] || code.toUpperCase();
}
