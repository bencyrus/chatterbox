import { useParams, useLocation, useNavigate } from 'react-router-dom';
import { useState, useEffect, useCallback, useMemo } from 'react';
import { HiOutlineDocumentText, HiOutlineChartBar, HiOutlineCalendar } from 'react-icons/hi2';
import { useAppHeader } from '../components/layout/AppHeader';
import { Card, CardContent } from '../components/ui/Card';
import { Button } from '../components/ui/Button';
import { Spinner } from '../components/ui/Spinner';
import { ErrorState } from '../components/feedback/ErrorState';
import { Modal } from '../components/ui/Modal';
import { CueContentMarkdown } from '../components/cues/CueContentMarkdown';
import { AudioPlayer } from '../components/recording/AudioPlayer';
import { NewRecordingButton } from '../components/recording/NewRecordingButton';
import { TranscriptBadge } from '../components/history/TranscriptBadge';
import { recordingsApi } from '../services/recordings';
import { cuesApi } from '../services/cues';
import { useTranscription } from '../hooks/history/useTranscription';
import { useProfile } from '../contexts/ProfileContext';
import { ApiError } from '../services/api';
import { parseDuration } from '../lib/date';
import { ROUTES } from '../lib/constants';
import type { Recording, ProcessedFile } from '../types';

// ═══════════════════════════════════════════════════════════════════════════
// RECORDING DETAIL PAGE
// ═══════════════════════════════════════════════════════════════════════════

function RecordingDetailPage() {
  const { recordingId } = useParams<{ recordingId: string }>();
  const location = useLocation();
  const navigate = useNavigate();
  const { activeProfile } = useProfile();

  // Recording can be passed via location state or fetched from history
  const [recording, setRecording] = useState<Recording | null>(
    location.state?.recording || null
  );
  const [processedFiles, setProcessedFiles] = useState<ProcessedFile[]>(
    location.state?.processedFiles || []
  );
  const [isLoading, setIsLoading] = useState(!location.state?.recording);
  const [error, setError] = useState<string | null>(null);
  const [showTranscriptModal, setShowTranscriptModal] = useState(false);
  const [recordingCount, setRecordingCount] = useState<number>(0);

  // ─────────────────────────────────────────────────────────────────────────
  // Fetch recording from history if not passed via state
  // ─────────────────────────────────────────────────────────────────────────

  const fetchRecording = useCallback(async () => {
    if (!recordingId || !activeProfile) {
      setError('No recording ID provided');
      setIsLoading(false);
      return;
    }

    setIsLoading(true);
    setError(null);

    try {
      const response = await recordingsApi.getProfileRecordingHistory(
        activeProfile.profileId
      );

      // Find the recording by ID
      const targetId = parseInt(recordingId, 10);
      const foundRecording = response.recordings.find(
        (r) => r.profileCueRecordingId === targetId
      );

      if (foundRecording) {
        setRecording(foundRecording);
        setProcessedFiles(response.processedFiles || []);
        
        // Fetch recording count for this cue
        try {
          const cueResponse = await cuesApi.getCueForProfile({
            profileId: activeProfile.profileId,
            cueId: foundRecording.cueId,
          });
          setRecordingCount(cueResponse.cue?.recordings?.length || 0);
        } catch (err) {
          console.error('Failed to fetch recording count:', err);
        }
      } else {
        setError('Recording not found');
      }
    } catch (err) {
      const message =
        err instanceof ApiError
          ? err.message
          : 'Failed to load recording.';
      setError(message);
    } finally {
      setIsLoading(false);
    }
  }, [recordingId, activeProfile]);

  // Refresh function for transcription polling
  const refreshRecording = useCallback(async () => {
    if (!activeProfile || !recording) return;
    
    try {
      const response = await recordingsApi.getProfileRecordingHistory(
        activeProfile.profileId
      );
      
      const foundRecording = response.recordings.find(
        (r) => r.profileCueRecordingId === recording.profileCueRecordingId
      );
      
      if (foundRecording) {
        setRecording(foundRecording);
        setProcessedFiles(response.processedFiles || []);
        
        // Also update recording count
        try {
          const cueResponse = await cuesApi.getCueForProfile({
            profileId: activeProfile.profileId,
            cueId: foundRecording.cueId,
          });
          setRecordingCount(cueResponse.cue?.recordings?.length || 0);
        } catch (err) {
          console.error('Failed to fetch recording count:', err);
        }
      }
    } catch (err) {
      console.error('Failed to refresh recording:', err);
    }
  }, [activeProfile, recording]);

  useEffect(() => {
    if (!recording && activeProfile) {
      fetchRecording();
    } else if (recording && activeProfile && recordingCount === 0) {
      // Fetch recording count if we have a recording but no count yet
      const fetchCount = async () => {
        try {
          const cueResponse = await cuesApi.getCueForProfile({
            profileId: activeProfile.profileId,
            cueId: recording.cueId,
          });
          setRecordingCount(cueResponse.cue?.recordings?.length || 0);
        } catch (err) {
          console.error('Failed to fetch recording count:', err);
        }
      };
      fetchCount();
    }
  }, [recording, activeProfile, fetchRecording, recordingCount]);

  // Transcription hook for the recording
  const {
    transcription,
    status: transcriptionStatus,
    isRequesting: isRequestingTranscription,
    requestTranscription,
  } = useTranscription({ 
    recording, 
    onRefresh: refreshRecording,
  });

  // Navigation handlers
  const handleRecordAgain = useCallback(() => {
    if (recording) {
      navigate(ROUTES.CUE_DETAIL.replace(':cueId', String(recording.cueId)));
    }
  }, [navigate, recording]);

  const handleViewAllRecordings = useCallback(() => {
    if (recording) {
      navigate(ROUTES.CUE_HISTORY.replace(':cueId', String(recording.cueId)));
    }
  }, [navigate, recording]);

  // ─────────────────────────────────────────────────────────────────────────
  // Recording count display for header
  // ─────────────────────────────────────────────────────────────────────────

  const recordingCountDisplay = useMemo(() => {
    if (!recording || recordingCount === 0) return null;
    
    return (
      <button
        type="button"
        onClick={handleViewAllRecordings}
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
  }, [recordingCount, recording, handleViewAllRecordings]);

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

  if (error || !recording) {
    return (
      <div>
        <ErrorState
          title="Couldn't load recording"
          message={error || 'The recording could not be found.'}
          onRetry={fetchRecording}
        />
      </div>
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Get audio file info
  // ─────────────────────────────────────────────────────────────────────────

  const audioFile = processedFiles.find(
    (pf) => pf.fileId === recording.fileId
  );
  const audioUrl = audioFile?.url || null;
  const durationStr = recording.file?.metadata?.duration;
  const durationMs = durationStr ? parseDuration(durationStr) : 0;

  // ─────────────────────────────────────────────────────────────────────────
  // Render
  // ─────────────────────────────────────────────────────────────────────────

  return (
    <div>
      <div className="container-page py-6 space-y-6">
        {/* Cue content card */}
        <Card>
          <CardContent className="py-6">
            <CueContentMarkdown
              title={recording.cue?.content?.title}
              details={recording.cue?.content?.details}
              className="text-body-md"
            />
          </CardContent>
        </Card>

        {/* New Recording button */}
        <div className="flex justify-end">
          <NewRecordingButton onClick={handleRecordAgain} />
        </div>

        <div className="space-y-3">
          {/* Recording date badge */}
          <div className="px-1">
            <span className="inline-flex items-center gap-1.5 px-2.5 py-1.5 rounded-md bg-black/5 text-text-primary text-label-md">
              <HiOutlineCalendar className="w-3.5 h-3.5" />
              {new Date(recording.createdAt).toLocaleString('en-US', {
                weekday: 'short',
                month: 'short',
                day: 'numeric',
                year: 'numeric',
              })}
            </span>
          </div>

          {/* Recording card */}
          <Card className="bg-app-beige">
            <CardContent className="space-y-4">
              {/* Recording time */}
              <p className="text-body-sm text-text-primary">
                {new Date(recording.createdAt).toLocaleString('en-US', {
                  hour: 'numeric',
                  minute: '2-digit',
                  hour12: true,
                })}
              </p>

            {/* Audio player with background */}
            {audioUrl && (
              <div className="bg-app-beige-dark rounded-lg p-4 py-6">
                <AudioPlayer
                  id={`recording-${recording.profileCueRecordingId}`}
                  url={audioUrl}
                  durationMs={durationMs}
                />
              </div>
            )}

            {/* View Report button */}
            <Button
              variant="primary"
              size="lg"
              onClick={() => setShowTranscriptModal(true)}
              className="!w-full !bg-app-green-strong !text-white hover:!bg-app-green-deep"
              leftIcon={<HiOutlineDocumentText className="w-5 h-5" />}
            >
              View Report
            </Button>
          </CardContent>
        </Card>
        </div>
      </div>

      {/* Transcript Modal */}
      <Modal
        isOpen={showTranscriptModal}
        onClose={() => setShowTranscriptModal(false)}
        title={recording.cue?.content?.title || 'Recording Report'}
      >
        <div className="space-y-4">
          {/* Status badge */}
          {transcriptionStatus && transcriptionStatus !== 'none' && (
            <div className="flex justify-end">
              <TranscriptBadge status={transcriptionStatus} />
            </div>
          )}

          {/* Transcript content */}
          {transcription ? (
            <div className="py-2">
              <h3 className="text-heading-sm font-semibold text-text-primary mb-3">
                Transcript
              </h3>
              <p className="text-body-md text-text-primary whitespace-pre-wrap leading-relaxed">
                {transcription}
              </p>
            </div>
          ) : transcriptionStatus === 'processing' ? (
            <div className="flex flex-col items-center gap-3 py-8">
              <Spinner size="lg" />
              <p className="text-body-md text-text-secondary">
                Transcription in progress...
              </p>
              <p className="text-body-sm text-text-tertiary">
                This may take a few moments
              </p>
            </div>
          ) : (
            <div className="py-6 text-center">
              <p className="text-body-md text-text-secondary mb-6">
                No transcript available yet. Generate an AI-powered transcription of your recording.
              </p>
              <Button
                variant="primary"
                size="lg"
                onClick={requestTranscription}
                isLoading={isRequestingTranscription}
                leftIcon={<HiOutlineDocumentText className="w-5 h-5" />}
                className="!bg-app-green-strong !text-white hover:!bg-app-green-deep"
              >
                Generate Transcript
              </Button>
            </div>
          )}
        </div>
      </Modal>
    </div>
  );
}

export default RecordingDetailPage;
