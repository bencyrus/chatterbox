/**
 * Account service
 * PostgREST RPC endpoints for account management
 */

import { apiClient } from './api';
import { clearTokens } from '../lib/storage';

// ═══════════════════════════════════════════════════════════════════════════
// LOGOUT
// ═══════════════════════════════════════════════════════════════════════════

/**
 * Logout the current user
 * Clears local tokens (no server endpoint for logout)
 */
export function logout(): void {
  clearTokens();
}

// ═══════════════════════════════════════════════════════════════════════════
// REQUEST ACCOUNT DELETION
// ═══════════════════════════════════════════════════════════════════════════

/**
 * Request account deletion
 * POST /rpc/request_account_deletion
 */
export async function requestAccountDeletion(accountId: number): Promise<void> {
  await apiClient.post('/rpc/request_account_deletion', { accountId });
  clearTokens();
}

// ═══════════════════════════════════════════════════════════════════════════
// EXPORT NAMESPACE
// ═══════════════════════════════════════════════════════════════════════════

export const accountApi = {
  logout,
  requestAccountDeletion,
};
