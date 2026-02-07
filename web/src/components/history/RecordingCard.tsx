import { useCallback } from 'react';
import { useNavigate } from 'react-router-dom';
import { HiOutlineClock } from 'react-icons/hi2';
import { cn } from '../../lib/cn';
import { formatDurationMs, parseDuration } from '../../lib/date';
import { ROUTES } from '../../lib/constants';
import type { Recording } from '../../types';

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

  // Format time
  const timeStr = recording.createdAt
    ? new Date(recording.createdAt).toLocaleString('en-US', {
        hour: 'numeric',
        minute: '2-digit',
        hour12: true,
      })
    : '';

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

      {/* Metadata row: time badge + duration badge */}
      <div className="flex items-center justify-between mt-3">
        {/* Time badge */}
        <span className="inline-flex items-center gap-1.5 px-2 py-1 rounded-md bg-black/10 text-label-sm text-text-primary/80">
          {timeStr}
        </span>

        {/* Duration badge */}
        <span className="inline-flex items-center gap-1.5 px-2 py-1 rounded-md bg-black/10 text-label-sm text-text-primary/80">
          <HiOutlineClock className="w-3.5 h-3.5" />
          {durationMs > 0 ? formatDurationMs(durationMs) : '--:--'}
        </span>
      </div>
    </button>
  );
}
