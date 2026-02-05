import { cn } from '../../lib/cn';

// ═══════════════════════════════════════════════════════════════════════════
// TYPES
// ═══════════════════════════════════════════════════════════════════════════

interface SettingsSectionProps {
  /** Section title */
  title: string;
  /** Section description */
  description?: string;
  /** Child elements */
  children: React.ReactNode;
  /** Additional class names */
  className?: string;
}

// ═══════════════════════════════════════════════════════════════════════════
// SETTINGS SECTION
// ═══════════════════════════════════════════════════════════════════════════

export function SettingsSection({
  title,
  description,
  children,
  className,
}: SettingsSectionProps) {
  return (
    <section className={cn('space-y-3', className)}>
      {/* Header */}
      <div className="px-1">
        <h2 className="text-label-md font-semibold text-text-secondary uppercase tracking-wide">
          {title}
        </h2>
        {description && (
          <p className="text-body-sm text-text-tertiary mt-1">
            {description}
          </p>
        )}
      </div>

      {/* Content */}
      <div className="space-y-2">
        {children}
      </div>
    </section>
  );
}
