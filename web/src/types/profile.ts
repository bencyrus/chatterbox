/**
 * Profile types
 * Matches PostgREST RPC response shapes
 */

// ═══════════════════════════════════════════════════════════════════════════
// PROFILE
// ═══════════════════════════════════════════════════════════════════════════

export interface Profile {
  profileId: number;
  accountId: number;
  languageCode: string;
  createdAt: string;
}

// ═══════════════════════════════════════════════════════════════════════════
// API REQUESTS
// ═══════════════════════════════════════════════════════════════════════════

export interface SetActiveProfileRequest {
  accountId: number;
  languageCode: string;
}

export interface GetOrCreateProfileRequest {
  accountId: number;
  languageCode: string;
}

// ═══════════════════════════════════════════════════════════════════════════
// API RESPONSES
// ═══════════════════════════════════════════════════════════════════════════

export type GetOrCreateProfileResponse = Profile;
