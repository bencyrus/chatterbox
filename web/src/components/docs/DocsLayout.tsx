import { Outlet, Link } from 'react-router-dom';
import { HiOutlineBars3 } from 'react-icons/hi2';
import { MarketingHeader } from '../layout/MarketingHeader';
import { DocsProvider, useDocs } from './DocsContext';
import { DocsSidebar } from './DocsSidebar';
import { ROUTES } from '../../lib/constants';
import { cn } from '../../lib/cn';

function DocsLayoutInner() {
  const { sidebarOpen, toggleSidebar, closeSidebar } = useDocs();

  return (
    <div className="min-h-screen bg-app-sand-light">
      <MarketingHeader
        className="bg-white"
        actions={[
          <button
            key="menu"
            type="button"
            onClick={toggleSidebar}
            className="inline-flex items-center gap-2 rounded-lg border border-border-secondary px-3 py-2 text-label-md font-medium text-text-secondary hover:bg-surface-secondary lg:hidden"
            aria-label="Open documentation menu"
          >
            <HiOutlineBars3 className="h-5 w-5" />
            Menu
          </button>,
          <Link
            key="home"
            to={ROUTES.HOME}
            className="hidden rounded-lg border border-border-secondary px-3 py-2 text-label-md font-medium text-text-secondary hover:bg-surface-secondary sm:inline-block"
          >
            Back to app
          </Link>,
        ]}
      />

      <div className="mx-auto flex max-w-[90rem]">
        {/* Mobile overlay */}
        {sidebarOpen ? (
          <button
            type="button"
            className="fixed inset-0 z-40 bg-black/30 lg:hidden"
            aria-label="Close menu overlay"
            onClick={closeSidebar}
          />
        ) : null}

        {/* Sidebar */}
        <aside
          className={cn(
            'fixed inset-y-0 left-0 z-50 w-72 transform border-r border-border-secondary bg-white pt-[73px] transition-transform duration-200 lg:static lg:z-auto lg:translate-x-0 lg:pt-0',
            sidebarOpen ? 'translate-x-0' : '-translate-x-full lg:translate-x-0'
          )}
        >
          <DocsSidebar className="h-[calc(100vh-73px)] lg:h-[calc(100vh-65px)] lg:sticky lg:top-[65px]" />
        </aside>

        {/* Main content */}
        <main className="min-w-0 flex-1">
          <Outlet />
        </main>
      </div>
    </div>
  );
}

export function DocsLayout() {
  return (
    <DocsProvider>
      <DocsLayoutInner />
    </DocsProvider>
  );
}
