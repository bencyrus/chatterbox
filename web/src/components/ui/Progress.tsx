import { cn } from '../../lib/cn';

// ═══════════════════════════════════════════════════════════════════════════
// TYPES
// ═══════════════════════════════════════════════════════════════════════════

interface ProgressProps {
  value: number;
  max?: number;
  className?: string;
  barClassName?: string;
}

// ═══════════════════════════════════════════════════════════════════════════
// COMPONENT
// ═══════════════════════════════════════════════════════════════════════════

export function Progress({
  value,
  max = 100,
  className,
  barClassName,
}: ProgressProps) {
  const percentage = Math.min(100, Math.max(0, (value / max) * 100));
  
  return (
    <div
      role="progressbar"
      aria-valuenow={value}
      aria-valuemin={0}
      aria-valuemax={max}
      className={cn(
        'w-full h-2 bg-surface-tertiary rounded-full overflow-hidden',
        className
      )}
    >
      <div
        className={cn(
          'h-full bg-brand-500 rounded-full transition-all duration-200',
          barClassName
        )}
        style={{ width: `${percentage}%` }}
      />
    </div>
  );
}

// ═══════════════════════════════════════════════════════════════════════════
// AUDIO PROGRESS (seekable)
// ═══════════════════════════════════════════════════════════════════════════

interface AudioProgressProps {
  currentTime: number;
  duration: number;
  onSeek: (time: number) => void;
  className?: string;
}

export function AudioProgress({
  currentTime,
  duration,
  onSeek,
  className,
}: AudioProgressProps) {
  const percentage = duration > 0 ? (currentTime / duration) * 100 : 0;
  
  const handleClick = (e: React.MouseEvent<HTMLDivElement>) => {
    const rect = e.currentTarget.getBoundingClientRect();
    const x = e.clientX - rect.left;
    const percentage = x / rect.width;
    const newTime = percentage * duration;
    onSeek(Math.max(0, Math.min(duration, newTime)));
  };
  
  return (
    <div
      role="slider"
      aria-valuenow={currentTime}
      aria-valuemin={0}
      aria-valuemax={duration}
      aria-label="Audio progress"
      tabIndex={0}
      onClick={handleClick}
      onKeyDown={(e) => {
        if (e.key === 'ArrowRight') {
          onSeek(Math.min(duration, currentTime + 5));
        } else if (e.key === 'ArrowLeft') {
          onSeek(Math.max(0, currentTime - 5));
        }
      }}
      className={cn(
        'w-full h-2 bg-surface-tertiary rounded-full overflow-hidden cursor-pointer group',
        className
      )}
    >
      <div
        className="h-full bg-brand-500 rounded-full transition-all duration-100 group-hover:bg-brand-600"
        style={{ width: `${percentage}%` }}
      />
    </div>
  );
}
