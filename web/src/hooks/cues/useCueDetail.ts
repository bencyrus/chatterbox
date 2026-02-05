import { useState, useEffect, useCallback } from 'react';
import { cuesApi } from '../../services/cues';
import { useProfile } from '../../contexts/ProfileContext';
import type { CueWithRecordingsResponse } from '../../types';
import { ApiError } from '../../services/api';

// ═══════════════════════════════════════════════════════════════════════════
// TYPES
// ═══════════════════════════════════════════════════════════════════════════

interface UseCueDetailParams {
  cueId: string | undefined;
}

interface UseCueDetailReturn {
  /** Cue detail data */
  data: CueWithRecordingsResponse | null;
  /** Whether data is loading */
  isLoading: boolean;
  /** Error message if load failed */
  error: string | null;
  /** Refresh data */
  refresh: () => Promise<void>;
}

// ═══════════════════════════════════════════════════════════════════════════
// HOOK
// ═══════════════════════════════════════════════════════════════════════════

export function useCueDetail({ cueId }: UseCueDetailParams): UseCueDetailReturn {
  const [data, setData] = useState<CueWithRecordingsResponse | null>(null);
  const [isLoading, setIsLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  
  const { activeProfile } = useProfile();

  // ─────────────────────────────────────────────────────────────────────────
  // Fetch cue detail
  // ─────────────────────────────────────────────────────────────────────────

  const fetchCueDetail = useCallback(async () => {
    if (!cueId) {
      setIsLoading(false);
      setError('No cue ID provided');
      return;
    }

    if (!activeProfile) {
      setIsLoading(false);
      return;
    }

    setIsLoading(true);
    setError(null);

    try {
      const response = await cuesApi.getCueForProfile({
        profileId: activeProfile.profileId,
        cueId: parseInt(cueId, 10),
      });
      setData(response);
    } catch (err) {
      const message =
        err instanceof ApiError
          ? err.message
          : 'Failed to load cue. Please try again.';
      setError(message);
      console.error('Failed to fetch cue detail:', err);
    } finally {
      setIsLoading(false);
    }
  }, [cueId, activeProfile]);

  // ─────────────────────────────────────────────────────────────────────────
  // Load on mount and cueId change
  // ─────────────────────────────────────────────────────────────────────────

  useEffect(() => {
    if (activeProfile) {
      fetchCueDetail();
    }
  }, [fetchCueDetail, activeProfile]);

  // ─────────────────────────────────────────────────────────────────────────
  // Return
  // ─────────────────────────────────────────────────────────────────────────

  return {
    data,
    isLoading,
    error,
    refresh: fetchCueDetail,
  };
}
