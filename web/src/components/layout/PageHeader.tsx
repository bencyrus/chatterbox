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
        'bg-app-sand-light/95 backdrop-blur-sm',
        'h-16',
        sticky && 'sticky top-0 z-sticky',
        className
      )}
    >
      <div className="max-w-3xl mx-auto px-page-x h-full grid grid-cols-[auto,1fr,auto] items-center gap-3">
        {/* Left: Back button or spacer */}
        <div
          className={cn(
            'flex items-center',
            showBack ? 'min-w-0' : 'w-0 overflow-hidden'
          )}
        >
          {showBack && (
            <button
              type="button"
              onClick={handleBack}
              className={cn(
                'flex items-center gap-1.5 py-2.5 pl-2 pr-3 -ml-2',
                'rounded-full min-h-[44px]',
                'bg-white text-text-primary font-medium',
                'hover:bg-black/10',
                'active:bg-black/10',
                'transition-colors duration-150',
                'shadow-sm'
              )}
              aria-label="Go back"
            >
              <HiOutlineChevronLeft className="w-5 h-5 shrink-0" />
              <span className="text-body-md">Back</span>
            </button>
          )}
        </div>

        {/* Center: Title and subtitle */}
        <div className="flex-1 text-left min-w-0 flex items-center">
          {title && (
            <h1 className="text-heading-md font-semibold text-text-primary truncate">
              {title}
            </h1>
          )}
          {subtitle && (
            <p className="text-body-sm text-text-secondary mt-0.5 truncate">
              {subtitle}
            </p>
          )}
        </div>

        {/* Right: Action or spacer */}
        <div className="flex items-center justify-end min-w-0">
          {rightAction}
        </div>
      </div>
    </header>
  );
}
