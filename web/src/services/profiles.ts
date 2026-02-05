/**
 * Profiles service
 * PostgREST RPC endpoints for profile management
 */

import { apiClient } from './api';
import type {
  SetActiveProfileRequest,
  GetOrCreateProfileRequest,
  GetOrCreateProfileResponse,
} from '../types';

// ═══════════════════════════════════════════════════════════════════════════
// SET ACTIVE PROFILE
// ═══════════════════════════════════════════════════════════════════════════

/**
 * Set the active profile for an account (creates if needed)
 * POST /rpc/set_active_profile
 */
export async function setActiveProfile(
  params: SetActiveProfileRequest
): Promise<void> {
  await apiClient.post('/rpc/set_active_profile', {
    accountId: params.accountId,
    languageCode: params.languageCode,
  });
}

// ═══════════════════════════════════════════════════════════════════════════
// GET OR CREATE PROFILE
// ═══════════════════════════════════════════════════════════════════════════

/**
 * Get or create a profile for an account and language
 * POST /rpc/get_or_create_account_profile
 */
export async function getOrCreateProfile(
  params: GetOrCreateProfileRequest
): Promise<GetOrCreateProfileResponse> {
  return apiClient.post<GetOrCreateProfileResponse>(
    '/rpc/get_or_create_account_profile',
    {
      accountId: params.accountId,
      languageCode: params.languageCode,
    }
  );
}

// ═══════════════════════════════════════════════════════════════════════════
// EXPORT NAMESPACE
// ═══════════════════════════════════════════════════════════════════════════

export const profilesApi = {
  setActiveProfile,
  getOrCreateProfile,
};
