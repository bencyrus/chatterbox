import { useParams, useNavigate } from 'react-router-dom';
import { useCallback } from 'react';
import { useAppHeader } from '../components/layout/AppHeader';
import { ROUTES } from '../lib/constants';
import { Spinner } from '../components/ui/Spinner';
import { Card, CardContent } from '../components/ui/Card';
import { CueContentMarkdown } from '../components/cues/CueContentMarkdown';
import { ErrorState } from '../components/feedback/ErrorState';
import { RecordingControls } from '../components/recording/RecordingControls';
import { useCueDetail } from '../hooks/cues/useCueDetail';
import type { Recording } from '../types';

// ═══════════════════════════════════════════════════════════════════════════
// CUE DETAIL PAGE
// ═══════════════════════════════════════════════════════════════════════════

function CueDetailPage() {
  const { cueId } = useParams<{ cueId: string }>();
  const navigate = useNavigate();
  const { data, isLoading, error, refresh } = useCueDetail({ cueId });

  const handleBack = useCallback(() => {
    navigate(ROUTES.CUES);
  }, [navigate]);

  // Get cue data
  const cue = data?.cue;
  const content = cue?.content;
  useAppHeader({ title: '', showBack: true, onBack: handleBack });

  // ─────────────────────────────────────────────────────────────────────────
  // Handle recording saved
  // ─────────────────────────────────────────────────────────────────────────

  const handleRecordingSaved = useCallback((recording: Recording) => {
    // Just log for now, stays on same page for another recording
    console.log('Recording saved:', recording.profileCueRecordingId);
  }, []);

  // ─────────────────────────────────────────────────────────────────────────
  // Loading state
  // ─────────────────────────────────────────────────────────────────────────

  if (isLoading) {
    return (
      <div>
        <div className="container-page flex items-center justify-center py-20">
          <Spinner size="lg" />
        </div>
      </div>
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Error state
  // ─────────────────────────────────────────────────────────────────────────

  if (error || !cue) {
    return (
      <div>
        <ErrorState
          title="Couldn't load cue"
          message={error || 'The cue could not be found.'}
          onRetry={refresh}
        />
      </div>
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Render
  // ─────────────────────────────────────────────────────────────────────────

  return (
    <div>
      <div className="container-page py-6 space-y-6">
        {/* Primary prompt (markdown) */}
        <Card>
          <CardContent className="py-8">
            <CueContentMarkdown
              title={content?.title}
              details={content?.details}
              className="text-body-lg"
            />
          </CardContent>
        </Card>

        {/* Recording controls */}
        <RecordingControls
          cueId={cue.cueId}
          onRecordingSaved={handleRecordingSaved}
        />
      </div>
    </div>
  );
}

export default CueDetailPage;
