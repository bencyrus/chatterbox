import { useEffect, useState } from 'react';
import { cn } from '../../lib/cn';
import { DB_FIRST_CONTENT_ID } from './DocsContext';

interface TocEntry {
  id: string;
  text: string;
  level: 2 | 3;
}

interface TableOfContentsProps {
  contentKey: string;
}

export function TableOfContents({ contentKey }: TableOfContentsProps) {
  const [headings, setHeadings] = useState<TocEntry[]>([]);
  const [activeId, setActiveId] = useState<string>('');

  useEffect(() => {
    const container = document.getElementById(DB_FIRST_CONTENT_ID);
    if (!container) {
      setHeadings([]);
      return;
    }

    const nodes = container.querySelectorAll('h2, h3');
    const entries: TocEntry[] = [];

    nodes.forEach((node) => {
      const id = node.id;
      if (!id) return;
      const level = node.tagName === 'H2' ? 2 : 3;
      entries.push({ id, text: node.textContent ?? '', level });
    });

    setHeadings(entries);
    setActiveId(entries[0]?.id ?? '');

    const observer = new IntersectionObserver(
      (observed) => {
        const visible = observed
          .filter((e) => e.isIntersecting)
          .sort((a, b) => (a.boundingClientRect.top ?? 0) - (b.boundingClientRect.top ?? 0));

        if (visible[0]?.target.id) {
          setActiveId(visible[0].target.id);
        }
      },
      {
        rootMargin: '-80px 0px -70% 0px',
        threshold: 0,
      }
    );

    nodes.forEach((node) => observer.observe(node));

    return () => observer.disconnect();
  }, [contentKey]);

  if (headings.length === 0) {
    return null;
  }

  return (
    <nav className="hidden xl:block" aria-label="On this page">
      <p className="mb-3 text-label-sm font-semibold uppercase tracking-wider text-text-tertiary">
        On this page
      </p>
      <ul className="space-y-1 border-l border-border-secondary">
        {headings.map((heading) => (
          <li key={heading.id}>
            <a
              href={`#${heading.id}`}
              className={cn(
                'block border-l-2 py-1 text-body-sm transition-colors -ml-px',
                heading.level === 3 && 'pl-6',
                heading.level === 2 && 'pl-4',
                activeId === heading.id
                  ? 'border-app-green-strong font-medium text-app-green-deep'
                  : 'border-transparent text-text-tertiary hover:border-border-strong hover:text-text-secondary'
              )}
              onClick={(e) => {
                e.preventDefault();
                document.getElementById(heading.id)?.scrollIntoView({ behavior: 'smooth' });
                setActiveId(heading.id);
              }}
            >
              {heading.text}
            </a>
          </li>
        ))}
      </ul>
    </nav>
  );
}
