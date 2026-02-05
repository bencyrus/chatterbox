import { useParams } from 'react-router-dom';
import { useCallback } from 'react';
import { PageHeader } from '../components/layout/PageHeader';
import { Spinner } from '../components/ui/Spinner';
import { Card, CardContent } from '../components/ui/Card';
import { ErrorState } from '../components/feedback/ErrorState';
import { RecordingControls } from '../components/recording/RecordingControls';
import { useCueDetail } from '../hooks/cues/useCueDetail';
import { useProfile } from '../contexts/ProfileContext';
import { LANGUAGE_NAMES } from '../lib/constants';
import type { Recording } from '../types';

// ═══════════════════════════════════════════════════════════════════════════
// CUE DETAIL PAGE
// ═══════════════════════════════════════════════════════════════════════════

function CueDetailPage() {
  const { cueId } = useParams<{ cueId: string }>();
  const { data, isLoading, error, refresh } = useCueDetail({ cueId });
  const { activeProfile } = useProfile();

  // Get cue data
  const cue = data?.cue;
  const content = cue?.content;
  const languageName = content?.languageCode
    ? LANGUAGE_NAMES[content.languageCode] || content.languageCode
    : 'Practice';

  // ─────────────────────────────────────────────────────────────────────────
  // Handle recording saved
  // ─────────────────────────────────────────────────────────────────────────

  const handleRecordingSaved = useCallback((recording: Recording) => {
    // Optionally navigate to recording detail or stay on page
    // For now, just stay and allow more recordings
    console.log('Recording saved:', recording.profileCueRecordingId);
  }, []);

  // ─────────────────────────────────────────────────────────────────────────
  // Loading state
  // ─────────────────────────────────────────────────────────────────────────

  if (isLoading) {
    return (
      <div>
        <PageHeader title="Loading..." showBack />
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
        <PageHeader title="Error" showBack />
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
    <div className="flex flex-col min-h-screen">
      <PageHeader title={languageName} showBack />

      {/* Cue content */}
      <div className="flex-1 container-page py-8">
        <div className="space-y-8">
          {/* Primary prompt */}
          <Card>
            <CardContent className="py-8">
              <p className="text-heading-lg font-semibold text-text-primary leading-relaxed text-center">
                {content?.title || 'No prompt available'}
              </p>
              {content?.details && (
                <p className="text-body-md text-text-secondary mt-4 text-center">
                  {content.details}
                </p>
              )}
            </CardContent>
          </Card>
        </div>
      </div>

      {/* Recording controls */}
      <div className="sticky bottom-20 pb-4">
        <div className="container-page">
          <Card className="bg-surface-secondary border-border-secondary">
            <CardContent>
              <RecordingControls
                cueId={cue.cueId}
                onRecordingSaved={handleRecordingSaved}
              />
            </CardContent>
          </Card>
        </div>
      </div>
    </div>
  );
}

export default CueDetailPage;
