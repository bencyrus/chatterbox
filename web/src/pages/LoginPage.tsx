import { useState, useCallback, type FormEvent } from 'react';
import { HiOutlineEnvelope, HiOutlineArrowRight, HiOutlineCheckCircle } from 'react-icons/hi2';
import { Button } from '../components/ui/Button';
import { Input } from '../components/ui/Input';
import { useMagicLink } from '../hooks/auth/useMagicLink';

// ═══════════════════════════════════════════════════════════════════════════
// LOGIN PAGE
// ═══════════════════════════════════════════════════════════════════════════

function LoginPage() {
  const [email, setEmail] = useState('');
  const [emailSent, setEmailSent] = useState(false);
  const {
    requestLink,
    isLoading,
    error,
    isInCooldown,
    cooldownSeconds,
    clearError,
  } = useMagicLink();

  // ─────────────────────────────────────────────────────────────────────────
  // Validate email
  // ─────────────────────────────────────────────────────────────────────────

  const isValidEmail = useCallback((value: string) => {
    return /^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(value);
  }, []);

  // ─────────────────────────────────────────────────────────────────────────
  // Handle submit
  // ─────────────────────────────────────────────────────────────────────────

  const handleSubmit = useCallback(async (e: FormEvent) => {
    e.preventDefault();
    
    if (!isValidEmail(email)) {
      return;
    }
    
    await requestLink(email);
    if (!error) {
      setEmailSent(true);
    }
  }, [email, isValidEmail, requestLink, error]);

  // ─────────────────────────────────────────────────────────────────────────
  // Handle email change
  // ─────────────────────────────────────────────────────────────────────────

  const handleEmailChange = useCallback((e: React.ChangeEvent<HTMLInputElement>) => {
    setEmail(e.target.value);
    if (error) {
      clearError();
    }
    if (emailSent) {
      setEmailSent(false);
    }
  }, [error, clearError, emailSent]);

  // ─────────────────────────────────────────────────────────────────────────
  // Render success state
  // ─────────────────────────────────────────────────────────────────────────

  if (emailSent && !error) {
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
          
          {/* Success icon */}
          <div className="w-16 h-16 mx-auto mb-6 rounded-full bg-app-green/20 flex items-center justify-center">
            <HiOutlineCheckCircle className="w-8 h-8 text-app-green-dark" />
          </div>
          
          {/* Success message */}
          <h1 className="text-heading-lg font-semibold text-text-primary mb-3">
            Check your email
          </h1>
          <p className="text-body-md text-text-secondary mb-6">
            We sent a magic link to <span className="font-medium text-text-primary">{email}</span>.
            Click the link in the email to sign in.
          </p>
          
          {/* Resend section */}
          <div className="pt-6 border-t border-border-secondary">
            <p className="text-body-sm text-text-tertiary mb-4">
              Didn't receive the email? Check your spam folder or try again.
            </p>
            <Button
              variant="secondary"
              size="sm"
              className="bg-app-beige text-text-primary border border-border-secondary hover:bg-app-beige-dark"
              onClick={() => requestLink(email)}
              isLoading={isLoading}
              disabled={isInCooldown}
            >
              {isInCooldown ? `Resend in ${cooldownSeconds}s` : 'Resend email'}
            </Button>
          </div>
        </div>
        </div>
      </div>
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Render form
  // ─────────────────────────────────────────────────────────────────────────

  return (
    <div className="min-h-screen flex flex-col bg-app-sand">
      <div className="flex-1 flex items-center justify-center px-page">
      <div className="w-full max-w-sm animate-fade-in bg-white rounded-3xl shadow-card border border-border-secondary p-8">
        {/* App icon */}
        <div className="text-center mb-8">
          <img
            src="https://storage.googleapis.com/chatterbox-public-assets/public-chatterbox-logo-color-bg.png"
            alt="Chatterbox"
            className="w-20 h-20 mx-auto mb-6 rounded-2xl shadow-card"
          />
          <h1 className="text-heading-lg font-semibold text-text-primary mb-2">
            Welcome to Chatterbox
          </h1>
          <p className="text-body-md text-text-secondary">
            Practice speaking any language with confidence
          </p>
        </div>

        {/* Login form */}
        <form onSubmit={handleSubmit} className="space-y-stack-md">
          <Input
            type="email"
            label="Email"
            placeholder="you@example.com"
            value={email}
            onChange={handleEmailChange}
            error={error || undefined}
            autoComplete="email"
            autoFocus
          />
          
          <Button
            type="submit"
            variant="primary"
            size="lg"
            className="w-full bg-success-600 text-white hover:bg-success-700 active:bg-success-700"
            isLoading={isLoading}
            disabled={!isValidEmail(email) || isInCooldown}
            rightIcon={!isLoading ? <HiOutlineArrowRight /> : undefined}
          >
            {isInCooldown 
              ? `Wait ${cooldownSeconds}s` 
              : 'Continue with email'
            }
          </Button>
        </form>

        {/* Info */}
        <div className="mt-8 text-center">
          <p className="text-body-sm text-text-tertiary">
            <HiOutlineEnvelope className="inline-block w-4 h-4 mr-1 -mt-0.5" />
            We'll send you a magic link to sign in
          </p>
        </div>
      </div>
      </div>
    </div>
  );
}

export default LoginPage;
