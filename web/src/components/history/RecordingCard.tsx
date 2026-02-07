import { useCallback } from 'react';
import { useNavigate } from 'react-router-dom';
import { HiOutlineCalendar, HiOutlineClock } from 'react-icons/hi2';
import { cn } from '../../lib/cn';
import { formatDurationMs, parseDuration } from '../../lib/date';
import { ROUTES } from '../../lib/constants';
import type { Recording } from '../../types';

// ═══════════════════════════════════════════════════════════════════════════
// HELPERS
// ═══════════════════════════════════════════════════════════════════════════

function formatCardDate(dateStr: string): string {
  const date = new Date(dateStr);
  const now = new Date();

  const isToday =
    date.getDate() === now.getDate() &&
    date.getMonth() === now.getMonth() &&
    date.getFullYear() === now.getFullYear();

  if (isToday) return 'Today';

  const yesterday = new Date(now);
  yesterday.setDate(yesterday.getDate() - 1);
  const isYesterday =
    date.getDate() === yesterday.getDate() &&
    date.getMonth() === yesterday.getMonth() &&
    date.getFullYear() === yesterday.getFullYear();

  if (isYesterday) return 'Yesterday';

  return date.toLocaleDateString('en-US', {
    day: 'numeric',
    month: 'short',
    year: 'numeric',
  });
}

// ═══════════════════════════════════════════════════════════════════════════
// TYPES
// ═══════════════════════════════════════════════════════════════════════════

interface RecordingCardProps {
  /** Recording data */
  recording: Recording;
  /** Additional class names */
  className?: string;
}

// ═══════════════════════════════════════════════════════════════════════════
// RECORDING CARD
// ═══════════════════════════════════════════════════════════════════════════

export function RecordingCard({ recording, className }: RecordingCardProps) {
  const navigate = useNavigate();

  const handleClick = useCallback(() => {
    navigate(ROUTES.RECORDING_DETAIL.replace(':recordingId', String(recording.profileCueRecordingId)));
  }, [navigate, recording.profileCueRecordingId]);

  // Get cue text (title)
  const cueText = recording.cue?.content?.title || 'Recording';

  // Get duration from file metadata
  const durationStr = recording.file?.metadata?.duration;
  const durationMs = durationStr ? parseDuration(durationStr) : 0;

  // Format date
  const dateLabel = recording.createdAt ? formatCardDate(recording.createdAt) : '';

  return (
    <button
      type="button"
      onClick={handleClick}
      className={cn(
        'w-full text-left bg-app-beige rounded-xl p-4',
        'transition-colors hover:bg-app-beige-hover',
        'focus:outline-none focus-visible:ring-2 focus-visible:ring-app-green-strong focus-visible:ring-offset-1',
        className
      )}
    >
      {/* Cue title */}
      <p className="text-body-md font-medium text-text-primary line-clamp-2 leading-snug">
        {cueText}
      </p>

      {/* Metadata row: date badge + duration badge */}
      <div className="flex items-center justify-between mt-3">
        {/* Date badge */}
        {dateLabel && (
          <span className="inline-flex items-center gap-1.5 px-2 py-1 rounded-md bg-black/10 text-label-sm text-text-primary/80">
            <HiOutlineCalendar className="w-3.5 h-3.5" />
            {dateLabel}
          </span>
        )}

        {/* Duration badge */}
        <span className="inline-flex items-center gap-1.5 px-2 py-1 rounded-md bg-black/10 text-label-sm text-text-primary/80">
          <HiOutlineClock className="w-3.5 h-3.5" />
          {durationMs > 0 ? formatDurationMs(durationMs) : '--:--'}
        </span>
      </div>
    </button>
  );
}
