import { useCallback, useMemo, useState } from 'react';
import { useAppEnv } from '../../contexts/AppEnvContext';
import { authApi } from '../../services/auth';
import { ApiError } from '../../services/api';
import { useMagicLink } from './useMagicLink';
import { useAuthSession } from './useAuthSession';

export type LoginMethod = 'otp' | 'magic_link';
export type LoginStep = 'enter_identifier' | 'otp' | 'magic_link_sent';

interface StartLoginArgs {
  identifier: string; // email or phone
  method?: LoginMethod;
}

interface UseLoginHandlerReturn {
  /** Which method the app prefers (PWA => otp, browser => magic link). */
  preferredMethod: LoginMethod;
  /** Current login step for UI. */
  step: LoginStep;
  /** Last identifier used (email/phone). */
  identifier: string;
  /** Any error to show in UI. */
  error: string | null;

  /** Loading flags */
  isStarting: boolean; // requesting code or sending magic link
  isVerifying: boolean; // verifying OTP or consuming magic token

  /** Magic link cooldown (browser only). */
  isInCooldown: boolean;
  cooldownSeconds: number;

  /** Actions */
  start: (args: StartLoginArgs) => Promise<void>;
  resend: () => Promise<void>;
  back: () => void;
  verifyOtp: (code: string) => Promise<void>;
  consumeMagicToken: (token: string) => Promise<void>;
  clearError: () => void;
}

export function useLoginHandler(): UseLoginHandlerReturn {
  const env = useAppEnv();
  const preferredMethod: LoginMethod = useMemo(
    () => (env.isPwa ? 'otp' : 'magic_link'),
    [env.isPwa]
  );

  const { hydrateSession } = useAuthSession();
  const magic = useMagicLink();

  const [step, setStep] = useState<LoginStep>('enter_identifier');
  const [identifier, setIdentifier] = useState('');
  const [error, setError] = useState<string | null>(null);
  const [isStarting, setIsStarting] = useState(false);
  const [isVerifying, setIsVerifying] = useState(false);

  const clearError = useCallback(() => setError(null), []);

  const start = useCallback(
    async ({ identifier: id, method }: StartLoginArgs) => {
      const chosen: LoginMethod = method ?? preferredMethod;
      setIdentifier(id);
      setError(null);
      setIsStarting(true);

      try {
        if (chosen === 'otp') {
          await authApi.requestLoginCode({ identifier: id });
          setStep('otp');
          return;
        }

        const result = await magic.requestLink(id);
        if (!result.ok) {
          setError(result.error);
          return;
        }
        setStep('magic_link_sent');
      } catch (err) {
        if (err instanceof ApiError) {
          setError(err.message);
        } else {
          setError('Unable to start login. Please try again.');
        }
      } finally {
        setIsStarting(false);
      }
    },
    [magic, preferredMethod]
  );

  const resend = useCallback(async () => {
    setError(null);
    setIsStarting(true);
    try {
      if (step === 'otp') {
        await authApi.requestLoginCode({ identifier });
        return;
      }
      if (step === 'magic_link_sent') {
        const result = await magic.requestLink(identifier);
        if (!result.ok) {
          setError(result.error);
        }
      }
    } catch (err) {
      if (err instanceof ApiError) {
        setError(err.message);
      } else {
        setError('Unable to resend. Please try again.');
      }
    } finally {
      setIsStarting(false);
    }
  }, [identifier, magic, step]);

  const back = useCallback(() => {
    setStep('enter_identifier');
    setError(null);
  }, []);

  const verifyOtp = useCallback(
    async (code: string) => {
      setError(null);
      setIsVerifying(true);
      try {
        await authApi.loginWithCode({ identifier, code });
        await hydrateSession();
      } catch (err) {
        if (err instanceof ApiError) {
          if (err.status === 400 || err.status === 401) {
            setError('Invalid or expired code. Please try again.');
          } else {
            setError(err.message);
          }
        } else {
          setError('Verification failed. Please try again.');
        }
        throw err;
      } finally {
        setIsVerifying(false);
      }
    },
    [hydrateSession, identifier]
  );

  const consumeMagicToken = useCallback(
    async (token: string) => {
      setError(null);
      setIsVerifying(true);
      try {
        await authApi.loginWithMagicToken({ token });
        await hydrateSession();
      } catch (err) {
        if (err instanceof ApiError) {
          if (err.status === 401 || err.status === 400) {
            setError('This link has expired or already been used. Please request a new one.');
          } else {
            setError(err.message);
          }
        } else {
          setError('Something went wrong. Please try again.');
        }
        throw err;
      } finally {
        setIsVerifying(false);
      }
    },
    [hydrateSession]
  );

  return {
    preferredMethod,
    step,
    identifier,
    error,
    isStarting,
    isVerifying,
    isInCooldown: magic.isInCooldown,
    cooldownSeconds: magic.cooldownSeconds,
    start,
    resend,
    back,
    verifyOtp,
    consumeMagicToken,
    clearError,
  };
}

