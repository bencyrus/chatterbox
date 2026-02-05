import { useState, useEffect, useCallback, useMemo } from 'react';
import { recordingsApi } from '../../services/recordings';
import { useProfile } from '../../contexts/ProfileContext';
import type { Recording } from '../../types';
import { ApiError } from '../../services/api';
import { getDateGroupKey } from '../../lib/date';

// ═══════════════════════════════════════════════════════════════════════════
// TYPES
// ═══════════════════════════════════════════════════════════════════════════

interface RecordingGroup {
  key: string;
  label: string;
  recordings: Recording[];
}

interface UseRecordingHistoryReturn {
  /** Grouped recordings by date */
  groups: RecordingGroup[];
  /** Flat list of all recordings */
  recordings: Recording[];
  /** Whether data is loading */
  isLoading: boolean;
  /** Whether more data is being loaded */
  isLoadingMore: boolean;
  /** Error message if any */
  error: string | null;
  /** Whether there are more recordings to load */
  hasMore: boolean;
  /** Refresh recordings */
  refresh: () => Promise<void>;
  /** Load more recordings */
  loadMore: () => Promise<void>;
}

// ═══════════════════════════════════════════════════════════════════════════
// HOOK
// ═══════════════════════════════════════════════════════════════════════════

export function useRecordingHistory(): UseRecordingHistoryReturn {
  const [recordings, setRecordings] = useState<Recording[]>([]);
  const [isLoading, setIsLoading] = useState(true);
  const [isLoadingMore, setIsLoadingMore] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [hasMore, setHasMore] = useState(false); // No pagination in current API
  
  const { activeProfile } = useProfile();

  // ─────────────────────────────────────────────────────────────────────────
  // Fetch recordings
  // ─────────────────────────────────────────────────────────────────────────

  const fetchRecordings = useCallback(async () => {
    if (!activeProfile) {
      setIsLoading(false);
      return;
    }

    setIsLoading(true);
    setError(null);

    try {
      const response = await recordingsApi.getProfileRecordingHistory(
        activeProfile.profileId
      );

      setRecordings(response.recordings || []);
      setHasMore(false); // API returns all recordings at once
    } catch (err) {
      const message =
        err instanceof ApiError
          ? err.message
          : 'Failed to load recording history.';
      setError(message);
    } finally {
      setIsLoading(false);
    }
  }, [activeProfile]);

  // ─────────────────────────────────────────────────────────────────────────
  // Refresh
  // ─────────────────────────────────────────────────────────────────────────

  const refresh = useCallback(async () => {
    await fetchRecordings();
  }, [fetchRecordings]);

  // ─────────────────────────────────────────────────────────────────────────
  // Load more (no-op for now since API returns all)
  // ─────────────────────────────────────────────────────────────────────────

  const loadMore = useCallback(async () => {
    // No pagination in current API
  }, []);

  // ─────────────────────────────────────────────────────────────────────────
  // Group recordings by date
  // ─────────────────────────────────────────────────────────────────────────

  const groups = useMemo(() => {
    const groupMap = new Map<string, Recording[]>();

    recordings.forEach((recording) => {
      const { key, label } = getDateGroupKey(recording.createdAt);
      
      if (!groupMap.has(key)) {
        groupMap.set(key, []);
      }
      groupMap.get(key)!.push(recording);
    });

    // Convert to array and sort by date (newest first)
    const groupArray: RecordingGroup[] = [];
    groupMap.forEach((recs, key) => {
      // Get label from first recording in group
      const { label } = getDateGroupKey(recs[0].createdAt);
      groupArray.push({
        key,
        label,
        recordings: recs,
      });
    });

    return groupArray;
  }, [recordings]);

  // ─────────────────────────────────────────────────────────────────────────
  // Load on mount and profile change
  // ─────────────────────────────────────────────────────────────────────────

  useEffect(() => {
    if (activeProfile) {
      fetchRecordings();
    }
  }, [activeProfile]); // Intentionally not including fetchRecordings to avoid loop

  // ─────────────────────────────────────────────────────────────────────────
  // Return
  // ─────────────────────────────────────────────────────────────────────────

  return {
    groups,
    recordings,
    isLoading,
    isLoadingMore,
    error,
    hasMore,
    refresh,
    loadMore,
  };
}
