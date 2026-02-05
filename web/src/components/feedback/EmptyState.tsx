import { cn } from '../../lib/cn';
import { Button } from '../ui/Button';

// ═══════════════════════════════════════════════════════════════════════════
// TYPES
// ═══════════════════════════════════════════════════════════════════════════

interface EmptyStateProps {
  /** Icon to display */
  icon?: React.ReactNode;
  /** Main title */
  title: string;
  /** Description text */
  description?: string;
  /** Primary action button text */
  actionLabel?: string;
  /** Primary action handler */
  onAction?: () => void;
  /** Additional class names */
  className?: string;
}

// ═══════════════════════════════════════════════════════════════════════════
// EMPTY STATE
// ═══════════════════════════════════════════════════════════════════════════

export function EmptyState({
  icon,
  title,
  description,
  actionLabel,
  onAction,
  className,
}: EmptyStateProps) {
  return (
    <div
      className={cn(
        'flex flex-col items-center justify-center text-center',
        'py-12 px-6',
        className
      )}
    >
      {/* Icon */}
      {icon && (
        <div className="w-16 h-16 mb-4 flex items-center justify-center text-text-tertiary">
          {icon}
        </div>
      )}

      {/* Title */}
      <h3 className="text-heading-md font-semibold text-text-primary mb-2">
        {title}
      </h3>

      {/* Description */}
      {description && (
        <p className="text-body-md text-text-secondary max-w-sm mb-6">
          {description}
        </p>
      )}

      {/* Action button */}
      {actionLabel && onAction && (
        <Button variant="primary" onClick={onAction}>
          {actionLabel}
        </Button>
      )}
    </div>
  );
}
