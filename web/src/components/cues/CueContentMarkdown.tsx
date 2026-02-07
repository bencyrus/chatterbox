import { cn } from '../../lib/cn';
import { parseContentLines } from '../../lib/markdown';

// ═══════════════════════════════════════════════════════════════════════════
// TYPES
// ═══════════════════════════════════════════════════════════════════════════

interface CueContentMarkdownProps {
  /** Main prompt / title */
  title?: string;
  /** Additional details (line-by-line with ### headings, * bullets) */
  details?: string;
  /** Additional class names for the wrapper */
  className?: string;
  /** Center text (e.g. for cue detail card) */
  center?: boolean;
}

// ═══════════════════════════════════════════════════════════════════════════
// COMPONENT
// ═══════════════════════════════════════════════════════════════════════════

/**
 * Renders cue content matching iOS:
 * - Title as heading
 * - Details parsed line-by-line:
 *   - ### prefix → subheading
 *   - * or - prefix → bullet point
 *   - empty → spacer
 *   - otherwise → body text
 */
export function CueContentMarkdown({
  title,
  details,
  className,
  center = false,
}: CueContentMarkdownProps) {
  if (!title && !details) {
    return (
      <p className="text-body-md text-text-secondary">
        No prompt available
      </p>
    );
  }

  const parsedLines = details ? parseContentLines(details) : [];

  return (
    <div className={cn('space-y-4', center && 'text-center', className)}>
      {/* Title */}
      {title && (
        <p className="text-heading-lg font-semibold text-text-primary leading-relaxed">
          {title}
        </p>
      )}

      {/* Details (parsed lines) */}
      {parsedLines.length > 0 && (
        <div className={cn('space-y-2', center ? 'text-center' : 'text-left')}>
          {parsedLines.map((line, index) => {
            switch (line.type) {
              case 'heading':
                return (
                  <p
                    key={index}
                    className="text-body-md font-semibold text-text-primary mt-4"
                  >
                    {line.content}
                  </p>
                );

              case 'bullet':
                return (
                  <div key={index} className="flex gap-2 items-start">
                    <span className="text-body-md text-text-primary mt-0.5">•</span>
                    <p className="text-body-md font-normal text-text-secondary flex-1">
                      {line.content}
                    </p>
                  </div>
                );

              case 'spacer':
                return <div key={index} className="h-1" />;

              case 'text':
                return (
                  <p key={index} className="text-body-md font-normal text-text-primary">
                    {line.content}
                  </p>
                );

              default:
                return null;
            }
          })}
        </div>
      )}
    </div>
  );
}
