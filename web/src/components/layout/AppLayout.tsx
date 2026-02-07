import { Outlet } from 'react-router-dom';
import { BottomNav } from './BottomNav';
import { AppHeader, AppHeaderProvider } from './AppHeader';

// ═══════════════════════════════════════════════════════════════════════════
// APP LAYOUT
// ═══════════════════════════════════════════════════════════════════════════

/**
 * Main application layout with bottom navigation
 * Used for authenticated pages
 */
export function AppLayout() {
  return (
    <AppHeaderProvider>
      <div className="min-h-screen bg-app-sand-light flex flex-col">
        <AppHeader />

        {/* Main content area */}
        <main className="flex-1 pb-20">
          <Outlet />
        </main>

        {/* Bottom navigation */}
        <BottomNav />
      </div>
    </AppHeaderProvider>
  );
}
