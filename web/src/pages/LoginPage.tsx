import { useState, useCallback, useRef, useEffect, type FormEvent } from 'react';
import { HiOutlineEnvelope, HiOutlineArrowRight, HiOutlineCheckCircle, HiOutlineArrowLeft } from 'react-icons/hi2';
import { Button } from '../components/ui/Button';
import { Input } from '../components/ui/Input';
import { useAppEnv } from '../contexts/AppEnvContext';
import { useLoginHandler } from '../hooks/auth/useLoginHandler';

// ═══════════════════════════════════════════════════════════════════════════
// LOGIN PAGE
// ═══════════════════════════════════════════════════════════════════════════

function LoginPage() {
  const env = useAppEnv();
  const login = useLoginHandler();
  const {
    preferredMethod,
    step,
    error,
    isStarting,
    isVerifying,
    isInCooldown,
    cooldownSeconds,
    start,
    resend,
    back,
    verifyOtp,
    clearError,
  } = login;

  const [email, setEmail] = useState('');

  // OTP state
  const [otpDigits, setOtpDigits] = useState<string[]>(['', '', '', '', '', '']);
  const otpInputRefs = useRef<(HTMLInputElement | null)[]>([]);

  // ─────────────────────────────────────────────────────────────────────────
  // Validate email
  // ─────────────────────────────────────────────────────────────────────────

  const isValidEmail = useCallback((value: string) => {
    return /^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(value);
  }, []);

  // ─────────────────────────────────────────────────────────────────────────
  // Handle email submit
  // ─────────────────────────────────────────────────────────────────────────

  const handleEmailSubmit = useCallback(async (e: FormEvent) => {
    e.preventDefault();
    if (!isValidEmail(email)) return;

    await start({ identifier: email });
    if (preferredMethod === 'otp') {
      // Focus first OTP input after render (PWA flow)
      setTimeout(() => otpInputRefs.current[0]?.focus(), 100);
    }
  }, [email, isValidEmail, preferredMethod, start]);

  // ─────────────────────────────────────────────────────────────────────────
  // Handle OTP input
  // ─────────────────────────────────────────────────────────────────────────

  const handleOtpChange = useCallback((index: number, value: string) => {
    // Only allow digits
    const digit = value.replace(/\D/g, '').slice(-1);
    
    setOtpDigits(prev => {
      const next = [...prev];
      next[index] = digit;
      return next;
    });

    // Auto-advance to next input
    if (digit && index < 5) {
      otpInputRefs.current[index + 1]?.focus();
    }
  }, []);

  const handleOtpKeyDown = useCallback((index: number, e: React.KeyboardEvent<HTMLInputElement>) => {
    if (e.key === 'Backspace' && !otpDigits[index] && index > 0) {
      // Move to previous input on backspace if current is empty
      otpInputRefs.current[index - 1]?.focus();
    }
  }, [otpDigits]);

  const handleOtpPaste = useCallback((e: React.ClipboardEvent) => {
    e.preventDefault();
    const pasted = e.clipboardData.getData('text').replace(/\D/g, '').slice(0, 6);
    if (pasted.length > 0) {
      const digits = pasted.split('');
      setOtpDigits(prev => {
        const next = [...prev];
        digits.forEach((d, i) => { next[i] = d; });
        return next;
      });
      // Focus the next empty input or the last one
      const nextFocus = Math.min(digits.length, 5);
      otpInputRefs.current[nextFocus]?.focus();
    }
  }, []);

  // ─────────────────────────────────────────────────────────────────────────
  // Auto-submit OTP when all 6 digits are entered
  // ─────────────────────────────────────────────────────────────────────────

  useEffect(() => {
    const code = otpDigits.join('');
    if (code.length !== 6 || isVerifying) return;

    const verifyCode = async () => {
      try {
        await verifyOtp(code);
      } catch {
        // Clear OTP and refocus first input
        setOtpDigits(['', '', '', '', '', '']);
        setTimeout(() => otpInputRefs.current[0]?.focus(), 100);
      }
    };

    verifyCode();
  }, [otpDigits, isVerifying, verifyOtp]);

  // ─────────────────────────────────────────────────────────────────────────
  // Handle resend code
  // ─────────────────────────────────────────────────────────────────────────

  const handleResendCode = useCallback(async () => {
    await resend();
    setOtpDigits(['', '', '', '', '', '']);
    setTimeout(() => otpInputRefs.current[0]?.focus(), 100);
  }, [resend]);

  // ─────────────────────────────────────────────────────────────────────────
  // Handle email change
  // ─────────────────────────────────────────────────────────────────────────

  const handleEmailChange = useCallback((e: React.ChangeEvent<HTMLInputElement>) => {
    setEmail(e.target.value);
    if (error) clearError();
  }, [clearError, error]);

  const handleBackToEmail = useCallback(() => {
    setOtpDigits(['', '', '', '', '', '']);
    back();
  }, [back]);

  // ─────────────────────────────────────────────────────────────────────────
  // Render: OTP entry (PWA mode)
  // ─────────────────────────────────────────────────────────────────────────

  if (step === 'otp') {
    return (
      <div className="min-h-screen flex flex-col bg-app-sand-light">
        <div className="flex-1 flex items-center justify-center px-page">
        <div className="w-full max-w-sm text-center animate-fade-in bg-white rounded-3xl shadow-card border border-border-secondary p-8">
          {/* App icon */}
          <img
            src="https://storage.googleapis.com/chatterbox-public-assets/public-chatterbox-logo-color-bg.png"
            alt="Chatterbox"
            className="w-20 h-20 mx-auto mb-6 rounded-2xl shadow-card"
          />
          
          {/* Title */}
          <h1 className="text-heading-lg font-semibold text-text-primary mb-2">
            Enter your code
          </h1>
          <p className="text-body-md text-text-secondary mb-8">
            We sent a 6-digit code to{' '}
            <span className="font-medium text-text-primary">{email}</span>
          </p>

          {/* OTP Input */}
          <div className="flex justify-center gap-2 mb-6" onPaste={handleOtpPaste}>
            {otpDigits.map((digit, index) => (
              <input
                key={index}
                ref={(el) => { otpInputRefs.current[index] = el; }}
                type="text"
                inputMode="numeric"
                autoComplete="one-time-code"
                maxLength={1}
                value={digit}
                onChange={(e) => handleOtpChange(index, e.target.value)}
                onKeyDown={(e) => handleOtpKeyDown(index, e)}
                disabled={isVerifying}
                className={`
                  w-12 h-14 text-center text-xl font-bold rounded-xl border-2
                  focus:outline-none focus:ring-2 focus:ring-success-600 focus:border-success-600
                  transition-colors
                  ${error 
                    ? 'border-error-400 bg-error-50' 
                    : digit 
                      ? 'border-success-400 bg-success-50' 
                      : 'border-border-secondary bg-white'
                  }
                  ${isVerifying ? 'opacity-50' : ''}
                `}
              />
            ))}
          </div>

          {/* Verifying indicator */}
          {isVerifying && (
            <p className="text-body-sm text-success-600 mb-4 animate-pulse">
              Verifying code...
            </p>
          )}

          {/* Error */}
          {error && (
            <p className="text-body-sm text-error-600 mb-4">
              {error}
            </p>
          )}

          {/* Resend / Back */}
          <div className="pt-6 border-t border-border-secondary space-y-3">
            <p className="text-body-sm text-text-tertiary">
              Didn't receive the code? Check your spam folder.
            </p>
            <Button
              variant="secondary"
              size="sm"
              className="bg-app-beige text-text-primary border border-border-secondary hover:bg-app-beige-dark"
              onClick={handleResendCode}
              isLoading={isStarting}
            >
              Resend code
            </Button>
            <div>
              <button
                onClick={handleBackToEmail}
                className="text-body-sm text-text-tertiary hover:text-text-secondary underline inline-flex items-center gap-1"
              >
                <HiOutlineArrowLeft className="w-3 h-3" />
                Use a different email
              </button>
            </div>
          </div>
        </div>
        </div>
      </div>
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Render: Magic link sent (browser mode)
  // ─────────────────────────────────────────────────────────────────────────

  if (step === 'magic_link_sent' && !error) {
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
              onClick={() => resend()}
              isLoading={isStarting}
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
  // Render: Email entry form
  // ─────────────────────────────────────────────────────────────────────────

  const emailError = error;

  return (
    <div className="min-h-screen flex flex-col bg-app-sand-light">
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
        <form onSubmit={handleEmailSubmit} className="space-y-stack-md">
          <Input
            type="email"
            label="Email"
            placeholder="you@example.com"
            value={email}
            onChange={handleEmailChange}
            error={emailError || undefined}
            autoComplete="email"
            autoFocus
          />
          
          <Button
            type="submit"
            variant="primary"
            size="lg"
            className="w-full bg-success-600 text-white hover:bg-success-700 active:bg-success-700"
            isLoading={isStarting}
            disabled={!isValidEmail(email) || isInCooldown}
            rightIcon={!isStarting ? <HiOutlineArrowRight /> : undefined}
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
            {env.isPwa ? "We'll send you a sign-in code" : "We'll send you a magic link to sign in"}
          </p>
        </div>
      </div>
      </div>
    </div>
  );
}

export default LoginPage;
