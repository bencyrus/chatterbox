/**
 * Recordings service
 * PostgREST RPC endpoints for recording management
 */

import { apiClient } from './api';
import type {
  RecordingHistoryResponse,
  CreateUploadIntentRequest,
  CreateUploadIntentResponse,
  CompleteUploadRequest,
  CompleteUploadResponse,
  RequestTranscriptionRequest,
  TranscriptionRequestResponse,
} from '../types';

// ═══════════════════════════════════════════════════════════════════════════
// RECORDING HISTORY
// ═══════════════════════════════════════════════════════════════════════════

/**
 * Get recording history for a profile
 * POST /rpc/get_profile_recording_history
 */
export async function getProfileRecordingHistory(
  profileId: number
): Promise<RecordingHistoryResponse> {
  return apiClient.post<RecordingHistoryResponse>(
    '/rpc/get_profile_recording_history',
    { profileId }
  );
}

// ═══════════════════════════════════════════════════════════════════════════
// UPLOAD
// ═══════════════════════════════════════════════════════════════════════════

/**
 * Create an upload intent for a new recording
 * POST /rpc/create_recording_upload_intent
 */
export async function createUploadIntent(
  params: CreateUploadIntentRequest
): Promise<CreateUploadIntentResponse> {
  return apiClient.post<CreateUploadIntentResponse>(
    '/rpc/create_recording_upload_intent',
    {
      profileId: params.profileId,
      cueId: params.cueId,
      mimeType: params.mimeType,
    }
  );
}

/**
 * Complete the upload after file is uploaded to signed URL
 * POST /rpc/complete_recording_upload
 */
export async function completeUpload(
  params: CompleteUploadRequest
): Promise<CompleteUploadResponse> {
  return apiClient.post<CompleteUploadResponse>(
    '/rpc/complete_recording_upload',
    {
      uploadIntentId: params.uploadIntentId,
      metadata: params.metadata ?? null,
    }
  );
}

// ═══════════════════════════════════════════════════════════════════════════
// TRANSCRIPTION
// ═══════════════════════════════════════════════════════════════════════════

/**
 * Request transcription for a recording
 * POST /rpc/request_recording_transcription
 */
export async function requestTranscription(
  params: RequestTranscriptionRequest
): Promise<TranscriptionRequestResponse> {
  return apiClient.post<TranscriptionRequestResponse>(
    '/rpc/request_recording_transcription',
    { profileCueRecordingId: params.profileCueRecordingId }
  );
}

// ═══════════════════════════════════════════════════════════════════════════
// EXPORT NAMESPACE
// ═══════════════════════════════════════════════════════════════════════════

export const recordingsApi = {
  getProfileRecordingHistory,
  createUploadIntent,
  completeUpload,
  requestTranscription,
};
