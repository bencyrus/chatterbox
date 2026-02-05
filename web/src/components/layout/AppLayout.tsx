import { Outlet } from 'react-router-dom';
import { BottomNav } from './BottomNav';

// ═══════════════════════════════════════════════════════════════════════════
// APP LAYOUT
// ═══════════════════════════════════════════════════════════════════════════

/**
 * Main application layout with bottom navigation
 * Used for authenticated pages
 */
export function AppLayout() {
  return (
    <div className="min-h-screen bg-surface-primary flex flex-col">
      {/* Main content area */}
      <main className="flex-1 pb-20">
        <Outlet />
      </main>
      
      {/* Bottom navigation */}
      <BottomNav />
    </div>
  );
}
