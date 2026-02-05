import { HiPlay, HiPause } from 'react-icons/hi2';
import { AudioProgress } from '../ui/Progress';
import { cn } from '../../lib/cn';
import { formatDurationMs } from '../../lib/date';
import { useAudioPlayer } from '../../hooks/recording/useAudioPlayer';

// ═══════════════════════════════════════════════════════════════════════════
// TYPES
// ═══════════════════════════════════════════════════════════════════════════

interface AudioPlayerProps {
  /** Unique ID for this player */
  id: string;
  /** Audio URL */
  url: string | null;
  /** Duration in milliseconds (for display before metadata loads) */
  durationMs?: number;
  /** Whether to show duration */
  showDuration?: boolean;
  /** Additional class names */
  className?: string;
}

// ═══════════════════════════════════════════════════════════════════════════
// AUDIO PLAYER
// ═══════════════════════════════════════════════════════════════════════════

export function AudioPlayer({
  id,
  url,
  durationMs,
  showDuration = true,
  className,
}: AudioPlayerProps) {
  const {
    isPlaying,
    progress,
    currentTime,
    duration,
    toggle,
    seek,
  } = useAudioPlayer({ id, url });

  // Use provided duration or calculated duration
  const displayDuration = duration > 0 ? duration * 1000 : (durationMs || 0);
  const displayCurrentTime = currentTime * 1000;

  return (
    <div className={cn('flex items-center gap-3', className)}>
      {/* Play/Pause button */}
      <button
        type="button"
        onClick={toggle}
        disabled={!url}
        className={cn(
          'w-10 h-10 flex-shrink-0 rounded-full',
          'flex items-center justify-center',
          'bg-brand-primary text-white',
          'hover:bg-brand-secondary',
          'transition-colors duration-150',
          'disabled:opacity-50 disabled:cursor-not-allowed',
          'focus:outline-none focus-visible:ring-2 focus-visible:ring-brand-primary focus-visible:ring-offset-2'
        )}
        aria-label={isPlaying ? 'Pause' : 'Play'}
      >
        {isPlaying ? (
          <HiPause className="w-5 h-5" />
        ) : (
          <HiPlay className="w-5 h-5 ml-0.5" />
        )}
      </button>

      {/* Progress bar */}
      <div className="flex-1 min-w-0">
        <AudioProgress
          progress={progress}
          onSeek={seek}
          disabled={!url}
        />
      </div>

      {/* Duration */}
      {showDuration && displayDuration > 0 && (
        <span className="text-body-sm text-text-tertiary font-mono flex-shrink-0 w-20 text-right">
          {formatDurationMs(displayCurrentTime)} / {formatDurationMs(displayDuration)}
        </span>
      )}
    </div>
  );
}
