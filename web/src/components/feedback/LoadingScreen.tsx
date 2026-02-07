import { Spinner } from '../ui/Spinner';
import { cn } from '../../lib/cn';

// ═══════════════════════════════════════════════════════════════════════════
// TYPES
// ═══════════════════════════════════════════════════════════════════════════

interface LoadingScreenProps {
  /** Optional message to display */
  message?: string;
  /** Whether to show full screen */
  fullScreen?: boolean;
  /** Additional class names */
  className?: string;
}

// ═══════════════════════════════════════════════════════════════════════════
// LOADING SCREEN
// ═══════════════════════════════════════════════════════════════════════════

export function LoadingScreen({
  message,
  fullScreen = true,
  className,
}: LoadingScreenProps) {
  return (
    <div
      className={cn(
        'flex flex-col items-center justify-center',
        fullScreen && 'min-h-screen bg-app-sand-light',
        !fullScreen && 'py-12',
        className
      )}
    >
      <Spinner size="lg" className="mb-4" />
      {message && (
        <p className="text-body-md text-text-secondary">{message}</p>
      )}
    </div>
  );
}
