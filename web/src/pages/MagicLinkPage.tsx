import { useEffect, useState, useCallback } from 'react';
import { useLocation, useNavigate } from 'react-router-dom';
import { HiOutlineCheckCircle, HiOutlineExclamationTriangle, HiOutlineDevicePhoneMobile } from 'react-icons/hi2';
import { Button } from '../components/ui/Button';
import { Spinner } from '../components/ui/Spinner';
import { authApi } from '../services/auth';
import { profilesApi } from '../services/profiles';
import { useAuth } from '../contexts/AuthContext';
import { useProfile } from '../contexts/ProfileContext';
import { ROUTES } from '../lib/constants';
import { ApiError } from '../services/api';
import { isPWAMode } from '../lib/storage';

// Default language if none set
const DEFAULT_LANGUAGE = 'en';

// ═══════════════════════════════════════════════════════════════════════════
// MAGIC LINK PAGE
// ═══════════════════════════════════════════════════════════════════════════

type PageState = 'loading' | 'success' | 'success-browser' | 'error' | 'no-token';

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
      // Check if running in PWA mode
      const inPWA = isPWAMode();

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
        
        // If in PWA, redirect normally. If in browser, show PWA open prompt
        if (inPWA) {
          setPageState('success');
          setRedirectCountdown(3);
        } else {
          setPageState('success-browser');
        }
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
  }, [token, setAccount, setActiveProfile]);

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

  const handleContinueInBrowser = useCallback(() => {
    navigate(ROUTES.APP);
  }, [navigate]);

  const handleOpenPWA = useCallback(() => {
    // Get the base URL without the /auth/magic path
    const baseUrl = window.location.origin;
    // Try to open the PWA - this works if user has added to home screen
    window.location.href = baseUrl + ROUTES.APP;
  }, []);

  // ─────────────────────────────────────────────────────────────────────────
  // Render
  // ─────────────────────────────────────────────────────────────────────────

  return (
    <div className="min-h-screen flex flex-col bg-app-sand-light">
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

        {/* Success state - in PWA */}
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

        {/* Success state - in browser (show PWA prompt) */}
        {pageState === 'success-browser' && (
          <>
            <div className="w-16 h-16 mx-auto mb-6 rounded-full bg-app-green/20 flex items-center justify-center">
              <HiOutlineCheckCircle className="w-8 h-8 text-app-green-dark" />
            </div>
            <h1 className="text-heading-lg font-semibold text-text-primary mb-2">
              You're signed in!
            </h1>
            <p className="text-body-md text-text-secondary mb-6">
              To continue, open the Chatterbox app from your home screen.
            </p>
            
            {/* Action buttons */}
            <div className="space-y-3">
              <Button
                variant="primary"
                onClick={handleOpenPWA}
                className="w-full bg-success-600 text-white hover:bg-success-700 active:bg-success-700"
                leftIcon={<HiOutlineDevicePhoneMobile />}
              >
                Open Chatterbox App
              </Button>
              <Button
                variant="secondary"
                onClick={handleContinueInBrowser}
                className="w-full bg-app-beige text-text-primary border border-border-secondary hover:bg-app-beige-dark"
              >
                Continue in browser
              </Button>
            </div>
            
            {/* Instructions */}
            <div className="mt-6 p-4 bg-app-sand-light rounded-2xl text-left">
              <p className="text-body-sm text-text-secondary mb-2">
                <strong className="text-text-primary">If you haven't added Chatterbox to your home screen yet:</strong>
              </p>
              <ol className="text-body-sm text-text-secondary space-y-1 list-decimal list-inside">
                <li>Tap the Share button in Safari</li>
                <li>Select "Add to Home Screen"</li>
                <li>Tap "Add"</li>
                <li>Open Chatterbox from your home screen</li>
              </ol>
            </div>
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
              This link is missing a valid token. Please request a new sign-in link.
            </p>
            <Button
              variant="primary"
              onClick={handleGoToLogin}
              className="w-full bg-success-600 text-white hover:bg-success-700 active:bg-success-700"
            >
              Go to login
            </Button>
          </>
        )}
      </div>
      </div>
    </div>
  );
}

export default MagicLinkPage;
