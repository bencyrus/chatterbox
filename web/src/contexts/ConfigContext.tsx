import {
  createContext,
  useContext,
  useState,
  useCallback,
  useEffect,
  type ReactNode,
} from 'react';
import type { AppConfigResponse } from '../types';
import { authApi } from '../services/auth';

// ═══════════════════════════════════════════════════════════════════════════
// TYPES
// ═══════════════════════════════════════════════════════════════════════════

interface ConfigState {
  config: AppConfigResponse | null;
  isLoading: boolean;
  error: string | null;
}

interface ConfigContextValue extends ConfigState {
  refreshConfig: () => Promise<void>;
}

// ═══════════════════════════════════════════════════════════════════════════
// CONTEXT
// ═══════════════════════════════════════════════════════════════════════════

const ConfigContext = createContext<ConfigContextValue | null>(null);

// ═══════════════════════════════════════════════════════════════════════════
// PROVIDER
// ═══════════════════════════════════════════════════════════════════════════

interface ConfigProviderProps {
  children: ReactNode;
}

export function ConfigProvider({ children }: ConfigProviderProps) {
  const [config, setConfig] = useState<AppConfigResponse | null>(null);
  const [isLoading, setIsLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);

  // ─────────────────────────────────────────────────────────────────────────
  // Fetch config
  // ─────────────────────────────────────────────────────────────────────────

  const refreshConfig = useCallback(async () => {
    setIsLoading(true);
    setError(null);
    
    try {
      const response = await authApi.appConfig();
      setConfig(response);
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Failed to load configuration');
      console.error('Failed to fetch app config:', err);
    } finally {
      setIsLoading(false);
    }
  }, []);

  // ─────────────────────────────────────────────────────────────────────────
  // Load config on mount
  // ─────────────────────────────────────────────────────────────────────────

  useEffect(() => {
    refreshConfig();
  }, [refreshConfig]);

  // ─────────────────────────────────────────────────────────────────────────
  // Value
  // ─────────────────────────────────────────────────────────────────────────

  const value: ConfigContextValue = {
    config,
    isLoading,
    error,
    refreshConfig,
  };

  return (
    <ConfigContext.Provider value={value}>
      {children}
    </ConfigContext.Provider>
  );
}

// ═══════════════════════════════════════════════════════════════════════════
// HOOK
// ═══════════════════════════════════════════════════════════════════════════

export function useConfig(): ConfigContextValue {
  const context = useContext(ConfigContext);
  if (!context) {
    throw new Error('useConfig must be used within a ConfigProvider');
  }
  return context;
}

// ═══════════════════════════════════════════════════════════════════════════
// HELPER HOOKS
// ═══════════════════════════════════════════════════════════════════════════

/**
 * Get available languages from config
 */
export function useAvailableLanguages(): string[] {
  const { config } = useConfig();
  return config?.availableLanguageCodes ?? [];
}
