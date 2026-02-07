import { formatDurationMs } from '../../lib/date';
import { cn } from '../../lib/cn';

// ═══════════════════════════════════════════════════════════════════════════
// TYPES
// ═══════════════════════════════════════════════════════════════════════════

interface RecordingTimerProps {
  /** Duration in milliseconds */
  durationMs: number;
  /** Whether recording is active */
  isRecording?: boolean;
  /** Additional class names */
  className?: string;
}

// ═══════════════════════════════════════════════════════════════════════════
// RECORDING TIMER
// ═══════════════════════════════════════════════════════════════════════════

export function RecordingTimer({
  durationMs,
  isRecording = false,
  className,
}: RecordingTimerProps) {
  return (
    <div
      className={cn(
        'flex items-center justify-center',
        className
      )}
    >
      {/* Timer display - always black */}
      <span className="font-mono text-4xl font-medium text-text-primary">
        {formatDurationMs(durationMs)}
      </span>
    </div>
  );
}
