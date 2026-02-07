import { useEffect, useRef } from 'react';
import { PiWaveformLight } from 'react-icons/pi';
import { useAppHeader } from '../components/layout/AppHeader';
import { RecordingGroup } from '../components/history/RecordingGroup';
import { RecordingCardSkeleton } from '../components/history/RecordingCardSkeleton';
import { EmptyState } from '../components/feedback/EmptyState';
import { ErrorState } from '../components/feedback/ErrorState';
import { Spinner } from '../components/ui/Spinner';
import { useRecordingHistory } from '../hooks/history/useRecordingHistory';

// ═══════════════════════════════════════════════════════════════════════════
// HISTORY PAGE
// ═══════════════════════════════════════════════════════════════════════════

function HistoryPage() {
  const {
    groups,
    isLoading,
    isLoadingMore,
    error,
    hasMore,
    refresh,
    loadMore,
  } = useRecordingHistory();
  
  const loadMoreRef = useRef<HTMLDivElement>(null);
  useAppHeader({ title: 'Recording History', showBack: false });

  // ─────────────────────────────────────────────────────────────────────────
  // Infinite scroll
  // ─────────────────────────────────────────────────────────────────────────

  useEffect(() => {
    if (!loadMoreRef.current || isLoading || isLoadingMore || !hasMore) {
      return;
    }

    const observer = new IntersectionObserver(
      (entries) => {
        if (entries[0].isIntersecting && hasMore && !isLoadingMore) {
          loadMore();
        }
      },
      { threshold: 0.1 }
    );

    observer.observe(loadMoreRef.current);

    return () => observer.disconnect();
  }, [hasMore, isLoading, isLoadingMore, loadMore]);

  // ─────────────────────────────────────────────────────────────────────────
  // Loading state
  // ─────────────────────────────────────────────────────────────────────────

  if (isLoading) {
    return (
      <div>
        <div className="container-page py-4 space-y-6">
          {/* Skeleton groups */}
          <div className="space-y-3">
            <div className="h-4 bg-surface-tertiary rounded w-16" />
            {Array.from({ length: 3 }).map((_, i) => (
              <RecordingCardSkeleton key={i} />
            ))}
          </div>
          <div className="space-y-3">
            <div className="h-4 bg-surface-tertiary rounded w-24" />
            {Array.from({ length: 2 }).map((_, i) => (
              <RecordingCardSkeleton key={i} />
            ))}
          </div>
        </div>
      </div>
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Error state
  // ─────────────────────────────────────────────────────────────────────────

  if (error) {
    return (
      <div>
        <ErrorState
          title="Couldn't load history"
          message={error}
          onRetry={refresh}
        />
      </div>
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Empty state
  // ─────────────────────────────────────────────────────────────────────────

  if (groups.length === 0) {
    return (
      <div>
        <EmptyState
          icon={<PiWaveformLight className="w-12 h-12" />}
          title="No recordings yet"
          description="Your practice recordings will appear here. Start by recording yourself on the Practice tab."
        />
      </div>
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Render
  // ─────────────────────────────────────────────────────────────────────────

  return (
    <div>
      <div className="container-page py-4 space-y-6">
        {/* Recording groups */}
        {groups.map((group, index) => (
          <RecordingGroup
            key={`${group.key}-${index}`}
            label={group.label}
            recordings={group.recordings}
          />
        ))}

        {/* Load more trigger */}
        {hasMore && (
          <div ref={loadMoreRef} className="flex justify-center py-4">
            {isLoadingMore && <Spinner size="md" />}
          </div>
        )}
      </div>
    </div>
  );
}

export default HistoryPage;
