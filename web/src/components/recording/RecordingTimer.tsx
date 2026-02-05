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
        'flex items-center justify-center gap-2',
        className
      )}
    >
      {/* Pulsing indicator when recording */}
      {isRecording && (
        <span className="w-3 h-3 rounded-full bg-recording-active animate-pulse-recording" />
      )}
      
      {/* Timer display */}
      <span
        className={cn(
          'font-mono text-heading-md font-semibold',
          isRecording ? 'text-recording-active' : 'text-text-primary'
        )}
      >
        {formatDurationMs(durationMs)}
      </span>
    </div>
  );
}
