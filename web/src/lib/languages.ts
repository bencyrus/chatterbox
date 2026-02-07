/**
 * Language utilities and mappings
 */

// ═══════════════════════════════════════════════════════════════════════════
// FLAG EMOJI MAPPING
// ═══════════════════════════════════════════════════════════════════════════

/**
 * Map language codes to country flag emojis
 * Matches iOS flagEmoji function
 */
export const LANGUAGE_FLAGS: Record<string, string> = {
  en: '🇬🇧',
  es: '🇪🇸',
  fr: '🇫🇷',
  de: '🇩🇪',
  it: '🇮🇹',
  pt: '🇵🇹',
  ru: '🇷🇺',
  zh: '🇨🇳',
  ja: '🇯🇵',
  ko: '🇰🇷',
  ar: '🇸🇦',
  hi: '🇮🇳',
  tr: '🇹🇷',
  nl: '🇳🇱',
  pl: '🇵🇱',
};

/**
 * Get flag emoji for a language code
 * Returns 🌐 if no flag is mapped
 */
export function getFlagEmoji(languageCode: string): string {
  return LANGUAGE_FLAGS[languageCode] || '🌐';
}

// ═══════════════════════════════════════════════════════════════════════════
// LANGUAGE DISPLAY NAMES
// ═══════════════════════════════════════════════════════════════════════════

/**
 * Map language codes to display names (in native script when appropriate)
 * Matches iOS languageDisplayName function
 */
export const LANGUAGE_DISPLAY_NAMES: Record<string, string> = {
  en: 'English',
  es: 'Español',
  fr: 'Français',
  de: 'Deutsch',
  it: 'Italiano',
  pt: 'Português',
  ru: 'Русский',
  zh: '中文',
  ja: '日本語',
  ko: '한국어',
  ar: 'العربية',
  hi: 'हिन्दी',
  tr: 'Türkçe',
  nl: 'Nederlands',
  pl: 'Polski',
};

/**
 * Get display name for a language code
 * Returns uppercase code if no name is mapped
 */
export function getLanguageDisplayName(code: string): string {
  return LANGUAGE_DISPLAY_NAMES[code] || code.toUpperCase();
}
