import { HiOutlineCalendar } from 'react-icons/hi2';
import { RecordingCard } from './RecordingCard';
import { cn } from '../../lib/cn';
import type { Recording } from '../../types';

// ═══════════════════════════════════════════════════════════════════════════
// TYPES
// ═══════════════════════════════════════════════════════════════════════════

interface RecordingGroupProps {
  /** Group label (e.g., "Today", "Yesterday", date) */
  label: string;
  /** Recordings in this group */
  recordings: Recording[];
  /** Additional class names */
  className?: string;
}

// ═══════════════════════════════════════════════════════════════════════════
// RECORDING GROUP
// ═══════════════════════════════════════════════════════════════════════════

export function RecordingGroup({
  label,
  recordings,
  className,
}: RecordingGroupProps) {
  if (recordings.length === 0) {
    return null;
  }

  return (
    <div className={cn('space-y-2', className)}>
      {/* Group header with date badge + count badge */}
      <div className="flex items-center gap-2 px-1">
        {/* Date badge */}
        <span className="inline-flex items-center gap-1.5 px-2.5 py-1.5 rounded-md bg-black/5 text-text-primary text-label-md">
          <HiOutlineCalendar className="w-3.5 h-3.5" />
          {label}
        </span>

        {/* Count badge */}
        <span className="inline-flex items-center px-2.5 py-1.5 rounded-md bg-app-green text-text-primary text-label-md">
          {recordings.length}
        </span>
      </div>

      {/* Recordings */}
      <div className="space-y-2">
        {recordings.map((recording) => (
          <RecordingCard key={recording.profileCueRecordingId} recording={recording} />
        ))}
      </div>
    </div>
  );
}
