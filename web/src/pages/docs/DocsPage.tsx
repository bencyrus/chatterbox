import { useMemo } from 'react';
import { Navigate, useParams } from 'react-router-dom';
import {
  DB_FIRST_PAGE_BY_SLUG,
  getDbFirstPrevNext,
} from '../../content/db-first';
import { stripLeadingH1 } from '../../lib/strip-leading-h1';
import { MarkdownRenderer } from '../../components/docs/MarkdownRenderer';
import { TableOfContents } from '../../components/docs/TableOfContents';
import { DocsNav } from '../../components/docs/DocsNav';
import { DB_FIRST_CONTENT_ID } from '../../components/docs/DocsContext';
import { DB_FIRST_ROUTES } from '../../lib/constants';

export default function DocsPage() {
  const { slug } = useParams<{ slug: string }>();
  const page = slug ? DB_FIRST_PAGE_BY_SLUG[slug] : undefined;

  const content = useMemo(
    () => (page ? stripLeadingH1(page.content) : ''),
    [page]
  );

  const { prev, next } = getDbFirstPrevNext(slug);

  if (!page) {
    return <Navigate to={DB_FIRST_ROUTES.INDEX} replace />;
  }

  return (
    <div className="px-6 py-10 lg:px-10 xl:pr-4">
      <div className="mx-auto flex max-w-6xl gap-10 xl:gap-12">
        <article className="min-w-0 flex-1 max-w-3xl">
          <header className="mb-8">
            <p className="mb-2 text-label-sm font-semibold uppercase tracking-wider text-app-green-deep">
              {page.section}
            </p>
            <h1 className="text-display-sm font-bold tracking-tight text-text-primary">
              {page.title}
            </h1>
            <p className="mt-3 text-body-lg text-text-secondary">{page.description}</p>
          </header>

          <div id={DB_FIRST_CONTENT_ID}>
            <MarkdownRenderer content={content} />
          </div>

          <DocsNav prev={prev} next={next} />
        </article>

        <aside className="w-56 shrink-0">
          <div className="sticky top-24">
            <TableOfContents contentKey={slug ?? ''} />
          </div>
        </aside>
      </div>
    </div>
  );
}
