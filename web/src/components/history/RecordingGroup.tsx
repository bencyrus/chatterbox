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
    <div className={cn('space-y-3', className)}>
      {/* Group header */}
      <h3 className="text-label-md font-semibold text-text-secondary uppercase tracking-wide px-1">
        {label}
      </h3>

      {/* Recordings */}
      <div className="space-y-2">
        {recordings.map((recording) => (
          <RecordingCard key={recording.id} recording={recording} />
        ))}
      </div>
    </div>
  );
}
