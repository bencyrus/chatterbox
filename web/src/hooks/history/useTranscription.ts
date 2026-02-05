import { useState, useEffect, useCallback, useRef } from 'react';
import { recordingsApi } from '../../services/recordings';
import { useToast } from '../../contexts/ToastContext';
import { ApiError } from '../../services/api';
import type { Recording, ReportStatus } from '../../types';
import { TRANSCRIPTION_POLL_INTERVAL_MS } from '../../lib/constants';

// ═══════════════════════════════════════════════════════════════════════════
// TYPES
// ═══════════════════════════════════════════════════════════════════════════

interface UseTranscriptionParams {
  recording: Recording | null;
  /** Callback to refresh the recording data (after transcription completes) */
  onRefresh?: () => Promise<void>;
}

interface UseTranscriptionReturn {
  /** Transcription text */
  transcription: string | null;
  /** Transcription status */
  status: ReportStatus | null;
  /** Whether transcription is loading */
  isLoading: boolean;
  /** Whether transcription request is pending */
  isRequesting: boolean;
  /** Error message if any */
  error: string | null;
  /** Request a new transcription */
  requestTranscription: () => Promise<void>;
}

// ═══════════════════════════════════════════════════════════════════════════
// HOOK
// ═══════════════════════════════════════════════════════════════════════════

export function useTranscription({
  recording,
  onRefresh,
}: UseTranscriptionParams): UseTranscriptionReturn {
  const [transcription, setTranscription] = useState<string | null>(null);
  const [status, setStatus] = useState<ReportStatus | null>(null);
  const [isLoading, setIsLoading] = useState(false);
  const [isRequesting, setIsRequesting] = useState(false);
  const [error, setError] = useState<string | null>(null);
  
  const { showToast } = useToast();
  const pollIntervalRef = useRef<ReturnType<typeof setInterval> | null>(null);

  // ─────────────────────────────────────────────────────────────────────────
  // Stop polling
  // ─────────────────────────────────────────────────────────────────────────

  const stopPolling = useCallback(() => {
    if (pollIntervalRef.current) {
      clearInterval(pollIntervalRef.current);
      pollIntervalRef.current = null;
    }
  }, []);

  // ─────────────────────────────────────────────────────────────────────────
  // Poll for transcription completion by refreshing recording data
  // ─────────────────────────────────────────────────────────────────────────

  const pollForCompletion = useCallback(async () => {
    if (!onRefresh) {
      stopPolling();
      return;
    }
    
    try {
      await onRefresh();
    } catch (err) {
      console.error('Failed to poll for transcription:', err);
    }
  }, [onRefresh, stopPolling]);

  // ─────────────────────────────────────────────────────────────────────────
  // Start polling
  // ─────────────────────────────────────────────────────────────────────────

  const startPolling = useCallback(() => {
    stopPolling();
    
    pollIntervalRef.current = setInterval(() => {
      pollForCompletion();
    }, TRANSCRIPTION_POLL_INTERVAL_MS);
  }, [pollForCompletion, stopPolling]);

  // ─────────────────────────────────────────────────────────────────────────
  // Request transcription
  // ─────────────────────────────────────────────────────────────────────────

  const requestTranscription = useCallback(async () => {
    if (!recording) return;

    setIsRequesting(true);
    setError(null);

    try {
      const response = await recordingsApi.requestTranscription({
        profileCueRecordingId: recording.profileCueRecordingId,
      });
      
      if (response.status === 'started' || response.status === 'in_progress') {
        setStatus('processing');
        showToast('Transcription started. This may take a moment.', 'info');
        startPolling();
      } else if (response.status === 'already_transcribed') {
        // Refresh to get the existing transcription
        onRefresh?.();
        showToast('Recording already has a transcription', 'info');
      }
    } catch (err) {
      const message =
        err instanceof ApiError
          ? err.message
          : 'Failed to request transcription.';
      setError(message);
      showToast(message, 'error');
    } finally {
      setIsRequesting(false);
    }
  }, [recording, showToast, startPolling, onRefresh]);

  // ─────────────────────────────────────────────────────────────────────────
  // Initialize from recording
  // ─────────────────────────────────────────────────────────────────────────

  useEffect(() => {
    if (!recording) {
      setTranscription(null);
      setStatus(null);
      return;
    }

    // Check if recording already has transcription data
    const report = recording.report;
    if (report) {
      setStatus(report.status);
      
      if (report.status === 'ready' && report.transcript) {
        setTranscription(report.transcript);
        stopPolling();
      } else if (report.status === 'processing') {
        // Start polling for processing transcriptions
        startPolling();
      } else {
        setTranscription(null);
      }
    } else {
      setStatus('none');
      setTranscription(null);
    }
  }, [recording?.profileCueRecordingId, recording?.report?.status, recording?.report?.transcript, startPolling, stopPolling]);

  // ─────────────────────────────────────────────────────────────────────────
  // Cleanup on unmount
  // ─────────────────────────────────────────────────────────────────────────

  useEffect(() => {
    return () => {
      stopPolling();
    };
  }, [stopPolling]);

  // ─────────────────────────────────────────────────────────────────────────
  // Return
  // ─────────────────────────────────────────────────────────────────────────

  return {
    transcription,
    status,
    isLoading,
    isRequesting,
    error,
    requestTranscription,
  };
}
