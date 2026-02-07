import { useState, useRef, useCallback, useEffect } from 'react';
import { AUDIO_MIME_TYPE, AUDIO_MIME_TYPE_FALLBACK } from '../../lib/constants';
import type { RecorderState } from '../../types';

// ═══════════════════════════════════════════════════════════════════════════
// TYPES
// ═══════════════════════════════════════════════════════════════════════════

interface UseRecorderReturn {
  /** Current recorder state */
  state: RecorderState;
  /** Recorded audio blob (after stop) */
  audioBlob: Blob | null;
  /** Recorded audio URL for playback */
  audioUrl: string | null;
  /** Recording duration in milliseconds */
  durationMs: number;
  /** Error message if any */
  error: string | null;
  /** Start recording */
  start: () => Promise<void>;
  /** Pause recording */
  pause: () => void;
  /** Resume recording */
  resume: () => void;
  /** Stop recording */
  stop: () => void;
  /** Reset recorder (clear recording) */
  reset: () => void;
  /** Check if recording is supported */
  isSupported: boolean;
}

// ═══════════════════════════════════════════════════════════════════════════
// HELPERS
// ═══════════════════════════════════════════════════════════════════════════

function getSupportedMimeType(): string {
  if (MediaRecorder.isTypeSupported(AUDIO_MIME_TYPE)) {
    return AUDIO_MIME_TYPE;
  }
  if (MediaRecorder.isTypeSupported(AUDIO_MIME_TYPE_FALLBACK)) {
    return AUDIO_MIME_TYPE_FALLBACK;
  }
  // Fallback to default
  return '';
}

// ═══════════════════════════════════════════════════════════════════════════
// HOOK
// ═══════════════════════════════════════════════════════════════════════════

export function useRecorder(): UseRecorderReturn {
  const [state, setState] = useState<RecorderState>('idle');
  const [audioBlob, setAudioBlob] = useState<Blob | null>(null);
  const [audioUrl, setAudioUrl] = useState<string | null>(null);
  const [durationMs, setDurationMs] = useState(0);
  const [error, setError] = useState<string | null>(null);

  const mediaRecorderRef = useRef<MediaRecorder | null>(null);
  const streamRef = useRef<MediaStream | null>(null);
  const chunksRef = useRef<Blob[]>([]);
  const startTimeRef = useRef<number>(0);
  const pausedTimeRef = useRef<number>(0);
  const timerRef = useRef<ReturnType<typeof setInterval> | null>(null);

  // Check if recording is supported
  const isSupported = typeof MediaRecorder !== 'undefined' && !!navigator.mediaDevices;

  // ─────────────────────────────────────────────────────────────────────────
  // Cleanup
  // ─────────────────────────────────────────────────────────────────────────

  const cleanup = useCallback((skipEvents = false) => {
    // Stop timer
    if (timerRef.current) {
      clearInterval(timerRef.current);
      timerRef.current = null;
    }

    // Stop and cleanup media recorder
    if (mediaRecorderRef.current && mediaRecorderRef.current.state !== 'inactive') {
      // Remove event handlers if skipping events (e.g., during reset)
      if (skipEvents) {
        mediaRecorderRef.current.ondataavailable = null;
        mediaRecorderRef.current.onstop = null;
        mediaRecorderRef.current.onerror = null;
      }
      mediaRecorderRef.current.stop();
    }
    mediaRecorderRef.current = null;

    // Stop all tracks
    if (streamRef.current) {
      streamRef.current.getTracks().forEach((track) => track.stop());
      streamRef.current = null;
    }

    // Clear chunks
    chunksRef.current = [];
  }, []);

  // ─────────────────────────────────────────────────────────────────────────
  // Start recording
  // ─────────────────────────────────────────────────────────────────────────

  const start = useCallback(async () => {
    if (!isSupported) {
      setError('Recording is not supported in this browser');
      return;
    }

    // Reset previous recording
    setAudioBlob(null);
    if (audioUrl) {
      URL.revokeObjectURL(audioUrl);
      setAudioUrl(null);
    }
    setError(null);
    setDurationMs(0);
    chunksRef.current = [];

    try {
      // Request microphone access
      const stream = await navigator.mediaDevices.getUserMedia({
        audio: {
          echoCancellation: true,
          noiseSuppression: true,
          sampleRate: 44100,
        },
      });
      streamRef.current = stream;

      // Create MediaRecorder
      const mimeType = getSupportedMimeType();
      const options: MediaRecorderOptions = mimeType ? { mimeType } : {};
      const mediaRecorder = new MediaRecorder(stream, options);
      mediaRecorderRef.current = mediaRecorder;

      // Handle data available
      mediaRecorder.ondataavailable = (event) => {
        if (event.data.size > 0) {
          chunksRef.current.push(event.data);
        }
      };

      // Handle stop
      mediaRecorder.onstop = () => {
        // Create blob from chunks
        const blob = new Blob(chunksRef.current, {
          type: mimeType || 'audio/webm',
        });
        setAudioBlob(blob);

        // Create URL for playback
        const url = URL.createObjectURL(blob);
        setAudioUrl(url);

        // Cleanup
        if (streamRef.current) {
          streamRef.current.getTracks().forEach((track) => track.stop());
          streamRef.current = null;
        }

        setState('stopped');
      };

      // Handle error
      mediaRecorder.onerror = () => {
        setError('Recording failed. Please try again.');
        cleanup();
        setState('idle');
      };

      // Start recording
      mediaRecorder.start(100); // Collect data every 100ms
      startTimeRef.current = Date.now();
      setState('recording');

      // Start duration timer
      timerRef.current = setInterval(() => {
        setDurationMs(Date.now() - startTimeRef.current);
      }, 100);
    } catch (err) {
      if (err instanceof Error) {
        if (err.name === 'NotAllowedError') {
          setError('Microphone access denied. Please allow microphone access to record.');
        } else if (err.name === 'NotFoundError') {
          setError('No microphone found. Please connect a microphone.');
        } else {
          setError(`Failed to start recording: ${err.message}`);
        }
      } else {
        setError('Failed to start recording. Please try again.');
      }
      cleanup();
      setState('idle');
    }
  }, [isSupported, audioUrl, cleanup]);

  // ─────────────────────────────────────────────────────────────────────────
  // Pause recording
  // ─────────────────────────────────────────────────────────────────────────

  const pause = useCallback(() => {
    if (timerRef.current) {
      clearInterval(timerRef.current);
      timerRef.current = null;
    }

    if (mediaRecorderRef.current && mediaRecorderRef.current.state === 'recording') {
      pausedTimeRef.current = Date.now() - startTimeRef.current;
      setDurationMs(pausedTimeRef.current);
      mediaRecorderRef.current.pause();
      setState('paused');
    }
  }, []);

  // ─────────────────────────────────────────────────────────────────────────
  // Resume recording
  // ─────────────────────────────────────────────────────────────────────────

  const resume = useCallback(() => {
    if (mediaRecorderRef.current && mediaRecorderRef.current.state === 'paused') {
      mediaRecorderRef.current.resume();
      startTimeRef.current = Date.now() - pausedTimeRef.current;
      setState('recording');

      // Restart timer
      timerRef.current = setInterval(() => {
        setDurationMs(Date.now() - startTimeRef.current);
      }, 100);
    }
  }, []);

  // ─────────────────────────────────────────────────────────────────────────
  // Stop recording
  // ─────────────────────────────────────────────────────────────────────────

  const stop = useCallback(() => {
    if (timerRef.current) {
      clearInterval(timerRef.current);
      timerRef.current = null;
    }

    const currentState = mediaRecorderRef.current?.state;
    if (mediaRecorderRef.current && (currentState === 'recording' || currentState === 'paused')) {
      // Calculate final duration
      if (currentState === 'recording') {
        setDurationMs(Date.now() - startTimeRef.current);
      }
      mediaRecorderRef.current.stop();
    }
  }, []);

  // ─────────────────────────────────────────────────────────────────────────
  // Reset
  // ─────────────────────────────────────────────────────────────────────────

  const reset = useCallback(() => {
    cleanup(true); // Skip events to prevent onstop from firing

    if (audioUrl) {
      URL.revokeObjectURL(audioUrl);
    }

    setAudioBlob(null);
    setAudioUrl(null);
    setDurationMs(0);
    pausedTimeRef.current = 0;
    setError(null);
    setState('idle');
  }, [cleanup, audioUrl]);

  // ─────────────────────────────────────────────────────────────────────────
  // Cleanup on unmount
  // ─────────────────────────────────────────────────────────────────────────

  useEffect(() => {
    return () => {
      cleanup();
      if (audioUrl) {
        URL.revokeObjectURL(audioUrl);
      }
    };
  }, [cleanup, audioUrl]);

  // ─────────────────────────────────────────────────────────────────────────
  // Return
  // ─────────────────────────────────────────────────────────────────────────

  return {
    state,
    audioBlob,
    audioUrl,
    durationMs,
    error,
    start,
    pause,
    resume,
    stop,
    reset,
    isSupported,
  };
}
