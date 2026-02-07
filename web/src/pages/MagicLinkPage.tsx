import { useEffect, useState, useCallback } from 'react';
import { useLocation, useNavigate } from 'react-router-dom';
import { HiOutlineCheckCircle, HiOutlineExclamationTriangle } from 'react-icons/hi2';
import { Button } from '../components/ui/Button';
import { Spinner } from '../components/ui/Spinner';
import { ROUTES } from '../lib/constants';
import { useLoginHandler } from '../hooks/auth/useLoginHandler';

// ═══════════════════════════════════════════════════════════════════════════
// MAGIC LINK PAGE
// ═══════════════════════════════════════════════════════════════════════════

type PageState = 'loading' | 'success' | 'error' | 'no-token';

function MagicLinkPage() {
  const location = useLocation();
  const navigate = useNavigate();
  const { consumeMagicToken, isVerifying, error } = useLoginHandler();
  
  const searchParams = new URLSearchParams(location.search);
  const token = searchParams.get('token') ?? '';

  const [pageState, setPageState] = useState<PageState>(token ? 'loading' : 'no-token');
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
      await consumeMagicToken(token);
      setPageState('success');
      setRedirectCountdown(2);
    } catch (err) {
      setPageState('error');
    }
  }, [consumeMagicToken, token]);

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
        {(pageState === 'loading' || isVerifying) && (
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
              {error || 'Something went wrong. Please try again.'}
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
