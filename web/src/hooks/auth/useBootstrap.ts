import { useEffect, useCallback } from 'react';
import { useAuth } from '../../contexts/AuthContext';
import { useProfile } from '../../contexts/ProfileContext';
import { authApi } from '../../services/auth';
import { profilesApi } from '../../services/profiles';
import { hasTokens, clearTokens } from '../../lib/storage';

// ═══════════════════════════════════════════════════════════════════════════
// TYPES
// ═══════════════════════════════════════════════════════════════════════════

interface UseBootstrapReturn {
  /** Re-run the bootstrap process */
  bootstrap: () => Promise<void>;
}

// Default language if none set
const DEFAULT_LANGUAGE = 'en';

// ═══════════════════════════════════════════════════════════════════════════
// HOOK
// ═══════════════════════════════════════════════════════════════════════════

/**
 * Bootstrap hook to initialize auth state on app load
 * Checks for stored tokens and validates them with the server
 */
export function useBootstrap(): UseBootstrapReturn {
  const { setAccount, setLoading, logout } = useAuth();
  const { setActiveProfile, reset: resetProfile } = useProfile();

  // ─────────────────────────────────────────────────────────────────────────
  // Bootstrap function
  // ─────────────────────────────────────────────────────────────────────────

  const bootstrap = useCallback(async () => {
    setLoading(true);

    // Check if we have stored tokens
    if (!hasTokens()) {
      console.log('[Bootstrap] No tokens found in localStorage');
      setLoading(false);
      return;
    }

    console.log('[Bootstrap] Tokens found, validating...');

    try {
      // Validate tokens by fetching user data
      const response = await authApi.me();
      console.log('[Bootstrap] Token validation successful', response.account);
      
      if (response.account) {
        setAccount(response.account);
        
        // Set active profile if available
        if (response.activeProfile) {
          setActiveProfile(response.activeProfile);
        } else {
          // No active profile - create one with default language
          try {
            // Get app config for default language
            const config = await authApi.appConfig();
            const defaultLang = config.defaultProfileLanguageCode || DEFAULT_LANGUAGE;
            
            // Create profile
            const profile = await profilesApi.getOrCreateProfile({
              accountId: response.account.accountId,
              languageCode: defaultLang,
            });
            
            // Set it as active
            await profilesApi.setActiveProfile({
              accountId: response.account.accountId,
              languageCode: defaultLang,
            });
            
            // Update context
            setActiveProfile({
              accountId: response.account.accountId,
              profileId: profile.profileId,
              languageCode: profile.languageCode,
            });
          } catch (profileErr) {
            console.error('Failed to create default profile:', profileErr);
            // Continue without profile - user can set it manually
          }
        }
      } else {
        // No account returned, clear tokens and logout
        clearTokens();
        resetProfile();
        logout();
      }
    } catch (err) {
      // Token validation failed, clear tokens
      console.error('[Bootstrap] Token validation failed:', err);
      clearTokens();
      resetProfile();
      logout();
    }
  }, [setAccount, setLoading, logout, setActiveProfile, resetProfile]);

  // ─────────────────────────────────────────────────────────────────────────
  // Run on mount
  // ─────────────────────────────────────────────────────────────────────────

  useEffect(() => {
    bootstrap();
  }, [bootstrap]);

  // ─────────────────────────────────────────────────────────────────────────
  // Return
  // ─────────────────────────────────────────────────────────────────────────

  return {
    bootstrap,
  };
}
