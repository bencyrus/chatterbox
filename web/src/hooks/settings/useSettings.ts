import { useState, useCallback } from 'react';
import { useNavigate } from 'react-router-dom';
import { profilesApi } from '../../services/profiles';
import { accountApi } from '../../services/account';
import { useAuth } from '../../contexts/AuthContext';
import { useProfile } from '../../contexts/ProfileContext';
import { useToast } from '../../contexts/ToastContext';
import { ApiError } from '../../services/api';
import { ROUTES } from '../../lib/constants';

// ═══════════════════════════════════════════════════════════════════════════
// TYPES
// ═══════════════════════════════════════════════════════════════════════════

interface UseSettingsReturn {
  /** Change the active language */
  changeLanguage: (languageCode: string) => Promise<void>;
  /** Whether language change is in progress */
  isChangingLanguage: boolean;
  /** Logout the user */
  logout: () => Promise<void>;
  /** Whether logout is in progress */
  isLoggingOut: boolean;
  /** Delete the account */
  deleteAccount: () => Promise<void>;
  /** Whether account deletion is in progress */
  isDeletingAccount: boolean;
}

// ═══════════════════════════════════════════════════════════════════════════
// HOOK
// ═══════════════════════════════════════════════════════════════════════════

export function useSettings(): UseSettingsReturn {
  const navigate = useNavigate();
  const { account, logout: authLogout } = useAuth();
  const { setActiveProfile, reset: resetProfile } = useProfile();
  const { showToast } = useToast();

  const [isChangingLanguage, setIsChangingLanguage] = useState(false);
  const [isLoggingOut, setIsLoggingOut] = useState(false);
  const [isDeletingAccount, setIsDeletingAccount] = useState(false);

  // ─────────────────────────────────────────────────────────────────────────
  // Change language
  // ─────────────────────────────────────────────────────────────────────────

  const changeLanguage = useCallback(async (languageCode: string) => {
    if (!account) return;

    setIsChangingLanguage(true);

    try {
      // Get or create profile for the language
      const profile = await profilesApi.getOrCreateProfile({
        accountId: account.accountId,
        languageCode,
      });
      
      // Set it as active
      await profilesApi.setActiveProfile({
        accountId: account.accountId,
        languageCode,
      });
      
      // Update context with the new active profile
      setActiveProfile({
        accountId: account.accountId,
        profileId: profile.profileId,
        languageCode: profile.languageCode,
      });
      
      showToast('Language updated', 'success');
    } catch (err) {
      const message =
        err instanceof ApiError
          ? err.message
          : 'Failed to change language.';
      showToast(message, 'error');
    } finally {
      setIsChangingLanguage(false);
    }
  }, [account, setActiveProfile, showToast]);

  // ─────────────────────────────────────────────────────────────────────────
  // Logout
  // ─────────────────────────────────────────────────────────────────────────

  const logout = useCallback(async () => {
    setIsLoggingOut(true);

    try {
      accountApi.logout();
      resetProfile();
      authLogout();
      navigate(ROUTES.LOGIN, { replace: true });
    } catch {
      // Even if something fails, clear local state
      resetProfile();
      authLogout();
      navigate(ROUTES.LOGIN, { replace: true });
    } finally {
      setIsLoggingOut(false);
    }
  }, [authLogout, resetProfile, navigate]);

  // ─────────────────────────────────────────────────────────────────────────
  // Delete account
  // ─────────────────────────────────────────────────────────────────────────

  const deleteAccount = useCallback(async () => {
    if (!account) return;

    setIsDeletingAccount(true);

    try {
      await accountApi.requestAccountDeletion(account.accountId);
      resetProfile();
      authLogout();
      showToast('Account deletion requested', 'success');
      navigate(ROUTES.LOGIN, { replace: true });
    } catch (err) {
      const message =
        err instanceof ApiError
          ? err.message
          : 'Failed to delete account.';
      showToast(message, 'error');
    } finally {
      setIsDeletingAccount(false);
    }
  }, [account, authLogout, resetProfile, navigate, showToast]);

  // ─────────────────────────────────────────────────────────────────────────
  // Return
  // ─────────────────────────────────────────────────────────────────────────

  return {
    changeLanguage,
    isChangingLanguage,
    logout,
    isLoggingOut,
    deleteAccount,
    isDeletingAccount,
  };
}
