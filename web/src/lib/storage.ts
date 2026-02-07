/**
 * Token storage utilities
 * Uses localStorage for persistent token storage
 */

const TOKEN_KEYS = {
  ACCESS: 'chatterbox_access_token',
  REFRESH: 'chatterbox_refresh_token',
  COOLDOWN_END: 'chatterbox_magic_link_cooldown_end',
} as const;

// ═══════════════════════════════════════════════════════════════════════════
// TOKEN MANAGEMENT
// ═══════════════════════════════════════════════════════════════════════════

export function getTokens(): { accessToken: string | null; refreshToken: string | null } {
  return {
    accessToken: localStorage.getItem(TOKEN_KEYS.ACCESS),
    refreshToken: localStorage.getItem(TOKEN_KEYS.REFRESH),
  };
}

export function setTokens(accessToken: string, refreshToken: string): void {
  localStorage.setItem(TOKEN_KEYS.ACCESS, accessToken);
  localStorage.setItem(TOKEN_KEYS.REFRESH, refreshToken);
}

export function clearTokens(): void {
  localStorage.removeItem(TOKEN_KEYS.ACCESS);
  localStorage.removeItem(TOKEN_KEYS.REFRESH);
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
