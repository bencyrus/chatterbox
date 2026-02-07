import { HiOutlineChevronRight } from 'react-icons/hi2';
import { Card, CardContent } from '../ui/Card';
import { cn } from '../../lib/cn';

// ═══════════════════════════════════════════════════════════════════════════
// TYPES
// ═══════════════════════════════════════════════════════════════════════════

interface SettingsRowProps {
  /** Row icon */
  icon?: React.ReactNode;
  /** Row label */
  label: string;
  /** Row value (optional) */
  value?: string;
  /** Click handler */
  onClick?: () => void;
  /** Whether to show chevron */
  showChevron?: boolean;
  /** Danger style */
  danger?: boolean;
  /** Disabled state */
  disabled?: boolean;
  /** Additional class names */
  className?: string;
}

// ═══════════════════════════════════════════════════════════════════════════
// SETTINGS ROW
// ═══════════════════════════════════════════════════════════════════════════

export function SettingsRow({
  icon,
  label,
  value,
  onClick,
  showChevron = true,
  danger = false,
  disabled = false,
  className,
}: SettingsRowProps) {
  return (
    <Card
      interactive={!!onClick && !disabled}
      onClick={disabled ? undefined : onClick}
      className={cn(
        disabled && 'opacity-50 cursor-not-allowed',
        className
      )}
    >
      <CardContent className="flex items-center gap-4 py-3">
        {/* Icon */}
        {icon && (
          <span
            className={cn(
              'w-6 h-6 flex items-center justify-center',
              danger ? 'text-error-500' : 'text-text-secondary'
            )}
          >
            {icon}
          </span>
        )}

        {/* Label */}
        <span
          className={cn(
            'flex-1 text-body-md',
            danger ? 'text-error-500' : 'text-text-primary'
          )}
        >
          {label}
        </span>

        {/* Value */}
        {value && (
          <span className="text-body-md text-text-tertiary">
            {value}
          </span>
        )}

        {/* Chevron */}
        {showChevron && onClick && (
          <HiOutlineChevronRight
            className={cn(
              'w-5 h-5',
              danger ? 'text-error-500' : 'text-text-tertiary'
            )}
          />
        )}
      </CardContent>
    </Card>
  );
}
