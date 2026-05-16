import readmeMd from '@db-first-docs/README.md?raw';
import manifestoMd from '@db-first-docs/philosophy/manifesto.md?raw';
import architectureMd from '@db-first-docs/architecture/overview.md?raw';
import gatewayMd from '@db-first-docs/architecture/gateway.md?raw';
import workersMd from '@db-first-docs/architecture/workers.md?raw';
import patternsMd from '@db-first-docs/patterns/database-patterns.md?raw';
import securityMd from '@db-first-docs/security/overview.md?raw';
import observabilityMd from '@db-first-docs/observability/overview.md?raw';
import gettingStartedMd from '@db-first-docs/guides/getting-started.md?raw';

export type DbFirstDocSection =
  | 'Introduction'
  | 'Philosophy'
  | 'Architecture'
  | 'Patterns'
  | 'Security'
  | 'Observability'
  | 'Guides';

export interface DbFirstDocPage {
  slug: string;
  title: string;
  description: string;
  section: DbFirstDocSection;
  content: string;
}

export const DB_FIRST_PAGES: DbFirstDocPage[] = [
  {
    slug: 'manifesto',
    title: 'The Manifesto',
    description: 'Core thesis, seven principles, and the fundamental shift in thinking',
    section: 'Philosophy',
    content: manifestoMd,
  },
  {
    slug: 'architecture',
    title: 'System Architecture',
    description: 'Component map, data flows, and infrastructure topology',
    section: 'Architecture',
    content: architectureMd,
  },
  {
    slug: 'gateway',
    title: 'The Gateway',
    description: 'Thin, replaceable reverse proxy with zero business logic',
    section: 'Architecture',
    content: gatewayMd,
  },
  {
    slug: 'workers',
    title: 'Supervisors & Workers',
    description: 'Background processing via Facts → Logic → Effects',
    section: 'Architecture',
    content: workersMd,
  },
  {
    slug: 'patterns',
    title: 'Database Patterns',
    description: 'Schema organization, audit trails, outbox, queues, and more',
    section: 'Patterns',
    content: patternsMd,
  },
  {
    slug: 'security',
    title: 'Security',
    description: 'Auth, RLS, encryption, and secrets management',
    section: 'Security',
    content: securityMd,
  },
  {
    slug: 'observability',
    title: 'Observability',
    description: 'Observe, don’t test — monitoring from the database out',
    section: 'Observability',
    content: observabilityMd,
  },
  {
    slug: 'getting-started',
    title: 'Getting Started',
    description: 'From zero to a running database-first system',
    section: 'Guides',
    content: gettingStartedMd,
  },
];

export const DB_FIRST_INDEX = {
  title: 'Database-First Development',
  description: 'Build systems where PostgreSQL is the application',
  section: 'Introduction' as const,
  content: readmeMd,
};

export const DB_FIRST_PAGE_BY_SLUG = Object.fromEntries(
  DB_FIRST_PAGES.map((page) => [page.slug, page])
) as Record<string, DbFirstDocPage>;

export interface DbFirstNavItem {
  slug: string;
  title: string;
}

/** Reading order for prev/next navigation */
export const DB_FIRST_READING_ORDER: DbFirstNavItem[] = [
  { slug: 'manifesto', title: 'The Manifesto' },
  { slug: 'architecture', title: 'System Architecture' },
  { slug: 'getting-started', title: 'Getting Started' },
  { slug: 'patterns', title: 'Database Patterns' },
  { slug: 'workers', title: 'Supervisors & Workers' },
  { slug: 'gateway', title: 'The Gateway' },
  { slug: 'security', title: 'Security' },
  { slug: 'observability', title: 'Observability' },
];

export interface DbFirstSidebarGroup {
  section: DbFirstDocSection;
  items: DbFirstNavItem[];
}

export const DB_FIRST_SIDEBAR_GROUPS: DbFirstSidebarGroup[] = [
  {
    section: 'Introduction',
    items: [{ slug: '', title: 'Overview' }],
  },
  {
    section: 'Philosophy',
    items: [{ slug: 'manifesto', title: 'The Manifesto' }],
  },
  {
    section: 'Architecture',
    items: [
      { slug: 'architecture', title: 'System Architecture' },
      { slug: 'gateway', title: 'The Gateway' },
      { slug: 'workers', title: 'Supervisors & Workers' },
    ],
  },
  {
    section: 'Patterns',
    items: [{ slug: 'patterns', title: 'Database Patterns' }],
  },
  {
    section: 'Security',
    items: [{ slug: 'security', title: 'Security' }],
  },
  {
    section: 'Observability',
    items: [{ slug: 'observability', title: 'Observability' }],
  },
  {
    section: 'Guides',
    items: [{ slug: 'getting-started', title: 'Getting Started' }],
  },
];

export function getDbFirstPrevNext(slug: string | undefined): {
  prev: DbFirstNavItem | null;
  next: DbFirstNavItem | null;
} {
  if (!slug) {
    return {
      prev: null,
      next: DB_FIRST_READING_ORDER[0] ?? null,
    };
  }

  const index = DB_FIRST_READING_ORDER.findIndex((item) => item.slug === slug);
  if (index === -1) {
    return { prev: null, next: null };
  }

  return {
    prev: index > 0 ? DB_FIRST_READING_ORDER[index - 1]! : { slug: '', title: 'Overview' },
    next: index < DB_FIRST_READING_ORDER.length - 1 ? DB_FIRST_READING_ORDER[index + 1]! : null,
  };
}

export interface DocHeading {
  id: string;
  text: string;
  level: 2 | 3;
}

/** Extract H2/H3 headings from markdown for table of contents */
export function extractDocHeadings(markdown: string): DocHeading[] {
  const headings: DocHeading[] = [];
  const lines = markdown.split('\n');

  for (const line of lines) {
    const match = /^(#{2,3})\s+(.+)$/.exec(line);
    if (!match) continue;

    const level = match[1]!.length as 2 | 3;
    const text = match[2]!.replace(/\*\*/g, '').replace(/`/g, '').trim();
    const id = slugifyHeading(text);
    headings.push({ id, text, level });
  }

  return headings;
}

function slugifyHeading(text: string): string {
  return text
    .toLowerCase()
    .replace(/[^\w\s-]/g, '')
    .replace(/\s+/g, '-')
    .replace(/-+/g, '-')
    .trim();
}
