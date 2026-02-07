import { useParams, useLocation, useNavigate } from 'react-router-dom';
import { useState, useEffect, useCallback } from 'react';
import { HiOutlineDocumentText } from 'react-icons/hi2';
import { useAppHeader } from '../components/layout/AppHeader';
import { Card, CardContent, CardHeader, CardTitle } from '../components/ui/Card';
import { Button } from '../components/ui/Button';
import { Spinner } from '../components/ui/Spinner';
import { ErrorState } from '../components/feedback/ErrorState';
import { CueContentMarkdown } from '../components/cues/CueContentMarkdown';
import { AudioPlayer } from '../components/recording/AudioPlayer';
import { TranscriptBadge } from '../components/history/TranscriptBadge';
import { recordingsApi } from '../services/recordings';
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

  const handleBack = useCallback(() => {
    navigate(ROUTES.HISTORY);
  }, [navigate]);

  // Recording can be passed via location state or fetched from history
  const [recording, setRecording] = useState<Recording | null>(
    location.state?.recording || null
  );
  const [processedFiles, setProcessedFiles] = useState<ProcessedFile[]>(
    location.state?.processedFiles || []
  );
  const [isLoading, setIsLoading] = useState(!location.state?.recording);
  const [error, setError] = useState<string | null>(null);

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
      }
    } catch (err) {
      console.error('Failed to refresh recording:', err);
    }
  }, [activeProfile, recording]);

  useEffect(() => {
    if (!recording && activeProfile) {
      fetchRecording();
    }
  }, [recording, activeProfile, fetchRecording]);

  // Transcription hook
  const {
    transcription,
    status: transcriptionStatus,
    isRequesting: isRequestingTranscription,
    requestTranscription,
  } = useTranscription({ 
    recording, 
    onRefresh: refreshRecording,
  });

  // ─────────────────────────────────────────────────────────────────────────
  // Get recording info
  // ─────────────────────────────────────────────────────────────────────────

  useAppHeader({ title: '', showBack: true, onBack: handleBack });
  
  // Get duration from file metadata
  const durationStr = recording?.file?.metadata?.duration;
  const durationMs = durationStr ? parseDuration(durationStr) : 0;
  
  // Find the audio URL from processed files
  const audioFile = processedFiles.find(
    (pf) => pf.fileId === recording?.fileId
  );
  const audioUrl = audioFile?.url || null;

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
  // Render
  // ─────────────────────────────────────────────────────────────────────────

  return (
    <div>
      <div className="container-page py-6 space-y-6">
        {/* Cue prompt (markdown) */}
        <Card>
          <CardContent className="py-6">
            <CueContentMarkdown
              title={recording.cue?.content?.title}
              details={recording.cue?.content?.details}
              className="text-body-md"
            />
          </CardContent>
        </Card>

        {/* Audio player */}
        {audioUrl && (
          <Card>
            <CardHeader>
              <CardTitle>Recording</CardTitle>
            </CardHeader>
            <CardContent>
              <AudioPlayer
                id={`recording-${recording.profileCueRecordingId}`}
                url={audioUrl}
                durationMs={durationMs}
              />
            </CardContent>
          </Card>
        )}

        {/* Transcription */}
        <Card>
          <CardHeader>
            <div className="flex items-center justify-between">
              <CardTitle>Transcript</CardTitle>
              {transcriptionStatus && transcriptionStatus !== 'none' && (
                <TranscriptBadge status={transcriptionStatus} />
              )}
            </div>
          </CardHeader>
          <CardContent>
            {transcription ? (
              <p className="text-body-md text-text-primary whitespace-pre-wrap leading-relaxed">
                {transcription}
              </p>
            ) : transcriptionStatus === 'processing' ? (
              <div className="flex items-center gap-3 py-4">
                <Spinner size="sm" />
                <p className="text-body-md text-text-secondary">
                  Transcription in progress...
                </p>
              </div>
            ) : (
              <div className="py-4">
                <p className="text-body-md text-text-secondary mb-4">
                  No transcript available. Get AI-powered transcription of your recording.
                </p>
                <Button
                  variant="primary"
                  onClick={requestTranscription}
                  isLoading={isRequestingTranscription}
                  leftIcon={<HiOutlineDocumentText className="w-5 h-5" />}
                >
                  Generate transcript
                </Button>
              </div>
            )}
          </CardContent>
        </Card>
      </div>
    </div>
  );
}

export default RecordingDetailPage;
