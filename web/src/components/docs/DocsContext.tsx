import { createContext, useCallback, useContext, useMemo, useState } from 'react';

interface DocsContextValue {
  sidebarOpen: boolean;
  openSidebar: () => void;
  closeSidebar: () => void;
  toggleSidebar: () => void;
  contentContainerId: string;
}

const DocsContext = createContext<DocsContextValue | null>(null);

export const DB_FIRST_CONTENT_ID = 'db-first-doc-content';

export function DocsProvider({ children }: { children: React.ReactNode }) {
  const [sidebarOpen, setSidebarOpen] = useState(false);

  const openSidebar = useCallback(() => setSidebarOpen(true), []);
  const closeSidebar = useCallback(() => setSidebarOpen(false), []);
  const toggleSidebar = useCallback(() => setSidebarOpen((v) => !v), []);

  const value = useMemo(
    () => ({
      sidebarOpen,
      openSidebar,
      closeSidebar,
      toggleSidebar,
      contentContainerId: DB_FIRST_CONTENT_ID,
    }),
    [sidebarOpen, openSidebar, closeSidebar, toggleSidebar]
  );

  return <DocsContext.Provider value={value}>{children}</DocsContext.Provider>;
}

export function useDocs() {
  const ctx = useContext(DocsContext);
  if (!ctx) {
    throw new Error('useDocs must be used within DocsProvider');
  }
  return ctx;
}
