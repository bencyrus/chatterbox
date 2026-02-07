import { useParams, useNavigate } from 'react-router-dom';
import { useCallback, useMemo } from 'react';
import { HiOutlineClock, HiOutlineCalendar } from 'react-icons/hi2';
import { PiWaveformLight } from 'react-icons/pi';
import { useAppHeader } from '../components/layout/AppHeader';
import { ROUTES } from '../lib/constants';
import { Spinner } from '../components/ui/Spinner';
import { Card, CardContent } from '../components/ui/Card';
import { CueContentMarkdown } from '../components/cues/CueContentMarkdown';
import { ErrorState } from '../components/feedback/ErrorState';
import { EmptyState } from '../components/feedback/EmptyState';
import { NewRecordingButton } from '../components/recording/NewRecordingButton';
import { useCueDetail } from '../hooks/cues/useCueDetail';
import { getDateGroupKey, formatDurationMs, parseDuration } from '../lib/date';
import type { CueRecording } from '../types';

// ═══════════════════════════════════════════════════════════════════════════
// CUE HISTORY PAGE
// ═══════════════════════════════════════════════════════════════════════════

function CueHistoryPage() {
  const { cueId } = useParams<{ cueId: string }>();
  const navigate = useNavigate();
  const { data, isLoading, error, refresh } = useCueDetail({ cueId });

  const handleNewRecording = useCallback(() => {
    if (cueId) {
      navigate(ROUTES.CUE_DETAIL.replace(':cueId', cueId));
    }
  }, [navigate, cueId]);

  const handleRecordingClick = useCallback((recordingId: number) => {
    navigate(ROUTES.RECORDING_DETAIL.replace(':recordingId', String(recordingId)));
  }, [navigate]);

  // Get cue data
  const cue = data?.cue;
  const content = cue?.content;
  const recordings = cue?.recordings || [];

  useAppHeader({ title: '' });

  // ─────────────────────────────────────────────────────────────────────────
  // Group recordings by date
  // ─────────────────────────────────────────────────────────────────────────

  const groupedRecordings = useMemo(() => {
    const groups = recordings.reduce((acc: Record<string, { label: string; recordings: CueRecording[] }>, rec: CueRecording) => {
      const { key, label } = getDateGroupKey(rec.createdAt);
      if (!acc[key]) {
        acc[key] = { label, recordings: [] };
      }
      acc[key].recordings.push(rec);
      return acc;
    }, {});
    return Object.values(groups);
  }, [recordings]);

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
          title="Couldn't load history"
          message={error || 'The cue could not be found.'}
          onRetry={refresh}
        />
      </div>
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Empty state
  // ─────────────────────────────────────────────────────────────────────────

  if (recordings.length === 0) {
    return (
      <div>
        <div className="container-page py-6 space-y-6">
          {/* Cue content card */}
          <Card>
            <CardContent className="py-6">
              <CueContentMarkdown
                title={content?.title}
                details={content?.details}
                className="text-body-md"
              />
            </CardContent>
          </Card>

          {/* Empty state */}
          <EmptyState
            icon={<PiWaveformLight className="w-12 h-12" />}
            title="No recordings yet"
            description="You haven't recorded anything for this topic yet. Start your first recording!"
          />

          {/* New recording button */}
          <div className="flex justify-center pt-4">
            <NewRecordingButton onClick={handleNewRecording} />
          </div>
        </div>
      </div>
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Render with recordings
  // ─────────────────────────────────────────────────────────────────────────

  return (
    <div>
      <div className="container-page py-6 space-y-6">
        {/* Cue content card */}
        <Card>
          <CardContent className="py-6">
            <CueContentMarkdown
              title={content?.title}
              details={content?.details}
              className="text-body-md"
            />
          </CardContent>
        </Card>

        {/* New recording button */}
        <div className="flex justify-end">
          <NewRecordingButton onClick={handleNewRecording} />
        </div>

        {/* Recording history */}
        <div className="space-y-6">
          <h2 className="text-heading-lg font-semibold text-text-primary">
            Recording History
          </h2>

          {groupedRecordings.map((group, groupIndex) => (
            <div key={groupIndex} className="space-y-3">
              {/* Group header with date badge + count */}
              <div className="flex items-center gap-2 px-1">
                <span className="inline-flex items-center gap-1.5 px-2.5 py-1.5 rounded-md bg-black/5 text-text-primary text-label-md">
                  <HiOutlineCalendar className="w-3.5 h-3.5" />
                  {group.label}
                </span>
                <span className="inline-flex items-center px-2.5 py-1.5 rounded-md bg-app-green text-text-primary text-label-md">
                  {group.recordings.length}
                </span>
              </div>

              {/* Recordings */}
              <div className="space-y-2">
                {group.recordings.map((rec) => {
                  const durationStr = rec.file?.metadata?.duration;
                  const durationMs = durationStr ? parseDuration(durationStr) : 0;
                  const timeStr = new Date(rec.createdAt).toLocaleString('en-US', {
                    hour: 'numeric',
                    minute: '2-digit',
                    hour12: true,
                  });

                  return (
                    <button
                      key={rec.profileCueRecordingId}
                      type="button"
                      onClick={() => handleRecordingClick(rec.profileCueRecordingId)}
                      className="w-full text-left bg-app-beige rounded-xl p-4 transition-colors hover:bg-app-beige-hover focus:outline-none focus-visible:ring-2 focus-visible:ring-app-green-strong focus-visible:ring-offset-1"
                    >
                      <div className="flex items-center justify-between">
                        {/* Time badge */}
                        <span className="inline-flex items-center gap-1.5 px-2 py-1 rounded-md bg-black/10 text-label-sm text-text-primary/80">
                          {timeStr}
                        </span>
                        
                        {/* Duration badge */}
                        <span className="inline-flex items-center gap-1.5 px-2 py-1 rounded-md bg-black/10 text-label-sm text-text-primary/80">
                          <HiOutlineClock className="w-3.5 h-3.5" />
                          {durationMs > 0 ? formatDurationMs(durationMs) : '--:--'}
                        </span>
                      </div>
                    </button>
                  );
                })}
              </div>
            </div>
          ))}
        </div>
      </div>
    </div>
  );
}

export default CueHistoryPage;
