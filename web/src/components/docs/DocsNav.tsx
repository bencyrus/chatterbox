import { Link } from 'react-router-dom';
import { HiOutlineArrowLeft, HiOutlineArrowRight } from 'react-icons/hi2';
import { DB_FIRST_ROUTES } from '../../lib/constants';
import type { DbFirstNavItem } from '../../content/db-first';
import { cn } from '../../lib/cn';

function navHref(item: DbFirstNavItem) {
  return item.slug === '' ? DB_FIRST_ROUTES.INDEX : DB_FIRST_ROUTES.page(item.slug);
}

interface DocsNavProps {
  prev: DbFirstNavItem | null;
  next: DbFirstNavItem | null;
}

export function DocsNav({ prev, next }: DocsNavProps) {
  if (!prev && !next) {
    return null;
  }

  return (
    <nav
      className="mt-16 grid gap-4 border-t border-border-secondary pt-8 sm:grid-cols-2"
      aria-label="Documentation pagination"
    >
      {prev ? (
        <Link
          to={navHref(prev)}
          className={cn(
            'group flex flex-col rounded-xl border border-border-secondary p-4 transition-colors',
            'hover:border-app-green/40 hover:bg-app-sand-light/50',
            !next && 'sm:col-span-1'
          )}
        >
          <span className="mb-1 flex items-center gap-1 text-caption font-medium uppercase tracking-wide text-text-tertiary">
            <HiOutlineArrowLeft className="h-3.5 w-3.5" />
            Previous
          </span>
          <span className="text-body-md font-semibold text-text-primary group-hover:text-app-green-deep">
            {prev.title}
          </span>
        </Link>
      ) : (
        <div />
      )}

      {next ? (
        <Link
          to={navHref(next)}
          className={cn(
            'group flex flex-col items-end rounded-xl border border-border-secondary p-4 text-right transition-colors',
            'hover:border-app-green/40 hover:bg-app-sand-light/50',
            !prev && 'sm:col-start-2'
          )}
        >
          <span className="mb-1 flex items-center gap-1 text-caption font-medium uppercase tracking-wide text-text-tertiary">
            Next
            <HiOutlineArrowRight className="h-3.5 w-3.5" />
          </span>
          <span className="text-body-md font-semibold text-text-primary group-hover:text-app-green-deep">
            {next.title}
          </span>
        </Link>
      ) : null}
    </nav>
  );
}
