import { HiMicrophone } from 'react-icons/hi2';
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

  if (isRecording) {
    // Recording state: transparent pill with grey border and red pause icon
    return (
      <button
        type="button"
        onClick={onClick}
        disabled={disabled}
        className={cn(
          'w-[162px] h-[70px] rounded-full',
          'border-2 border-gray-300',
          'flex items-center justify-center gap-1.5',
          'transition-all duration-200',
          'focus:outline-none focus-visible:ring-2 focus-visible:ring-recording-active focus-visible:ring-offset-2',
          disabled && 'opacity-50 cursor-not-allowed',
          className
        )}
        aria-label="Pause recording"
      >
        {/* Pause icon (two vertical bars) */}
        <div className="w-2 h-7 bg-recording-active rounded-full" />
        <div className="w-2 h-7 bg-recording-active rounded-full" />
      </button>
    );
  }

  // Idle state: grey ring with red circle + mic icon
  return (
    <button
      type="button"
      onClick={onClick}
      disabled={disabled}
      className={cn(
        'relative',
        'focus:outline-none focus-visible:ring-2 focus-visible:ring-recording-active focus-visible:ring-offset-2',
        disabled && 'opacity-50 cursor-not-allowed',
        className
      )}
      aria-label="Start recording"
    >
      {/* Outer grey ring (110x110) */}
      <div className="relative w-[110px] h-[110px] rounded-full border-2 border-gray-300 flex items-center justify-center">
        {/* Inner red circle (100x100) */}
        <div className="w-[100px] h-[100px] rounded-full flex items-center justify-center bg-recording-active">
          {/* Mic icon */}
          <HiMicrophone className="w-10 h-10 text-white" />
        </div>
      </div>
    </button>
  );
}
