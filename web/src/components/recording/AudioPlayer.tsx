import { HiPlay, HiPause } from 'react-icons/hi2';
import { MdReplay10, MdForward10 } from 'react-icons/md';
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
    currentTime,
    duration,
    toggle,
    seek,
  } = useAudioPlayer({ id, url });

  // Use provided duration or calculated duration (guard against invalid values)
  const displayDuration = (isFinite(duration) && duration > 0) ? duration * 1000 : (durationMs || 0);
  const displayCurrentTime = isFinite(currentTime) ? currentTime * 1000 : 0;

  return (
    <div className={cn('space-y-3', className)}>
      {/* Progress slider */}
      <div className="px-1">
        <AudioProgress
          currentTime={currentTime}
          duration={duration}
          onSeek={seek}
        />
      </div>

      {/* Time display */}
      {showDuration && displayDuration > 0 && (
        <div className="flex justify-between text-caption text-text-primary px-1">
          <span>{formatDurationMs(displayCurrentTime)}</span>
          <span>{formatDurationMs(displayDuration)}</span>
        </div>
      )}

      {/* Playback controls */}
      <div className="flex items-center justify-center gap-10">
        {/* Skip backward 10s */}
        <button
          type="button"
          onClick={() => seek(Math.max(0, currentTime - 10))}
          disabled={!url}
          className={cn(
            'flex-shrink-0 rounded-full',
            'flex items-center justify-center',
            'text-text-primary',
            'hover:bg-black/10',
            'transition-all duration-150',
            'disabled:opacity-50 disabled:cursor-not-allowed',
            'active:scale-95',
            'p-2'
          )}
          aria-label="Skip backward 10 seconds"
        >
          <MdReplay10 className="w-9 h-9" />
        </button>

        {/* Play/Pause */}
        <button
          type="button"
          onClick={toggle}
          disabled={!url}
          className={cn(
            'w-11 h-11 flex-shrink-0 rounded-full',
            'flex items-center justify-center',
            'bg-transparent text-text-primary',
            'transition-transform duration-150',
            'disabled:opacity-50 disabled:cursor-not-allowed',
            'active:scale-95'
          )}
          aria-label={isPlaying ? 'Pause' : 'Play'}
        >
          {isPlaying ? (
            <HiPause className="w-11 h-11" />
          ) : (
            <HiPlay className="w-11 h-11" />
          )}
        </button>

        {/* Skip forward 10s */}
        <button
          type="button"
          onClick={() => seek(Math.min(duration, currentTime + 10))}
          disabled={!url}
          className={cn(
            'flex-shrink-0 rounded-full',
            'flex items-center justify-center',
            'text-text-primary',
            'hover:bg-black/10',
            'transition-all duration-150',
            'disabled:opacity-50 disabled:cursor-not-allowed',
            'active:scale-95',
            'p-2'
          )}
          aria-label="Skip forward 10 seconds"
        >
          <MdForward10 className="w-9 h-9" />
        </button>
      </div>
    </div>
  );
}
