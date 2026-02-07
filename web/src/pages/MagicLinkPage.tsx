import { useEffect, useState, useCallback } from 'react';
import { useLocation, useNavigate } from 'react-router-dom';
import { HiOutlineCheckCircle, HiOutlineExclamationTriangle } from 'react-icons/hi2';
import { Button } from '../components/ui/Button';
import { Spinner } from '../components/ui/Spinner';
import { authApi } from '../services/auth';
import { profilesApi } from '../services/profiles';
import { useAuth } from '../contexts/AuthContext';
import { useProfile } from '../contexts/ProfileContext';
import { ROUTES } from '../lib/constants';
import { ApiError } from '../services/api';

// Default language if none set
const DEFAULT_LANGUAGE = 'en';

// ═══════════════════════════════════════════════════════════════════════════
// MAGIC LINK PAGE
// ═══════════════════════════════════════════════════════════════════════════

type PageState = 'loading' | 'success' | 'error' | 'no-token';

function MagicLinkPage() {
  const location = useLocation();
  const navigate = useNavigate();
  const { setAccount } = useAuth();
  const { setActiveProfile } = useProfile();
  
  const searchParams = new URLSearchParams(location.search);
  const token = searchParams.get('token') ?? '';

  const [pageState, setPageState] = useState<PageState>(token ? 'loading' : 'no-token');
  const [errorMessage, setErrorMessage] = useState<string>('');
  const [redirectCountdown, setRedirectCountdown] = useState<number | null>(null);

  // ─────────────────────────────────────────────────────────────────────────
  // Handle login
  // ─────────────────────────────────────────────────────────────────────────

  const handleLogin = useCallback(async () => {
    if (!token) {
      setPageState('no-token');
      return;
    }

    try {
      // Login with magic token
      await authApi.loginWithMagicToken({ token });
      
      // Fetch user data
      const meResponse = await authApi.me();
      
      if (meResponse.account) {
        setAccount(meResponse.account);
        
        // Set active profile if available, or create one
        if (meResponse.activeProfile) {
          setActiveProfile(meResponse.activeProfile);
        } else {
          // No active profile - create one with default language
          try {
            const config = await authApi.appConfig();
            const defaultLang = config.defaultProfileLanguageCode || DEFAULT_LANGUAGE;
            
            const profile = await profilesApi.getOrCreateProfile({
              accountId: meResponse.account.accountId,
              languageCode: defaultLang,
            });
            
            await profilesApi.setActiveProfile({
              accountId: meResponse.account.accountId,
              languageCode: defaultLang,
            });
            
            setActiveProfile({
              accountId: meResponse.account.accountId,
              profileId: profile.profileId,
              languageCode: profile.languageCode,
            });
          } catch (profileErr) {
            console.error('Failed to create default profile:', profileErr);
          }
        }
        
        setPageState('success');
        setRedirectCountdown(3);
      } else {
        throw new Error('Failed to get account info');
      }
    } catch (err) {
      setPageState('error');
      if (err instanceof ApiError) {
        if (err.status === 401 || err.status === 400) {
          setErrorMessage('This link has expired or already been used. Please request a new one.');
        } else {
          setErrorMessage(err.message);
        }
      } else {
        setErrorMessage('Something went wrong. Please try again.');
      }
    }
  }, [token, setAccount, setActiveProfile, navigate]);

  // ─────────────────────────────────────────────────────────────────────────
  // Effect: Login on mount
  // ─────────────────────────────────────────────────────────────────────────

  useEffect(() => {
    if (token) {
      handleLogin();
    }
  }, [token, handleLogin]);

  // ─────────────────────────────────────────────────────────────────────────
  // Effect: Countdown after success
  // ─────────────────────────────────────────────────────────────────────────

  useEffect(() => {
    if (pageState !== 'success' || redirectCountdown === null) {
      return;
    }

    if (redirectCountdown <= 0) {
      navigate(ROUTES.APP, { replace: true });
      return;
    }

    const timer = setTimeout(() => {
      setRedirectCountdown((current) =>
        current === null ? null : current - 1
      );
    }, 1000);

    return () => clearTimeout(timer);
  }, [pageState, redirectCountdown, navigate]);

  // ─────────────────────────────────────────────────────────────────────────
  // Handle navigation
  // ─────────────────────────────────────────────────────────────────────────

  const handleGoToLogin = useCallback(() => {
    navigate(ROUTES.LOGIN);
  }, [navigate]);

  // ─────────────────────────────────────────────────────────────────────────
  // App redirect (for mobile deep link)
  // ─────────────────────────────────────────────────────────────────────────

  const appUrl = token
    ? `chatterbox://auth/magic?token=${encodeURIComponent(token)}`
    : 'chatterbox://auth/magic';

  const handleOpenApp = useCallback(() => {
    window.location.href = appUrl;
  }, [appUrl]);

  // ─────────────────────────────────────────────────────────────────────────
  // Render
  // ─────────────────────────────────────────────────────────────────────────

  return (
    <div className="min-h-screen flex flex-col bg-app-sand">
      <div className="flex-1 flex items-center justify-center px-page">
      <div className="w-full max-w-sm text-center animate-fade-in bg-white rounded-3xl shadow-card border border-border-secondary p-8">
        {/* App icon */}
        <img
          src="https://storage.googleapis.com/chatterbox-public-assets/public-chatterbox-logo-color-bg.png"
          alt="Chatterbox"
          className="w-20 h-20 mx-auto mb-8 rounded-2xl shadow-card"
        />

        {/* Loading state */}
        {pageState === 'loading' && (
          <>
            <Spinner size="lg" className="mx-auto mb-6" />
            <h1 className="text-heading-lg font-semibold text-text-primary mb-2">
              Signing you in...
            </h1>
            <p className="text-body-md text-text-secondary">
              Please wait while we verify your magic link.
            </p>
          </>
        )}

        {/* Success state */}
        {pageState === 'success' && (
          <>
            <div className="w-16 h-16 mx-auto mb-6 rounded-full bg-app-green/20 flex items-center justify-center">
              <HiOutlineCheckCircle className="w-8 h-8 text-app-green-dark" />
            </div>
            <h1 className="text-heading-lg font-semibold text-text-primary mb-2">
              Welcome back!
            </h1>
            <p className="text-body-md text-text-secondary">
              You've been signed in successfully. Redirecting in{' '}
              {redirectCountdown ?? 3} seconds.
            </p>
          </>
        )}

        {/* Error state */}
        {pageState === 'error' && (
          <>
            <div className="w-16 h-16 mx-auto mb-6 rounded-full bg-error-100 flex items-center justify-center">
              <HiOutlineExclamationTriangle className="w-8 h-8 text-error-600" />
            </div>
            <h1 className="text-heading-lg font-semibold text-text-primary mb-2">
              Unable to sign in
            </h1>
            <p className="text-body-md text-text-secondary mb-6">
              {errorMessage}
            </p>
            <Button
              variant="primary"
              className="bg-success-600 text-white hover:bg-success-700 active:bg-success-700"
              onClick={handleGoToLogin}
            >
              Request new link
            </Button>
          </>
        )}

        {/* No token state */}
        {pageState === 'no-token' && (
          <>
            <h1 className="text-heading-lg font-semibold text-text-primary mb-2">
              Sign in to Chatterbox
            </h1>
            <p className="text-body-md text-text-secondary mb-6">
              This link is meant to sign you into the Chatterbox app.
            </p>
            <div className="space-y-3">
              <Button
                variant="primary"
                onClick={handleOpenApp}
                className="w-full bg-success-600 text-white hover:bg-success-700 active:bg-success-700"
              >
                Open in Chatterbox app
              </Button>
              <Button
                variant="secondary"
                onClick={handleGoToLogin}
                className="w-full bg-app-beige text-text-primary border border-border-secondary hover:bg-app-beige-dark"
              >
                Continue on web
              </Button>
            </div>
            <p className="text-body-sm text-text-tertiary mt-6">
              If you opened this link from an email, the app should open automatically.
              If not, tap the button above.
            </p>
          </>
        )}
      </div>
      </div>
    </div>
  );
}

export default MagicLinkPage;
