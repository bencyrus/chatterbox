import {
  createContext,
  useContext,
  useMemo,
  type ReactNode,
} from 'react';

// ═══════════════════════════════════════════════════════════════════════════
// TYPES
// ═══════════════════════════════════════════════════════════════════════════

export type AppPlatform = 'ios' | 'android' | 'desktop' | 'unknown';

export interface AppEnv {
  /** True when running as an installed PWA (standalone display-mode). */
  isPwa: boolean;
  /** Best-effort platform detection. */
  platform: AppPlatform;
  /** Convenience flag. */
  isIos: boolean;
  /** Current origin (useful for debugging / logging / consistency checks). */
  origin: string;
}

interface AppEnvContextValue extends AppEnv {}

// ═══════════════════════════════════════════════════════════════════════════
// DETECTION
// ═══════════════════════════════════════════════════════════════════════════

function detectPlatform(): AppPlatform {
  const ua = navigator.userAgent.toLowerCase();
  if (/(iphone|ipad|ipod)/.test(ua)) return 'ios';
  if (/android/.test(ua)) return 'android';
  if (/macintosh|windows|linux/.test(ua)) return 'desktop';
  return 'unknown';
}

function detectIsPwa(): boolean {
  // Standard PWA display-mode detection
  if (window.matchMedia?.('(display-mode: standalone)')?.matches) {
    return true;
  }

  // iOS standalone mode (Safari Add to Home Screen)
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  if ((window.navigator as any).standalone === true) {
    return true;
  }

  return false;
}

// ═══════════════════════════════════════════════════════════════════════════
// CONTEXT
// ═══════════════════════════════════════════════════════════════════════════

const AppEnvContext = createContext<AppEnvContextValue | null>(null);

interface AppEnvProviderProps {
  children: ReactNode;
}

export function AppEnvProvider({ children }: AppEnvProviderProps) {
  const value = useMemo<AppEnvContextValue>(() => {
    const platform = detectPlatform();
    return {
      isPwa: detectIsPwa(),
      platform,
      isIos: platform === 'ios',
      origin: window.location.origin,
    };
  }, []);

  return <AppEnvContext.Provider value={value}>{children}</AppEnvContext.Provider>;
}

export function useAppEnv(): AppEnvContextValue {
  const ctx = useContext(AppEnvContext);
  if (!ctx) {
    throw new Error('useAppEnv must be used within an AppEnvProvider');
  }
  return ctx;
}

