import { useState, useEffect, useCallback } from 'react';
import { cuesApi } from '../../services/cues';
import { useProfile } from '../../contexts/ProfileContext';
import { useToast } from '../../contexts/ToastContext';
import type { Cue } from '../../types';
import { ApiError } from '../../services/api';

// ═══════════════════════════════════════════════════════════════════════════
// TYPES
// ═══════════════════════════════════════════════════════════════════════════

interface UseCuesReturn {
  /** List of cues */
  cues: Cue[];
  /** Whether cues are loading */
  isLoading: boolean;
  /** Whether shuffle is in progress */
  isShuffling: boolean;
  /** Error message if load failed */
  error: string | null;
  /** Refresh cues */
  refresh: () => Promise<void>;
  /** Shuffle cues */
  shuffle: () => Promise<void>;
}

// ═══════════════════════════════════════════════════════════════════════════
// HOOK
// ═══════════════════════════════════════════════════════════════════════════

export function useCues(): UseCuesReturn {
  const [cues, setCues] = useState<Cue[]>([]);
  const [isLoading, setIsLoading] = useState(true);
  const [isShuffling, setIsShuffling] = useState(false);
  const [error, setError] = useState<string | null>(null);
  
  const { activeProfile } = useProfile();
  const { showToast } = useToast();

  // ─────────────────────────────────────────────────────────────────────────
  // Fetch cues
  // ─────────────────────────────────────────────────────────────────────────

  const fetchCues = useCallback(async () => {
    if (!activeProfile) {
      setIsLoading(false);
      return;
    }

    setIsLoading(true);
    setError(null);

    try {
      const fetchedCues = await cuesApi.getCues({
        profileId: activeProfile.profileId,
      });
      setCues(fetchedCues);
    } catch (err) {
      const message =
        err instanceof ApiError
          ? err.message
          : 'Failed to load cues. Please try again.';
      setError(message);
      console.error('Failed to fetch cues:', err);
    } finally {
      setIsLoading(false);
    }
  }, [activeProfile]);

  // ─────────────────────────────────────────────────────────────────────────
  // Shuffle cues
  // ─────────────────────────────────────────────────────────────────────────

  const shuffle = useCallback(async () => {
    if (!activeProfile) return;

    setIsShuffling(true);

    try {
      const shuffledCues = await cuesApi.shuffleCues({
        profileId: activeProfile.profileId,
      });
      setCues(shuffledCues);
    } catch (err) {
      const message =
        err instanceof ApiError
          ? err.message
          : 'Failed to shuffle cues. Please try again.';
      showToast(message, 'error');
      console.error('Failed to shuffle cues:', err);
    } finally {
      setIsShuffling(false);
    }
  }, [activeProfile, showToast]);

  // ─────────────────────────────────────────────────────────────────────────
  // Load on mount and profile change
  // ─────────────────────────────────────────────────────────────────────────

  useEffect(() => {
    if (activeProfile) {
      fetchCues();
    }
  }, [activeProfile, fetchCues]);

  // ─────────────────────────────────────────────────────────────────────────
  // Return
  // ─────────────────────────────────────────────────────────────────────────

  return {
    cues,
    isLoading,
    isShuffling,
    error,
    refresh: fetchCues,
    shuffle,
  };
}
