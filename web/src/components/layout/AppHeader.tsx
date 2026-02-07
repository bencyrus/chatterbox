import {
  createContext,
  useCallback,
  useContext,
  useLayoutEffect,
  useMemo,
  useState,
} from 'react';
import { PageHeader } from './PageHeader';

// ═══════════════════════════════════════════════════════════════════════════
// TYPES
// ═══════════════════════════════════════════════════════════════════════════

interface AppHeaderConfig {
  title: string;
  subtitle?: string;
  showBack?: boolean;
  backText?: string;
  onBack?: () => void;
  rightAction?: React.ReactNode;
}

interface AppHeaderContextValue {
  config: AppHeaderConfig;
  setConfig: (config: AppHeaderConfig) => void;
}

// ═══════════════════════════════════════════════════════════════════════════
// CONTEXT
// ═══════════════════════════════════════════════════════════════════════════

const defaultConfig: AppHeaderConfig = { title: '' };

const AppHeaderContext = createContext<AppHeaderContextValue | null>(null);

function areConfigsEqual(a: AppHeaderConfig, b: AppHeaderConfig) {
  return (
    a.title === b.title &&
    a.subtitle === b.subtitle &&
    a.showBack === b.showBack &&
    a.backText === b.backText &&
    a.onBack === b.onBack &&
    a.rightAction === b.rightAction
  );
}

export function AppHeaderProvider({ children }: { children: React.ReactNode }) {
  const [config, setConfig] = useState<AppHeaderConfig>(defaultConfig);

  const setConfigSafe = useCallback((nextConfig: AppHeaderConfig) => {
    setConfig((current) =>
      areConfigsEqual(current, nextConfig) ? current : nextConfig
    );
  }, []);

  const value = useMemo(
    () => ({ config, setConfig: setConfigSafe }),
    [config, setConfigSafe]
  );

  return (
    <AppHeaderContext.Provider value={value}>
      {children}
    </AppHeaderContext.Provider>
  );
}

export function useAppHeader(config: AppHeaderConfig) {
  const context = useContext(AppHeaderContext);

  useLayoutEffect(() => {
    if (context) {
      context.setConfig(config);
    }
  }, [context, config.title, config.subtitle, config.showBack, config.backText, config.onBack, config.rightAction]);
}

export function AppHeader() {
  const context = useContext(AppHeaderContext);
  if (!context) {
    return null;
  }

  const { config } = context;
  
  // Don't render if no title and no right action
  if (!config.title && !config.rightAction) {
    return null;
  }

  return (
    <PageHeader
      title={config.title}
      subtitle={config.subtitle}
      showBack={config.showBack}
      backText={config.backText}
      onBack={config.onBack}
      rightAction={config.rightAction}
    />
  );
}
