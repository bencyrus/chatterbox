import { HiMicrophone, HiStop } from 'react-icons/hi2';
import { cn } from '../../lib/cn';
import type { RecorderState } from '../../types';

// ═══════════════════════════════════════════════════════════════════════════
// TYPES
// ═══════════════════════════════════════════════════════════════════════════

interface RecordButtonProps {
  /** Current recorder state */
  state: RecorderState;
  /** Click handler */
  onClick: () => void;
  /** Whether button is disabled */
  disabled?: boolean;
  /** Additional class names */
  className?: string;
}

// ═══════════════════════════════════════════════════════════════════════════
// RECORD BUTTON
// ═══════════════════════════════════════════════════════════════════════════

export function RecordButton({
  state,
  onClick,
  disabled = false,
  className,
}: RecordButtonProps) {
  const isRecording = state === 'recording';

  return (
    <button
      type="button"
      onClick={onClick}
      disabled={disabled}
      className={cn(
        'relative w-20 h-20 rounded-full',
        'flex items-center justify-center',
        'transition-all duration-200',
        'focus:outline-none focus-visible:ring-2 focus-visible:ring-offset-2',
        isRecording
          ? 'bg-recording-active focus-visible:ring-recording-active'
          : 'bg-app-green-strong hover:bg-app-green-dark focus-visible:ring-app-green-strong',
        disabled && 'opacity-50 cursor-not-allowed',
        className
      )}
      aria-label={isRecording ? 'Stop recording' : 'Start recording'}
    >
      {/* Outer ring animation when recording */}
      {isRecording && (
        <span
          className={cn(
            'absolute inset-0 rounded-full',
            'border-4 border-recording-active/30',
            'animate-ping'
          )}
        />
      )}

      {/* Icon */}
      {isRecording ? (
        <HiStop className="w-8 h-8 text-white" />
      ) : (
        <HiMicrophone className="w-8 h-8 text-white" />
      )}
    </button>
  );
}
