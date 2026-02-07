import { useCallback, useEffect, useState } from 'react';
import { HiOutlineTrash, HiArchiveBox } from 'react-icons/hi2';
import { RecordButton } from './RecordButton';
import { RecordingTimer } from './RecordingTimer';
import { Progress } from '../ui/Progress';
import { Modal } from '../ui/Modal';
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
  const [showDeleteConfirm, setShowDeleteConfirm] = useState(false);
  const [shouldSaveAfterStop, setShouldSaveAfterStop] = useState(false);

  const {
    state,
    audioBlob,
    durationMs,
    error: recorderError,
    start,
    pause,
    resume,
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
      pause();
    } else if (state === 'paused') {
      resume();
    } else {
      start();
    }
  }, [state, start, pause, resume]);

  // ─────────────────────────────────────────────────────────────────────────
  // Handle save
  // ─────────────────────────────────────────────────────────────────────────

  const handleSave = useCallback(async () => {
    // If paused, stop the recording first to generate the blob
    if (state === 'paused') {
      setShouldSaveAfterStop(true);
      stop();
      return; // The upload will happen after the blob is created
    }

    if (!audioBlob) return;

    const recording = await upload(audioBlob, durationMs);
    if (recording) {
      onRecordingSaved?.(recording);
      reset();
      setShouldSaveAfterStop(false);
    }
  }, [state, audioBlob, durationMs, stop, upload, onRecordingSaved, reset, setShouldSaveAfterStop]);

  // ─────────────────────────────────────────────────────────────────────────
  // Auto-upload when recording stops after user clicked Save
  // ─────────────────────────────────────────────────────────────────────────

  useEffect(() => {
    if (shouldSaveAfterStop && state === 'stopped' && audioBlob && !isUploading) {
      handleSave();
    }
  }, [shouldSaveAfterStop, state, audioBlob, isUploading, handleSave]);

  // ─────────────────────────────────────────────────────────────────────────
  // Handle discard
  // ─────────────────────────────────────────────────────────────────────────

  const handleDiscardClick = useCallback(() => {
    setShowDeleteConfirm(true);
  }, []);

  const handleConfirmDiscard = useCallback(() => {
    reset();
    setShowDeleteConfirm(false);
  }, [reset]);

  const handleCancelDiscard = useCallback(() => {
    setShowDeleteConfirm(false);
  }, []);

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
        <Progress value={uploadProgress} className="w-48" />
      </div>
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Review state (paused or stopped with recording)
  // ─────────────────────────────────────────────────────────────────────────

  if (state === 'paused' || (state === 'stopped' && audioBlob)) {
    return (
      <div
        className={cn(
          'flex flex-col items-center gap-6',
          'py-6 px-4',
          className
        )}
      >
        {/* Timer */}
        <RecordingTimer durationMs={durationMs} />

        {/* Action buttons */}
        <div className="flex items-center justify-center gap-4">
          {/* Delete */}
          <button
            type="button"
            onClick={handleDiscardClick}
            className="w-[100px] h-[70px] flex flex-col items-center justify-center gap-1.5 rounded-3xl border-2 border-error-600 transition-colors hover:bg-error-600/10"
          >
            <HiOutlineTrash className="w-6 h-6 text-error-600" />
            <span className="text-label-sm text-error-600">Delete</span>
          </button>

          {/* Resume */}
          <button
            type="button"
            onClick={resume}
            className="w-[162px] h-[70px] flex items-center justify-center rounded-full border-2 border-recording-active bg-recording-active/10 transition-colors hover:bg-recording-active/20"
          >
            <span className="text-heading-sm font-semibold text-recording-active uppercase tracking-wide">
              Resume
            </span>
          </button>

          {/* Save */}
          <button
            type="button"
            onClick={handleSave}
            className="w-[100px] h-[70px] flex flex-col items-center justify-center gap-1.5 rounded-3xl border-2 border-success-600 transition-colors hover:bg-app-green/20"
          >
            <HiArchiveBox className="w-6 h-6 text-success-600" />
            <span className="text-label-sm text-success-600">Save</span>
          </button>
        </div>

        {/* Delete confirmation modal */}
        <Modal
          isOpen={showDeleteConfirm}
          onClose={handleCancelDiscard}
          title="Delete Recording?"
          showCloseButton={false}
        >
          <p className="text-body-md text-text-secondary mb-6">
            Are you sure you want to delete this recording? This action cannot be undone.
          </p>
          <div className="flex items-center justify-end gap-3">
            <button
              type="button"
              onClick={handleCancelDiscard}
              className="px-4 py-2 text-body-md text-text-primary bg-app-beige rounded-button hover:bg-app-beige-hover transition-colors"
            >
              Cancel
            </button>
            <button
              type="button"
              onClick={handleConfirmDiscard}
              className="px-4 py-2 text-body-md text-white bg-error-600 rounded-button hover:bg-error-700 transition-colors"
            >
              Delete
            </button>
          </div>
        </Modal>
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
      <p className="text-caption text-text-secondary text-center">
        {state === 'recording' ? 'Tap to stop' : 'Tap to record'}
      </p>
    </div>
  );
}
