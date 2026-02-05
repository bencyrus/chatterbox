import { useCallback } from 'react';
import { HiOutlineArrowPath } from 'react-icons/hi2';
import { PageHeader } from '../components/layout/PageHeader';
import { Button } from '../components/ui/Button';
import { CueList } from '../components/cues/CueList';
import { useCues } from '../hooks/cues/useCues';
import { useProfile } from '../contexts/ProfileContext';
import { LANGUAGE_NAMES } from '../lib/constants';

// ═══════════════════════════════════════════════════════════════════════════
// CUES PAGE
// ═══════════════════════════════════════════════════════════════════════════

function CuesPage() {
  const { cues, isLoading, isShuffling, error, refresh, shuffle } = useCues();
  const { activeProfile } = useProfile();

  // Get profile language name for subtitle
  const languageName = activeProfile?.languageCode
    ? LANGUAGE_NAMES[activeProfile.languageCode] || activeProfile.languageCode
    : '';

  // ─────────────────────────────────────────────────────────────────────────
  // Handlers
  // ─────────────────────────────────────────────────────────────────────────

  const handleShuffle = useCallback(() => {
    shuffle();
  }, [shuffle]);

  // ─────────────────────────────────────────────────────────────────────────
  // Shuffle button
  // ─────────────────────────────────────────────────────────────────────────

  const shuffleButton = (
    <Button
      variant="ghost"
      size="sm"
      onClick={handleShuffle}
      isLoading={isShuffling}
      disabled={isLoading}
      aria-label="Shuffle cues"
      className="!p-2"
    >
      {!isShuffling && (
        <HiOutlineArrowPath className="w-5 h-5" />
      )}
    </Button>
  );

  // ─────────────────────────────────────────────────────────────────────────
  // Render
  // ─────────────────────────────────────────────────────────────────────────

  return (
    <div>
      <PageHeader
        title="Practice"
        subtitle={languageName}
        rightAction={shuffleButton}
      />
      
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
