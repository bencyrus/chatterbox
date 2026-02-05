/**
 * Authentication and account types
 * Matches PostgREST RPC response shapes
 */

// ═══════════════════════════════════════════════════════════════════════════
// MAGIC LINK
// ═══════════════════════════════════════════════════════════════════════════

export interface RequestMagicLinkRequest {
  identifier: string; // email or phone
}

export interface RequestMagicLinkResponse {
  success: boolean;
}

export interface LoginWithMagicTokenRequest {
  token: string;
}

export interface LoginWithMagicTokenResponse {
  accessToken: string;
  refreshToken: string;
}

// ═══════════════════════════════════════════════════════════════════════════
// ACCOUNT
// ═══════════════════════════════════════════════════════════════════════════

export interface Account {
  accountId: number;
  email: string | null;
  phoneNumber: string | null;
  accountRole: string;
  lastLoginAt: string | null;
  flags: string[];
}

// ═══════════════════════════════════════════════════════════════════════════
// ACTIVE PROFILE SUMMARY (from /rpc/me)
// ═══════════════════════════════════════════════════════════════════════════

export interface ActiveProfileSummary {
  accountId: number;
  profileId: number;
  languageCode: string;
}

// ═══════════════════════════════════════════════════════════════════════════
// ME RESPONSE
// ═══════════════════════════════════════════════════════════════════════════

export interface MeResponse {
  account: Account;
  activeProfile: ActiveProfileSummary | null;
}

// ═══════════════════════════════════════════════════════════════════════════
// APP CONFIG
// ═══════════════════════════════════════════════════════════════════════════

export interface AppConfigResponse {
  defaultProfileLanguageCode: string;
  availableLanguageCodes: string[];
  flags: string[];
}
