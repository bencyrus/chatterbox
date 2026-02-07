import { useCallback, useMemo } from 'react';
import { HiOutlineArrowPath } from 'react-icons/hi2';
import { useAppHeader } from '../components/layout/AppHeader';
import { Button } from '../components/ui/Button';
import { CueList } from '../components/cues/CueList';
import { useCues } from '../hooks/cues/useCues';

// ═══════════════════════════════════════════════════════════════════════════
// CUES PAGE
// ═══════════════════════════════════════════════════════════════════════════

function CuesPage() {
  const { cues, isLoading, isShuffling, error, refresh, shuffle } = useCues();

  // ─────────────────────────────────────────────────────────────────────────
  // Handlers
  // ─────────────────────────────────────────────────────────────────────────

  const handleShuffle = useCallback(() => {
    shuffle();
  }, [shuffle]);

  // ─────────────────────────────────────────────────────────────────────────
  // Shuffle button
  // ─────────────────────────────────────────────────────────────────────────

  const shuffleButton = useMemo(
    () => (
      <Button
        variant="primary"
        size="lg"
        onClick={handleShuffle}
        isLoading={isShuffling}
        disabled={isLoading}
        className="rounded-full !bg-neutral-900 !text-white hover:!bg-black active:!bg-black"
        leftIcon={!isShuffling ? <HiOutlineArrowPath className="w-5 h-5" /> : undefined}
      >
        Shuffle
      </Button>
    ),
    [handleShuffle, isShuffling, isLoading]
  );

  // ─────────────────────────────────────────────────────────────────────────
  useAppHeader({
    title: 'Subjects',
    showBack: false,
    rightAction: shuffleButton,
  });

  // Render
  // ─────────────────────────────────────────────────────────────────────────

  return (
    <div>
      <div className="container-page py-4">
        <CueList
          cues={cues}
          isLoading={isLoading}
          error={error}
          onRetry={refresh}
          onEmptyAction={shuffle}
        />
      </div>
    </div>
  );
}

export default CuesPage;
