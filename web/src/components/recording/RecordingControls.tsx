import { useCallback, useEffect } from 'react';
import { HiOutlineTrash, HiOutlineArrowUpTray } from 'react-icons/hi2';
import { RecordButton } from './RecordButton';
import { RecordingTimer } from './RecordingTimer';
import { AudioPlayer } from './AudioPlayer';
import { Button } from '../ui/Button';
import { Progress } from '../ui/Progress';
import { cn } from '../../lib/cn';
import { useRecorder } from '../../hooks/recording/useRecorder';
import { useRecordingUpload } from '../../hooks/recording/useRecordingUpload';
import { useToast } from '../../contexts/ToastContext';
import type { Recording } from '../../types';

// ═══════════════════════════════════════════════════════════════════════════
// TYPES
// ═══════════════════════════════════════════════════════════════════════════

interface RecordingControlsProps {
  /** Cue ID to associate recording with */
  cueId: number;
  /** Callback when recording is saved */
  onRecordingSaved?: (recording: Recording) => void;
  /** Additional class names */
  className?: string;
}

// ═══════════════════════════════════════════════════════════════════════════
// RECORDING CONTROLS
// ═══════════════════════════════════════════════════════════════════════════

export function RecordingControls({
  cueId,
  onRecordingSaved,
  className,
}: RecordingControlsProps) {
  const {
    state,
    audioBlob,
    audioUrl,
    durationMs,
    error: recorderError,
    start,
    stop,
    reset,
    isSupported,
  } = useRecorder();

  const {
    upload,
    isUploading,
    progress: uploadProgress,
  } = useRecordingUpload({ cueId });

  const { showToast } = useToast();

  // ─────────────────────────────────────────────────────────────────────────
  // Show recorder error
  // ─────────────────────────────────────────────────────────────────────────

  useEffect(() => {
    if (recorderError) {
      showToast(recorderError, 'error');
    }
  }, [recorderError, showToast]);

  // ─────────────────────────────────────────────────────────────────────────
  // Handle record button
  // ─────────────────────────────────────────────────────────────────────────

  const handleRecordPress = useCallback(() => {
    if (state === 'recording') {
      stop();
    } else {
      start();
    }
  }, [state, start, stop]);

  // ─────────────────────────────────────────────────────────────────────────
  // Handle save
  // ─────────────────────────────────────────────────────────────────────────

  const handleSave = useCallback(async () => {
    if (!audioBlob) return;

    const recording = await upload(audioBlob, durationMs);
    if (recording) {
      onRecordingSaved?.(recording);
      reset();
    }
  }, [audioBlob, durationMs, upload, onRecordingSaved, reset]);

  // ─────────────────────────────────────────────────────────────────────────
  // Handle discard
  // ─────────────────────────────────────────────────────────────────────────

  const handleDiscard = useCallback(() => {
    reset();
  }, [reset]);

  // ─────────────────────────────────────────────────────────────────────────
  // Unsupported browser
  // ─────────────────────────────────────────────────────────────────────────

  if (!isSupported) {
    return (
      <div
        className={cn(
          'flex flex-col items-center justify-center',
          'py-8 px-4 text-center',
          className
        )}
      >
        <p className="text-body-md text-text-secondary">
          Recording is not supported in this browser.
          Please use a modern browser like Chrome, Firefox, or Safari.
        </p>
      </div>
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Uploading state
  // ─────────────────────────────────────────────────────────────────────────

  if (isUploading) {
    return (
      <div
        className={cn(
          'flex flex-col items-center justify-center gap-4',
          'py-8 px-4',
          className
        )}
      >
        <p className="text-body-md text-text-secondary">Saving recording...</p>
        <Progress progress={uploadProgress / 100} className="w-48" />
      </div>
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Review state (has recording)
  // ─────────────────────────────────────────────────────────────────────────

  if (state === 'stopped' && audioBlob) {
    return (
      <div
        className={cn(
          'flex flex-col items-center gap-6',
          'py-6 px-4',
          className
        )}
      >
        {/* Audio player for review */}
        <AudioPlayer
          id={`review-${cueId}`}
          url={audioUrl}
          durationMs={durationMs}
          className="w-full max-w-sm"
        />

        {/* Action buttons */}
        <div className="flex items-center gap-4">
          <Button
            variant="secondary"
            onClick={handleDiscard}
            iconLeft={<HiOutlineTrash className="w-5 h-5" />}
          >
            Discard
          </Button>
          <Button
            variant="primary"
            onClick={handleSave}
            iconLeft={<HiOutlineArrowUpTray className="w-5 h-5" />}
          >
            Save
          </Button>
        </div>
      </div>
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Recording/idle state
  // ─────────────────────────────────────────────────────────────────────────

  return (
    <div
      className={cn(
        'flex flex-col items-center gap-6',
        'py-6 px-4',
        className
      )}
    >
      {/* Timer */}
      <RecordingTimer
        durationMs={durationMs}
        isRecording={state === 'recording'}
      />

      {/* Record button */}
      <RecordButton state={state} onClick={handleRecordPress} />

      {/* Instructions */}
      <p className="text-body-sm text-text-tertiary text-center">
        {state === 'recording'
          ? 'Tap to stop recording'
          : 'Tap to start recording'}
      </p>
    </div>
  );
}
