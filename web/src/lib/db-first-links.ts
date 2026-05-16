import { DB_FIRST_ROUTES } from './constants';

/** Maps markdown file paths to route slugs */
const MD_PATH_TO_SLUG: Record<string, string> = {
  'README.md': '',
  'philosophy/manifesto.md': 'manifesto',
  'architecture/overview.md': 'architecture',
  'architecture/gateway.md': 'gateway',
  'architecture/workers.md': 'workers',
  'patterns/database-patterns.md': 'patterns',
  'security/overview.md': 'security',
  'observability/overview.md': 'observability',
  'guides/getting-started.md': 'getting-started',
};

function normalizeMdPath(href: string): string | null {
  const trimmed = href.trim();
  if (!trimmed.endsWith('.md')) {
    return null;
  }

  let path = trimmed.replace(/^\.\//, '');
  while (path.startsWith('../')) {
    path = path.slice(3);
  }

  return path;
}

/**
 * Resolve a markdown link to an in-app /db-first route, or null if external/anchor-only.
 */
export function resolveDbFirstDocHref(href: string): string | null {
  if (!href || href.startsWith('http://') || href.startsWith('https://') || href.startsWith('#')) {
    return null;
  }

  const path = normalizeMdPath(href);
  if (!path) {
    return null;
  }

  const slug = MD_PATH_TO_SLUG[path];
  if (slug === undefined) {
    return null;
  }

  return slug === '' ? DB_FIRST_ROUTES.INDEX : DB_FIRST_ROUTES.page(slug);
}
