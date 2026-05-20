import { useState, useEffect, useCallback, useRef } from 'react';
import { recordingsApi } from '../../services/recordings';
import { ApiError } from '../../services/api';
import type { Recording, EvaluationStatus, EvaluationResult } from '../../types';
import { EVALUATION_POLL_INTERVAL_MS } from '../../lib/constants';

// ═══════════════════════════════════════════════════════════════════════════
// TYPES
// ═══════════════════════════════════════════════════════════════════════════

interface UseEvaluationParams {
  recording: Recording | null;
  /** Callback to refresh the recording data (after evaluation completes) */
  onRefresh?: () => Promise<void>;
  /** When true, automatically request evaluation once transcript is ready */
  autoRequest?: boolean;
}

interface UseEvaluationReturn {
  evaluation: EvaluationResult | null;
  status: EvaluationStatus | null;
  isRequesting: boolean;
  error: string | null;
  requestEvaluation: () => Promise<void>;
}

// ═══════════════════════════════════════════════════════════════════════════
// HOOK
// ═══════════════════════════════════════════════════════════════════════════

export function useEvaluation({
  recording,
  onRefresh,
  autoRequest = false,
}: UseEvaluationParams): UseEvaluationReturn {
  const [evaluation, setEvaluation] = useState<EvaluationResult | null>(null);
  const [status, setStatus] = useState<EvaluationStatus | null>(null);
  const [isRequesting, setIsRequesting] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const pollIntervalRef = useRef<ReturnType<typeof setInterval> | null>(null);
  const autoRequestedRef = useRef<number | null>(null);

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
  // Poll for evaluation completion by refreshing recording data
  // ─────────────────────────────────────────────────────────────────────────

  const pollForCompletion = useCallback(async () => {
    if (!onRefresh) {
      stopPolling();
      return;
    }

    try {
      await onRefresh();
    } catch (err) {
      console.error('Failed to poll for evaluation:', err);
    }
  }, [onRefresh, stopPolling]);

  // ─────────────────────────────────────────────────────────────────────────
  // Start polling
  // ─────────────────────────────────────────────────────────────────────────

  const startPolling = useCallback(() => {
    stopPolling();

    pollIntervalRef.current = setInterval(() => {
      pollForCompletion();
    }, EVALUATION_POLL_INTERVAL_MS);
  }, [pollForCompletion, stopPolling]);

  // ─────────────────────────────────────────────────────────────────────────
  // Request evaluation
  // ─────────────────────────────────────────────────────────────────────────

  const requestEvaluation = useCallback(async () => {
    if (!recording) return;

    setIsRequesting(true);
    setError(null);

    try {
      const response = await recordingsApi.requestEvaluation({
        profileCueRecordingId: recording.profileCueRecordingId,
      });

      if (response.status === 'started' || response.status === 'in_progress') {
        setStatus('processing');
        startPolling();
      } else if (response.status === 'already_evaluated') {
        onRefresh?.();
      }
    } catch (err) {
      const message =
        err instanceof ApiError
          ? err.message
          : 'Failed to request evaluation.';
      setError(message);
    } finally {
      setIsRequesting(false);
    }
  }, [recording, startPolling, onRefresh]);

  // ─────────────────────────────────────────────────────────────────────────
  // Initialize from recording and auto-request when transcript becomes ready
  // ─────────────────────────────────────────────────────────────────────────

  useEffect(() => {
    if (!recording) {
      setEvaluation(null);
      setStatus(null);
      stopPolling();
      return;
    }

    const report = recording.report;
    const evalData = report?.evaluation;

    if (!evalData) {
      setStatus('none');
      setEvaluation(null);
      stopPolling();

      if (
        autoRequest &&
        report?.status === 'ready' &&
        report?.transcript &&
        autoRequestedRef.current !== recording.profileCueRecordingId
      ) {
        autoRequestedRef.current = recording.profileCueRecordingId;
        requestEvaluation();
      }
      return;
    }

    setStatus(evalData.status);

    if (evalData.status === 'processing') {
      setEvaluation(null);
      startPolling();
      return;
    }

    stopPolling();

    if (evalData.status === 'ready' && evalData.result) {
      setEvaluation(evalData.result);
    } else {
      setEvaluation(null);

      if (
        autoRequest &&
        evalData.status === 'none' &&
        report?.status === 'ready' &&
        report?.transcript &&
        autoRequestedRef.current !== recording.profileCueRecordingId
      ) {
        autoRequestedRef.current = recording.profileCueRecordingId;
        requestEvaluation();
      }
    }
  }, [
    recording?.profileCueRecordingId,
    recording?.report?.evaluation?.status,
    recording?.report?.status,
    autoRequest,
    startPolling,
    stopPolling,
    requestEvaluation,
  ]);

  // ─────────────────────────────────────────────────────────────────────────
  // Cleanup on unmount
  // ─────────────────────────────────────────────────────────────────────────

  useEffect(() => {
    return () => {
      stopPolling();
    };
  }, [stopPolling]);

  return {
    evaluation,
    status,
    isRequesting,
    error,
    requestEvaluation,
  };
}
