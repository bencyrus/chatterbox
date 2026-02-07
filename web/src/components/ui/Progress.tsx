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
          'h-full bg-success-600 rounded-full transition-all duration-200',
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
  
  const handleSeekToPosition = (clientX: number, element: HTMLElement) => {
    const rect = element.getBoundingClientRect();
    const x = clientX - rect.left;
    const newPercentage = Math.max(0, Math.min(1, x / rect.width));
    const newTime = newPercentage * duration;
    onSeek(newTime);
  };

  const handleMouseDown = (e: React.MouseEvent<HTMLDivElement>) => {
    e.preventDefault();
    const element = e.currentTarget;
    handleSeekToPosition(e.clientX, element);
    
    const handleMouseMove = (moveEvent: MouseEvent) => {
      handleSeekToPosition(moveEvent.clientX, element);
    };
    
    const handleMouseUp = () => {
      document.removeEventListener('mousemove', handleMouseMove);
      document.removeEventListener('mouseup', handleMouseUp);
    };
    
    document.addEventListener('mousemove', handleMouseMove);
    document.addEventListener('mouseup', handleMouseUp);
  };

  const handleTouchStart = (e: React.TouchEvent<HTMLDivElement>) => {
    const element = e.currentTarget;
    const touch = e.touches[0];
    handleSeekToPosition(touch.clientX, element);
  };

  const handleTouchMove = (e: React.TouchEvent<HTMLDivElement>) => {
    const element = e.currentTarget;
    const touch = e.touches[0];
    handleSeekToPosition(touch.clientX, element);
  };
  
  return (
    <div
      role="slider"
      aria-valuenow={currentTime}
      aria-valuemin={0}
      aria-valuemax={duration}
      aria-label="Audio progress"
      tabIndex={0}
      onMouseDown={handleMouseDown}
      onTouchStart={handleTouchStart}
      onTouchMove={handleTouchMove}
      onKeyDown={(e) => {
        if (e.key === 'ArrowRight') {
          onSeek(Math.min(duration, currentTime + 5));
        } else if (e.key === 'ArrowLeft') {
          onSeek(Math.max(0, currentTime - 5));
        }
      }}
      className={cn(
        'relative w-full cursor-pointer group select-none',
        'py-2', // Add padding for easier clicking on thumb
        className
      )}
    >
      {/* Progress track */}
      <div className="relative h-1 bg-surface-tertiary rounded-full">
        <div
          className="absolute h-full bg-text-primary rounded-full"
          style={{ width: `${percentage}%` }}
        />
      </div>
      
      {/* Thumb circle */}
      <div
        className="absolute top-1/2 -translate-y-1/2 w-4 h-4 bg-text-primary rounded-full shadow-sm"
        style={{ left: `calc(${percentage}% - 8px)` }}
      />
    </div>
  );
}
