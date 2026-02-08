import { useState, useEffect, useCallback } from 'react';
import { authApi } from '../../services/auth';
import {
  setCooldownEnd,
  clearCooldown,
  getRemainingCooldown,
} from '../../lib/storage';
import { MAGIC_LINK_COOLDOWN_MS } from '../../lib/constants';
import { ApiError } from '../../services/api';

// ═══════════════════════════════════════════════════════════════════════════
// TYPES
// ═══════════════════════════════════════════════════════════════════════════

interface UseMagicLinkReturn {
  /** Request a magic link for the given email */
  requestLink: (email: string) => Promise<{ ok: true } | { ok: false; error: string }>;
  /** Whether a request is in progress */
  isLoading: boolean;
  /** Error message if request failed */
  error: string | null;
  /** Whether the user is in cooldown period */
  isInCooldown: boolean;
  /** Remaining cooldown time in seconds */
  cooldownSeconds: number;
  /** Clear the error */
  clearError: () => void;
}

// ═══════════════════════════════════════════════════════════════════════════
// HOOK
// ═══════════════════════════════════════════════════════════════════════════

export function useMagicLink(): UseMagicLinkReturn {
  const [isLoading, setIsLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [cooldownSeconds, setCooldownSeconds] = useState(0);

  // ─────────────────────────────────────────────────────────────────────────
  // Update cooldown timer
  // ─────────────────────────────────────────────────────────────────────────

  useEffect(() => {
    // Check initial cooldown
    const remaining = getRemainingCooldown();
    if (remaining > 0) {
      setCooldownSeconds(Math.ceil(remaining / 1000));
    }

    // Update cooldown every second
    const interval = setInterval(() => {
      const remaining = getRemainingCooldown();
      if (remaining > 0) {
        setCooldownSeconds(Math.ceil(remaining / 1000));
      } else {
        setCooldownSeconds(0);
        clearCooldown();
      }
    }, 1000);

    return () => clearInterval(interval);
  }, []);

  // ─────────────────────────────────────────────────────────────────────────
  // Request magic link
  // ─────────────────────────────────────────────────────────────────────────

  const requestLink = useCallback(async (email: string) => {
    // Check cooldown
    if (getRemainingCooldown() > 0) {
      const msg = 'Please wait before requesting another link';
      setError(msg);
      return { ok: false as const, error: msg };
    }

    setIsLoading(true);
    setError(null);

    try {
      await authApi.requestMagicLink({ identifier: email });
      
      // Set cooldown
      const cooldownEnd = Date.now() + MAGIC_LINK_COOLDOWN_MS;
      setCooldownEnd(cooldownEnd);
      setCooldownSeconds(Math.ceil(MAGIC_LINK_COOLDOWN_MS / 1000));
      return { ok: true as const };
    } catch (err) {
      if (err instanceof ApiError) {
        setError(err.message);
        return { ok: false as const, error: err.message };
      } else {
        const msg = 'Failed to send magic link. Please try again.';
        setError(msg);
        return { ok: false as const, error: msg };
      }
    } finally {
      setIsLoading(false);
    }
  }, []);

  // ─────────────────────────────────────────────────────────────────────────
  // Clear error
  // ─────────────────────────────────────────────────────────────────────────

  const clearError = useCallback(() => {
    setError(null);
  }, []);

  // ─────────────────────────────────────────────────────────────────────────
  // Return
  // ─────────────────────────────────────────────────────────────────────────

  return {
    requestLink,
    isLoading,
    error,
    isInCooldown: cooldownSeconds > 0,
    cooldownSeconds,
    clearError,
  };
}
