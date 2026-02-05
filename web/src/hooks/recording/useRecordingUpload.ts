import { useState, useCallback } from 'react';
import { recordingsApi } from '../../services/recordings';
import { uploadToSignedUrl } from '../../services/api';
import { useProfile } from '../../contexts/ProfileContext';
import { useToast } from '../../contexts/ToastContext';
import { ApiError } from '../../services/api';
import type { Recording } from '../../types';
import { AUDIO_UPLOAD_MIME_TYPE } from '../../lib/constants';
import { formatDurationMs } from '../../lib/date';

// ═══════════════════════════════════════════════════════════════════════════
// TYPES
// ═══════════════════════════════════════════════════════════════════════════

interface UseRecordingUploadParams {
  cueId: number;
}

interface UseRecordingUploadReturn {
  /** Upload the recording */
  upload: (blob: Blob, durationMs: number) => Promise<Recording | null>;
  /** Whether upload is in progress */
  isUploading: boolean;
  /** Upload progress (0-100) */
  progress: number;
  /** Error message if upload failed */
  error: string | null;
}

// ═══════════════════════════════════════════════════════════════════════════
// HOOK
// ═══════════════════════════════════════════════════════════════════════════

export function useRecordingUpload({
  cueId,
}: UseRecordingUploadParams): UseRecordingUploadReturn {
  const [isUploading, setIsUploading] = useState(false);
  const [progress, setProgress] = useState(0);
  const [error, setError] = useState<string | null>(null);
  
  const { activeProfile } = useProfile();
  const { showToast } = useToast();

  // ─────────────────────────────────────────────────────────────────────────
  // Upload recording
  // ─────────────────────────────────────────────────────────────────────────

  const upload = useCallback(
    async (blob: Blob, durationMs: number): Promise<Recording | null> => {
      if (!activeProfile) {
        showToast('No active profile', 'error');
        return null;
      }

      setIsUploading(true);
      setProgress(0);
      setError(null);

      try {
        // Step 1: Create upload intent
        setProgress(10);
        const intent = await recordingsApi.createUploadIntent({
          profileId: activeProfile.profileId,
          cueId,
          mimeType: AUDIO_UPLOAD_MIME_TYPE,
        });

        // Step 2: Upload to signed URL
        setProgress(30);
        await uploadToSignedUrl(intent.uploadUrl, blob, AUDIO_UPLOAD_MIME_TYPE);

        // Step 3: Complete upload with metadata
        setProgress(80);
        const response = await recordingsApi.completeUpload({
          uploadIntentId: intent.uploadIntentId,
          metadata: {
            duration: formatDurationMs(durationMs),
          },
        });

        setProgress(100);
        showToast('Recording saved!', 'success');
        
        // Return a Recording object constructed from the response
        // The complete_recording_upload returns file info, not full recording
        // Return a partial recording that the caller can use
        return {
          profileCueRecordingId: 0, // Will be refreshed on next load
          profileId: activeProfile.profileId,
          cueId,
          fileId: response.file.fileId,
          createdAt: new Date().toISOString(),
          file: response.file,
          cue: null as any, // Not returned from complete, caller should refresh
          report: { status: 'none', transcript: null },
        };
      } catch (err) {
        const message =
          err instanceof ApiError
            ? err.message
            : 'Failed to upload recording. Please try again.';
        setError(message);
        showToast(message, 'error');
        return null;
      } finally {
        setIsUploading(false);
      }
    },
    [activeProfile, cueId, showToast]
  );

  // ─────────────────────────────────────────────────────────────────────────
  // Return
  // ─────────────────────────────────────────────────────────────────────────

  return {
    upload,
    isUploading,
    progress,
    error,
  };
}
