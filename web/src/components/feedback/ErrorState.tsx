import { HiOutlineExclamationTriangle } from 'react-icons/hi2';
import { cn } from '../../lib/cn';
import { Button } from '../ui/Button';

// ═══════════════════════════════════════════════════════════════════════════
// TYPES
// ═══════════════════════════════════════════════════════════════════════════

interface ErrorStateProps {
  /** Error title */
  title?: string;
  /** Error message */
  message?: string;
  /** Retry button handler */
  onRetry?: () => void;
  /** Additional class names */
  className?: string;
}

// ═══════════════════════════════════════════════════════════════════════════
// ERROR STATE
// ═══════════════════════════════════════════════════════════════════════════

export function ErrorState({
  title = 'Something went wrong',
  message = 'We couldn\'t load this content. Please try again.',
  onRetry,
  className,
}: ErrorStateProps) {
  return (
    <div
      className={cn(
        'flex flex-col items-center justify-center text-center',
        'py-12 px-6',
        className
      )}
    >
      {/* Icon */}
      <div className="w-16 h-16 mb-4 rounded-full bg-error-100 flex items-center justify-center">
        <HiOutlineExclamationTriangle className="w-8 h-8 text-error-500" />
      </div>

      {/* Title */}
      <h3 className="text-heading-md font-semibold text-text-primary mb-2">
        {title}
      </h3>

      {/* Message */}
      <p className="text-body-md text-text-secondary max-w-sm mb-6">
        {message}
      </p>

      {/* Retry button */}
      {onRetry && (
        <Button variant="secondary" onClick={onRetry}>
          Try again
        </Button>
      )}
    </div>
  );
}
