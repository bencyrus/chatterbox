import { useCallback } from 'react';
import { useAuth } from '../../contexts/AuthContext';
import { useProfile } from '../../contexts/ProfileContext';
import { authApi } from '../../services/auth';
import { profilesApi } from '../../services/profiles';
import { hasTokens } from '../../lib/storage';

// Default language if none set
const DEFAULT_LANGUAGE = 'en';

/**
 * Centralized session logic:
 * - bootstrap() for app startup
 * - hydrateSession() after a successful login (OTP or magic link)
 */
export function useAuthSession() {
  const { setAccount, setLoading, logout } = useAuth();
  const { setActiveProfile, reset: resetProfile } = useProfile();

  const ensureActiveProfile = useCallback(
    async (accountId: number) => {
      const config = await authApi.appConfig();
      const defaultLang = config.defaultProfileLanguageCode || DEFAULT_LANGUAGE;

      const profile = await profilesApi.getOrCreateProfile({
        accountId,
        languageCode: defaultLang,
      });

      await profilesApi.setActiveProfile({
        accountId,
        languageCode: defaultLang,
      });

      setActiveProfile({
        accountId,
        profileId: profile.profileId,
        languageCode: profile.languageCode,
      });
    },
    [setActiveProfile]
  );

  const hydrateSession = useCallback(async () => {
    // Validate tokens by fetching user data
    const response = await authApi.me();

    if (!response.account) {
      throw new Error('Missing account from /rpc/me');
    }

    setAccount(response.account);

    if (response.activeProfile) {
      setActiveProfile(response.activeProfile);
      return;
    }

    try {
      await ensureActiveProfile(response.account.accountId);
    } catch (profileErr) {
      // Continue without profile - user can set it manually
      console.error('Failed to create default profile:', profileErr);
    }
  }, [ensureActiveProfile, setAccount, setActiveProfile]);

  const resetSession = useCallback(() => {
    resetProfile();
    logout();
  }, [logout, resetProfile]);

  const bootstrap = useCallback(async () => {
    setLoading(true);

    if (!hasTokens()) {
      setLoading(false);
      return;
    }

    try {
      await hydrateSession();
    } catch {
      resetSession();
    }
  }, [hydrateSession, resetSession, setLoading]);

  return {
    bootstrap,
    hydrateSession,
    resetSession,
  };
}

