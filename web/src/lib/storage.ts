/**
 * Token storage utilities
 * Uses cookies for persistent token storage (shared between Safari and PWA on iOS)
 * Falls back to localStorage for compatibility
 */

const TOKEN_KEYS = {
  ACCESS: 'chatterbox_access_token',
  REFRESH: 'chatterbox_refresh_token',
  COOLDOWN_END: 'chatterbox_magic_link_cooldown_end',
} as const;

// Cookie configuration
const COOKIE_MAX_AGE = 30 * 24 * 60 * 60; // 30 days in seconds
const COOKIE_OPTIONS = {
  path: '/',
  sameSite: 'Lax' as const,
  secure: window.location.protocol === 'https:',
};

// ═══════════════════════════════════════════════════════════════════════════
// COOKIE UTILITIES
// ═══════════════════════════════════════════════════════════════════════════

function setCookie(name: string, value: string, maxAge: number = COOKIE_MAX_AGE): void {
  const parts = [
    `${encodeURIComponent(name)}=${encodeURIComponent(value)}`,
    `max-age=${maxAge}`,
    `path=${COOKIE_OPTIONS.path}`,
    `samesite=${COOKIE_OPTIONS.sameSite}`,
  ];
  
  if (COOKIE_OPTIONS.secure) {
    parts.push('secure');
  }
  
  document.cookie = parts.join('; ');
}

function getCookie(name: string): string | null {
  const nameEQ = encodeURIComponent(name) + '=';
  const cookies = document.cookie.split(';');
  
  for (let cookie of cookies) {
    cookie = cookie.trim();
    if (cookie.indexOf(nameEQ) === 0) {
      return decodeURIComponent(cookie.substring(nameEQ.length));
    }
  }
  
  return null;
}

function deleteCookie(name: string): void {
  document.cookie = `${encodeURIComponent(name)}=; max-age=0; path=${COOKIE_OPTIONS.path}`;
}

// ═══════════════════════════════════════════════════════════════════════════
// TOKEN MANAGEMENT
// ═══════════════════════════════════════════════════════════════════════════

export function getTokens(): { accessToken: string | null; refreshToken: string | null } {
  // Try cookies first (shared between Safari and PWA)
  let accessToken = getCookie(TOKEN_KEYS.ACCESS);
  let refreshToken = getCookie(TOKEN_KEYS.REFRESH);
  
  // Fall back to localStorage for backwards compatibility
  if (!accessToken) {
    accessToken = localStorage.getItem(TOKEN_KEYS.ACCESS);
  }
  if (!refreshToken) {
    refreshToken = localStorage.getItem(TOKEN_KEYS.REFRESH);
  }
  
  const tokens = { accessToken, refreshToken };
  
  console.log('[Storage] getTokens called:', { 
    hasAccess: !!tokens.accessToken,
    hasRefresh: !!tokens.refreshToken,
    source: accessToken === getCookie(TOKEN_KEYS.ACCESS) ? 'cookie' : 'localStorage',
    origin: window.location.origin,
    isPWA: isPWAMode()
  });
  
  return tokens;
}

export function setTokens(accessToken: string, refreshToken: string): void {
  console.log('[Storage] setTokens called:', { 
    origin: window.location.origin,
    isPWA: isPWAMode(),
    willUseCookies: true
  });
  
  // Store in cookies (shared between Safari and PWA)
  setCookie(TOKEN_KEYS.ACCESS, accessToken);
  setCookie(TOKEN_KEYS.REFRESH, refreshToken);
  
  // Also store in localStorage for backwards compatibility
  try {
    localStorage.setItem(TOKEN_KEYS.ACCESS, accessToken);
    localStorage.setItem(TOKEN_KEYS.REFRESH, refreshToken);
  } catch (e) {
    console.warn('[Storage] localStorage not available, using cookies only');
  }
}

export function clearTokens(): void {
  console.log('[Storage] clearTokens called');
  
  // Clear from cookies
  deleteCookie(TOKEN_KEYS.ACCESS);
  deleteCookie(TOKEN_KEYS.REFRESH);
  
  // Clear from localStorage
  try {
    localStorage.removeItem(TOKEN_KEYS.ACCESS);
    localStorage.removeItem(TOKEN_KEYS.REFRESH);
  } catch (e) {
    // localStorage not available
  }
}

export function hasTokens(): boolean {
  const { accessToken, refreshToken } = getTokens();
  return Boolean(accessToken && refreshToken);
}

// ═══════════════════════════════════════════════════════════════════════════
// COOLDOWN MANAGEMENT (for magic link requests)
// ═══════════════════════════════════════════════════════════════════════════

export function setCooldownEnd(timestamp: number): void {
  localStorage.setItem(TOKEN_KEYS.COOLDOWN_END, timestamp.toString());
}

export function getCooldownEnd(): number | null {
  const value = localStorage.getItem(TOKEN_KEYS.COOLDOWN_END);
  return value ? parseInt(value, 10) : null;
}

export function clearCooldown(): void {
  localStorage.removeItem(TOKEN_KEYS.COOLDOWN_END);
}

export function isInCooldown(): boolean {
  const cooldownEnd = getCooldownEnd();
  if (!cooldownEnd) return false;
  return Date.now() < cooldownEnd;
}

export function getRemainingCooldown(): number {
  const cooldownEnd = getCooldownEnd();
  if (!cooldownEnd) return 0;
  const remaining = cooldownEnd - Date.now();
  return remaining > 0 ? remaining : 0;
}

// ═══════════════════════════════════════════════════════════════════════════
// PWA UTILITIES
// ═══════════════════════════════════════════════════════════════════════════

/**
 * Check if the app is running in standalone PWA mode
 */
export function isPWAMode(): boolean {
  // Check if running in standalone mode (iOS)
  if (window.matchMedia('(display-mode: standalone)').matches) {
    return true;
  }
  
  // Check iOS standalone mode
  if ((window.navigator as any).standalone === true) {
    return true;
  }
  
  return false;
}

/**
 * Check if the app is installable as a PWA
 */
export function canInstallPWA(): boolean {
  return 'serviceWorker' in navigator && 'PushManager' in window;
}
