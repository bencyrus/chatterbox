import { useMemo } from 'react';
import ReactMarkdown, { type Components } from 'react-markdown';
import remarkGfm from 'remark-gfm';
import rehypeSlug from 'rehype-slug';
import rehypeAutolinkHeadings from 'rehype-autolink-headings';
import { Link } from 'react-router-dom';
import { resolveDbFirstDocHref } from '../../lib/db-first-links';
import { cn } from '../../lib/cn';
import { CodeBlock } from './CodeBlock';
import { MermaidDiagram } from './MermaidDiagram';

interface MarkdownRendererProps {
  content: string;
  className?: string;
}

export function MarkdownRenderer({ content, className }: MarkdownRendererProps) {
  const components = useMemo<Components>(
    () => ({
      h1: ({ children }) => (
        <h1 className="mb-6 mt-2 text-display-sm font-bold tracking-tight text-text-primary first:mt-0">
          {children}
        </h1>
      ),
      h2: ({ children, id }) => (
        <h2
          id={id}
          className="mb-4 mt-12 scroll-mt-28 border-b border-border-secondary pb-2 text-heading-lg font-semibold text-text-primary first:mt-8"
        >
          {children}
        </h2>
      ),
      h3: ({ children, id }) => (
        <h3
          id={id}
          className="mb-3 mt-8 scroll-mt-28 text-heading-md font-semibold text-text-primary"
        >
          {children}
        </h3>
      ),
      p: ({ children }) => (
        <p className="mb-4 text-body-md leading-relaxed text-text-secondary">{children}</p>
      ),
      ul: ({ children }) => (
        <ul className="mb-4 ml-6 list-disc space-y-2 text-body-md text-text-secondary">{children}</ul>
      ),
      ol: ({ children }) => (
        <ol className="mb-4 ml-6 list-decimal space-y-2 text-body-md text-text-secondary">{children}</ol>
      ),
      li: ({ children }) => <li className="leading-relaxed">{children}</li>,
      blockquote: ({ children }) => (
        <blockquote className="my-6 border-l-4 border-app-green-strong bg-app-sand-light/80 py-3 pl-5 pr-4 text-body-md italic text-text-secondary">
          {children}
        </blockquote>
      ),
      hr: () => <hr className="my-10 border-border-secondary" />,
      strong: ({ children }) => (
        <strong className="font-semibold text-text-primary">{children}</strong>
      ),
      a: ({ href, children }) => {
        const resolved = href ? resolveDbFirstDocHref(href) : null;
        if (resolved) {
          return (
            <Link
              to={resolved}
              className="font-medium text-app-green-deep underline decoration-app-green/40 underline-offset-2 hover:decoration-app-green-deep"
            >
              {children}
            </Link>
          );
        }
        const external = href?.startsWith('http');
        return (
          <a
            href={href}
            className="font-medium text-app-green-deep underline decoration-app-green/40 underline-offset-2 hover:decoration-app-green-deep"
            {...(external ? { target: '_blank', rel: 'noopener noreferrer' } : {})}
          >
            {children}
          </a>
        );
      },
      table: ({ children }) => (
        <div className="my-6 overflow-x-auto rounded-lg border border-border-secondary">
          <table className="min-w-full divide-y divide-border-secondary text-body-sm">
            {children}
          </table>
        </div>
      ),
      thead: ({ children }) => <thead className="bg-surface-secondary">{children}</thead>,
      tbody: ({ children }) => (
        <tbody className="divide-y divide-border-secondary bg-white">{children}</tbody>
      ),
      tr: ({ children }) => <tr>{children}</tr>,
      th: ({ children }) => (
        <th className="px-4 py-3 text-left text-label-sm font-semibold uppercase tracking-wide text-text-secondary">
          {children}
        </th>
      ),
      td: ({ children }) => (
        <td className="px-4 py-3 text-text-secondary">{children}</td>
      ),
      code: ({ className, children }) => {
        const text = String(children).replace(/\n$/, '');
        const match = /language-(\w+)/.exec(className ?? '');
        const isBlock = match !== null || text.includes('\n');

        if (!isBlock) {
          return (
            <code className="rounded bg-surface-tertiary px-1.5 py-0.5 font-mono text-[0.875em] text-app-green-deep">
              {children}
            </code>
          );
        }

        const lang = match?.[1];
        if (lang === 'mermaid') {
          return <MermaidDiagram chart={text} />;
        }

        return <CodeBlock language={lang}>{text}</CodeBlock>;
      },
      pre: ({ children }) => <>{children}</>,
    }),
    []
  );

  return (
    <ReactMarkdown
      className={cn(
        'docs-prose max-w-none',
        className
      )}
      remarkPlugins={[remarkGfm]}
      rehypePlugins={[
        rehypeSlug,
        [rehypeAutolinkHeadings, { behavior: 'wrap' }],
      ]}
      components={components}
    >
      {content}
    </ReactMarkdown>
  );
}
