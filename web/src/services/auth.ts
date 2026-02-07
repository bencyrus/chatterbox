/**
 * Authentication service
 * PostgREST RPC endpoints for magic link and OTP authentication
 */

import { apiClient } from './api';
import { setTokens } from '../lib/storage';
import type {
  RequestMagicLinkRequest,
  RequestMagicLinkResponse,
  LoginWithMagicTokenRequest,
  LoginWithMagicTokenResponse,
  RequestLoginCodeRequest,
  RequestLoginCodeResponse,
  LoginWithCodeRequest,
  LoginWithCodeResponse,
  MeResponse,
  AppConfigResponse,
} from '../types';

// ═══════════════════════════════════════════════════════════════════════════
// MAGIC LINK
// ═══════════════════════════════════════════════════════════════════════════

/**
 * Request a magic link to be sent to the user's email/phone
 * POST /rpc/request_magic_link
 */
export async function requestMagicLink(
  data: RequestMagicLinkRequest
): Promise<RequestMagicLinkResponse> {
  return apiClient.post<RequestMagicLinkResponse>(
    '/rpc/request_magic_link',
    data,
    { requiresAuth: false }
  );
}

/**
 * Login with a magic token (from email/SMS link)
 * POST /rpc/login_with_magic_token
 * Stores tokens automatically on success
 */
export async function loginWithMagicToken(
  data: LoginWithMagicTokenRequest
): Promise<LoginWithMagicTokenResponse> {
  const response = await apiClient.post<LoginWithMagicTokenResponse>(
    '/rpc/login_with_magic_token',
    data,
    { requiresAuth: false }
  );
  
  // Store tokens
  if (response.accessToken && response.refreshToken) {
    setTokens(response.accessToken, response.refreshToken);
  }
  
  return response;
}

// ═══════════════════════════════════════════════════════════════════════════
// OTP (ONE-TIME PASSWORD)
// ═══════════════════════════════════════════════════════════════════════════

/**
 * Request a login code to be sent to the user's email/phone
 * POST /rpc/request_login_code
 */
export async function requestLoginCode(
  data: RequestLoginCodeRequest
): Promise<RequestLoginCodeResponse> {
  return apiClient.post<RequestLoginCodeResponse>(
    '/rpc/request_login_code',
    data,
    { requiresAuth: false }
  );
}

/**
 * Login with a one-time code (from email/SMS)
 * POST /rpc/login_with_code
 * Stores tokens automatically on success
 */
export async function loginWithCode(
  data: LoginWithCodeRequest
): Promise<LoginWithCodeResponse> {
  const response = await apiClient.post<LoginWithCodeResponse>(
    '/rpc/login_with_code',
    data,
    { requiresAuth: false }
  );
  
  // Store tokens
  if (response.accessToken && response.refreshToken) {
    setTokens(response.accessToken, response.refreshToken);
  }
  
  return response;
}

// ═══════════════════════════════════════════════════════════════════════════
// USER DATA
// ═══════════════════════════════════════════════════════════════════════════

/**
 * Get the current authenticated user's account and active profile
 * POST /rpc/me
 */
export async function me(): Promise<MeResponse> {
  return apiClient.post<MeResponse>('/rpc/me', {});
}

// ═══════════════════════════════════════════════════════════════════════════
// APP CONFIG
// ═══════════════════════════════════════════════════════════════════════════

/**
 * Get application configuration (available languages, flags)
 * POST /rpc/app_config
 */
export async function appConfig(): Promise<AppConfigResponse> {
  return apiClient.post<AppConfigResponse>('/rpc/app_config', {});
}

// ═══════════════════════════════════════════════════════════════════════════
// EXPORT NAMESPACE
// ═══════════════════════════════════════════════════════════════════════════

export const authApi = {
  requestMagicLink,
  loginWithMagicToken,
  requestLoginCode,
  loginWithCode,
  me,
  appConfig,
};
