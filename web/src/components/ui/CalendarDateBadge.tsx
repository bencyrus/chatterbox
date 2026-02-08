import { HiOutlineCalendar } from 'react-icons/hi2';
import { MetaBadge } from './MetaBadge';
import { formatStandardDate, formatStandardDateTime } from '../../lib/date';

// ═══════════════════════════════════════════════════════════════════════════
// TYPES
// ═══════════════════════════════════════════════════════════════════════════

type CalendarDateBadgeMode = 'date' | 'dateTime';

interface CalendarDateBadgeProps {
  /** Pre-formatted label (e.g. "Today", "Yesterday", "Jan 15, 2024") */
  label?: string;
  /** Date value to format */
  date?: Date | string;
  /** If true, show date + time. */
  showTime?: boolean;
  /**
   * Formatting mode when using `date`.
   * Prefer `showTime` for consistency.
   */
  mode?: CalendarDateBadgeMode;
  className?: string;
}

// ═══════════════════════════════════════════════════════════════════════════
// COMPONENT
// ═══════════════════════════════════════════════════════════════════════════

export function CalendarDateBadge({
  label,
  date,
  showTime,
  mode = 'date',
  className,
}: CalendarDateBadgeProps) {
  const effectiveMode: CalendarDateBadgeMode =
    showTime === true ? 'dateTime' : mode;

  const text =
    label ??
    (date
      ? effectiveMode === 'dateTime'
        ? formatStandardDateTime(date)
        : formatStandardDate(date)
      : '');

  if (!text) return null;

  return (
    <MetaBadge className={className} tone="neutral" size="md">
      <HiOutlineCalendar className="w-3.5 h-3.5" />
      {text}
    </MetaBadge>
  );
}

