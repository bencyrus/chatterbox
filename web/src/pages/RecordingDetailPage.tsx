import { useParams, useLocation, useNavigate } from 'react-router-dom';
import { useState, useEffect, useCallback } from 'react';
import { HiOutlineDocumentText, HiOutlineMicrophone, HiOutlineCalendar } from 'react-icons/hi2';
import { useAppHeader } from '../components/layout/AppHeader';
import { Card, CardContent } from '../components/ui/Card';
import { Button } from '../components/ui/Button';
import { Spinner } from '../components/ui/Spinner';
import { ErrorState } from '../components/feedback/ErrorState';
import { Modal } from '../components/ui/Modal';
import { CueContentMarkdown } from '../components/cues/CueContentMarkdown';
import { AudioPlayer } from '../components/recording/AudioPlayer';
import { RecordingControls } from '../components/recording/RecordingControls';
import { TranscriptBadge } from '../components/history/TranscriptBadge';
import { recordingsApi } from '../services/recordings';
import { cuesApi } from '../services/cues';
import { useTranscription } from '../hooks/history/useTranscription';
import { useProfile } from '../contexts/ProfileContext';
import { ApiError } from '../services/api';
import { parseDuration, getDateGroupKey } from '../lib/date';
import { ROUTES } from '../lib/constants';
import type { Recording, ProcessedFile, CueRecording, CueWithRecordingsResponse } from '../types';

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
  const [cueData, setCueData] = useState<CueWithRecordingsResponse | null>(null);
  const [processedFiles, setProcessedFiles] = useState<ProcessedFile[]>(
    location.state?.processedFiles || []
  );
  const [isLoading, setIsLoading] = useState(!location.state?.recording);
  const [error, setError] = useState<string | null>(null);
  const [showTranscriptModal, setShowTranscriptModal] = useState(false);
  const [selectedRecordingId, setSelectedRecordingId] = useState<number | null>(
    recordingId ? parseInt(recordingId, 10) : null
  );
  const [isRecordingMode, setIsRecordingMode] = useState(false);

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
        
        // Fetch the cue with all its recordings
        const cueResponse = await cuesApi.getCueForProfile({
          profileId: activeProfile.profileId,
          cueId: foundRecording.cueId,
        });
        setCueData(cueResponse);
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

  // Refresh function for transcription polling and after new recording
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
        
        // Also refresh cue data
        const cueResponse = await cuesApi.getCueForProfile({
          profileId: activeProfile.profileId,
          cueId: foundRecording.cueId,
        });
        setCueData(cueResponse);
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

  // Transcription hook for selected recording
  const selectedCueRecording = cueData?.cue?.recordings?.find(
    (r) => r.profileCueRecordingId === selectedRecordingId
  );

  // Convert CueRecording to Recording for the transcription hook
  const selectedRecording: Recording | null = selectedCueRecording && cueData?.cue ? {
    ...selectedCueRecording,
    cue: cueData.cue,
  } : recording;

  const {
    transcription,
    status: transcriptionStatus,
    isRequesting: isRequestingTranscription,
    requestTranscription,
  } = useTranscription({ 
    recording: selectedRecording, 
    onRefresh: refreshRecording,
  });

  // Handle new recording saved
  const handleRecordingSaved = useCallback(() => {
    setIsRecordingMode(false);
    refreshRecording();
  }, [refreshRecording]);

  // ─────────────────────────────────────────────────────────────────────────
  // Get recording info
  // ─────────────────────────────────────────────────────────────────────────

  useAppHeader({ title: '', showBack: true, onBack: handleBack });

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

  // Group recordings by date
  const cueRecordings = cueData?.cue?.recordings || [];
  const groupedRecordings = cueRecordings.reduce((acc: Record<string, { label: string; recordings: CueRecording[] }>, rec: CueRecording) => {
    const { key, label } = getDateGroupKey(rec.createdAt);
    if (!acc[key]) {
      acc[key] = { label, recordings: [] };
    }
    acc[key].recordings.push(rec);
    return acc;
  }, {});
  const groups = Object.values(groupedRecordings);

  return (
    <div>
      <div className="container-page py-6 space-y-6">
        {/* Cue content card */}
        <Card>
          <CardContent className="py-6">
            <CueContentMarkdown
              title={recording.cue?.content?.title || cueData?.cue?.content?.title}
              details={recording.cue?.content?.details || cueData?.cue?.content?.details}
              className="text-body-md"
            />
          </CardContent>
        </Card>

        {/* Recording mode */}
        {isRecordingMode ? (
          <RecordingControls
            cueId={recording.cueId}
            onRecordingSaved={handleRecordingSaved}
          />
        ) : (
          <>
            {/* Record new take button */}
            <div className="flex justify-end">
              <Button
                variant="primary"
                size="lg"
                onClick={() => setIsRecordingMode(true)}
                className="!bg-app-green-strong !text-white hover:!bg-app-green-deep !rounded-full"
                leftIcon={<HiOutlineMicrophone className="w-5 h-5" />}
              >
                New Recording
              </Button>
            </div>

            {/* Recording history */}
            {groups.length > 0 && (
              <div className="space-y-6">
                <h2 className="text-heading-lg font-semibold text-text-primary">
                  Recording History
                </h2>

                {groups.map((group, groupIndex) => (
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
                    <div className="space-y-6">
                      {group.recordings.map((rec) => {
                        const audioFile = processedFiles.find(
                          (pf) => pf.fileId === rec.fileId
                        );
                        const audioUrl = audioFile?.url || null;
                        const durationStr = rec.file?.metadata?.duration;
                        const durationMs = durationStr ? parseDuration(durationStr) : 0;

                        return (
                          <Card key={rec.profileCueRecordingId} className="bg-app-beige">
                            <CardContent className="space-y-2">
                              {/* Recording time */}
                              <p className="text-caption text-text-tertiary">
                                {new Date(rec.createdAt).toLocaleString('en-US', {
                                  hour: 'numeric',
                                  minute: '2-digit',
                                  hour12: true,
                                })}
                              </p>

                              {/* Audio player with background */}
                              {audioUrl && (
                                <div className="bg-app-beige-dark rounded-lg p-4 py-6">
                                  <AudioPlayer
                                    id={`recording-${rec.profileCueRecordingId}`}
                                    url={audioUrl}
                                    durationMs={durationMs}
                                  />
                                </div>
                              )}

                              {/* View Report button */}
                                <Button
                                  variant="primary"
                                  size="lg"
                                  onClick={() => {
                                    setSelectedRecordingId(rec.profileCueRecordingId);
                                    setShowTranscriptModal(true);
                                  }}
                                  className="!w-full !bg-app-green-strong !text-white hover:!bg-app-green-deep"
                                  leftIcon={<HiOutlineDocumentText className="w-5 h-5" />}
                                >
                                  View Report
                                </Button>
                            </CardContent>
                          </Card>
                        );
                      })}
                    </div>
                  </div>
                ))}
              </div>
            )}
          </>
        )}
      </div>

      {/* Transcript Modal */}
      <Modal
        isOpen={showTranscriptModal}
        onClose={() => setShowTranscriptModal(false)}
        title={recording.cue?.content?.title || cueData?.cue?.content?.title || 'Recording Report'}
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
