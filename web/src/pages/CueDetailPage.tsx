import { useParams, useNavigate } from 'react-router-dom';
import { useCallback, useMemo } from 'react';
import { HiOutlineChartBar } from 'react-icons/hi2';
import { useAppHeader } from '../components/layout/AppHeader';
import { ROUTES } from '../lib/constants';
import { Spinner } from '../components/ui/Spinner';
import { Card, CardContent } from '../components/ui/Card';
import { CueContentMarkdown } from '../components/cues/CueContentMarkdown';
import { ErrorState } from '../components/feedback/ErrorState';
import { RecordingControls } from '../components/recording/RecordingControls';
import { useCueDetail } from '../hooks/cues/useCueDetail';

// ═══════════════════════════════════════════════════════════════════════════
// CUE DETAIL PAGE
// ═══════════════════════════════════════════════════════════════════════════

function CueDetailPage() {
  const { cueId } = useParams<{ cueId: string }>();
  const navigate = useNavigate();
  const { data, isLoading, error, refresh } = useCueDetail({ cueId });

  // Get cue data
  const cue = data?.cue;
  const content = cue?.content;
  const recordings = cue?.recordings || [];
  const recordingCount = recordings.length;

  // ─────────────────────────────────────────────────────────────────────────
  // Handle recording saved
  // ─────────────────────────────────────────────────────────────────────────

  const handleRecordingSaved = useCallback(() => {
    // Refresh data to update recording count
    refresh();
  }, [refresh]);

  // ─────────────────────────────────────────────────────────────────────────
  // Handle view history
  // ─────────────────────────────────────────────────────────────────────────

  const handleViewHistory = useCallback(() => {
    if (cueId) {
      navigate(ROUTES.CUE_HISTORY.replace(':cueId', cueId));
    }
  }, [navigate, cueId]);

  // ─────────────────────────────────────────────────────────────────────────
  // Recording count display for header
  // ─────────────────────────────────────────────────────────────────────────

  const recordingCountDisplay = useMemo(() => {
    return (
      <button
        type="button"
        onClick={handleViewHistory}
        className="inline-flex items-center gap-3 px-4 py-2.5 rounded-lg bg-black/5 hover:bg-black/10 text-text-primary transition-all focus:outline-none cursor-pointer focus-visible:ring-2 focus-visible:ring-app-green-strong focus-visible:ring-offset-1"
      >
        <div className="flex items-center gap-1.5">
          <HiOutlineChartBar className="w-4 h-4" />
          <span className="text-label-md">
            Recordings: <span className="font-semibold">{recordingCount}</span>
          </span>
        </div>
        <span className="text-label-md font-medium">
          View →
        </span>
      </button>
    );
  }, [recordingCount, handleViewHistory]);

  useAppHeader({ 
    title: '',
    rightAction: recordingCountDisplay,
  });

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
