/**
 * Cues service
 * PostgREST RPC endpoints for cue management
 */

import { apiClient } from './api';
import type {
  Cue,
  GetCuesRequest,
  ShuffleCuesRequest,
  GetCueForProfileRequest,
  CueWithRecordingsResponse,
} from '../types';

// ═══════════════════════════════════════════════════════════════════════════
// GET CUES
// ═══════════════════════════════════════════════════════════════════════════

/**
 * Get cues for a profile (returns recent cues or shuffles if none)
 * POST /rpc/get_cues
 */
export async function getCues(params: GetCuesRequest): Promise<Cue[]> {
  return apiClient.post<Cue[]>('/rpc/get_cues', {
    profileId: params.profileId,
    count: params.count ?? 10,
  });
}

// ═══════════════════════════════════════════════════════════════════════════
// SHUFFLE CUES
// ═══════════════════════════════════════════════════════════════════════════

/**
 * Shuffle and get new cues for a profile
 * POST /rpc/shuffle_cues
 */
export async function shuffleCues(params: ShuffleCuesRequest): Promise<Cue[]> {
  return apiClient.post<Cue[]>('/rpc/shuffle_cues', {
    profileId: params.profileId,
    count: params.count ?? 10,
  });
}

// ═══════════════════════════════════════════════════════════════════════════
// GET CUE FOR PROFILE
// ═══════════════════════════════════════════════════════════════════════════

/**
 * Get a specific cue with recording history for a profile
 * POST /rpc/get_cue_for_profile
 */
export async function getCueForProfile(
  params: GetCueForProfileRequest
): Promise<CueWithRecordingsResponse> {
  return apiClient.post<CueWithRecordingsResponse>('/rpc/get_cue_for_profile', {
    profileId: params.profileId,
    cueId: params.cueId,
  });
}

// ═══════════════════════════════════════════════════════════════════════════
// EXPORT NAMESPACE
// ═══════════════════════════════════════════════════════════════════════════

export const cuesApi = {
  getCues,
  shuffleCues,
  getCueForProfile,
};
