import { NavLink } from 'react-router-dom';
import { HiOutlineXMark } from 'react-icons/hi2';
import { DB_FIRST_ROUTES } from '../../lib/constants';
import { DB_FIRST_SIDEBAR_GROUPS } from '../../content/db-first';
import { cn } from '../../lib/cn';
import { useDocs } from './DocsContext';

function sidebarHref(slug: string) {
  return slug === '' ? DB_FIRST_ROUTES.INDEX : DB_FIRST_ROUTES.page(slug);
}

interface DocsSidebarProps {
  className?: string;
}

export function DocsSidebar({ className }: DocsSidebarProps) {
  const { closeSidebar } = useDocs();

  return (
    <nav
      className={cn('flex h-full flex-col', className)}
      aria-label="Documentation"
    >
      <div className="flex items-center justify-between border-b border-border-secondary px-4 py-4 lg:hidden">
        <span className="text-label-md font-semibold text-text-primary">Documentation</span>
        <button
          type="button"
          onClick={closeSidebar}
          className="rounded-lg p-2 text-text-secondary hover:bg-surface-secondary"
          aria-label="Close menu"
        >
          <HiOutlineXMark className="h-5 w-5" />
        </button>
      </div>

      <div className="flex-1 overflow-y-auto px-3 py-6">
        {DB_FIRST_SIDEBAR_GROUPS.map((group) => (
          <div key={group.section} className="mb-6 last:mb-0">
            <p className="mb-2 px-3 text-caption font-semibold uppercase tracking-wider text-text-tertiary">
              {group.section}
            </p>
            <ul className="space-y-0.5">
              {group.items.map((item) => (
                <li key={item.slug || 'index'}>
                  <NavLink
                    to={sidebarHref(item.slug)}
                    onClick={closeSidebar}
                    end={item.slug === ''}
                    className={({ isActive }) =>
                      cn(
                        'block rounded-lg px-3 py-2 text-body-sm transition-colors',
                        isActive
                          ? 'bg-app-green/20 font-medium text-app-green-deep'
                          : 'text-text-secondary hover:bg-surface-secondary hover:text-text-primary'
                      )
                    }
                  >
                    {item.title}
                  </NavLink>
                </li>
              ))}
            </ul>
          </div>
        ))}
      </div>
    </nav>
  );
}
