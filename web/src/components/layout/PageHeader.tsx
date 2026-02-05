import { useCallback } from 'react';
import { useNavigate } from 'react-router-dom';
import { HiOutlineChevronLeft } from 'react-icons/hi2';
import { cn } from '../../lib/cn';

// ═══════════════════════════════════════════════════════════════════════════
// TYPES
// ═══════════════════════════════════════════════════════════════════════════

interface PageHeaderProps {
  /** Page title */
  title: string;
  /** Optional subtitle */
  subtitle?: string;
  /** Show back button */
  showBack?: boolean;
  /** Custom back handler (defaults to navigate -1) */
  onBack?: () => void;
  /** Right side action element */
  rightAction?: React.ReactNode;
  /** Whether header is sticky */
  sticky?: boolean;
  /** Additional class names */
  className?: string;
}

// ═══════════════════════════════════════════════════════════════════════════
// PAGE HEADER
// ═══════════════════════════════════════════════════════════════════════════

export function PageHeader({
  title,
  subtitle,
  showBack = false,
  onBack,
  rightAction,
  sticky = true,
  className,
}: PageHeaderProps) {
  const navigate = useNavigate();

  const handleBack = useCallback(() => {
    if (onBack) {
      onBack();
    } else {
      navigate(-1);
    }
  }, [onBack, navigate]);

  return (
    <header
      className={cn(
        'bg-surface-primary/95 backdrop-blur-sm',
        'px-page py-4',
        sticky && 'sticky top-0 z-sticky',
        className
      )}
    >
      <div className="flex items-center justify-between">
        {/* Left: Back button or spacer */}
        <div className="w-10 flex-shrink-0">
          {showBack && (
            <button
              type="button"
              onClick={handleBack}
              className={cn(
                'w-10 h-10 -ml-2 flex items-center justify-center',
                'rounded-full',
                'text-text-secondary hover:text-text-primary',
                'hover:bg-surface-secondary',
                'transition-colors duration-150'
              )}
              aria-label="Go back"
            >
              <HiOutlineChevronLeft className="w-6 h-6" />
            </button>
          )}
        </div>

        {/* Center: Title and subtitle */}
        <div className="flex-1 text-center min-w-0">
          <h1 className="text-heading-md font-semibold text-text-primary truncate">
            {title}
          </h1>
          {subtitle && (
            <p className="text-body-sm text-text-secondary mt-0.5 truncate">
              {subtitle}
            </p>
          )}
        </div>

        {/* Right: Action or spacer */}
        <div className="w-10 flex-shrink-0 flex justify-end">
          {rightAction}
        </div>
      </div>
    </header>
  );
}
