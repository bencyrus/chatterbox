import { useCallback } from 'react';
import { useNavigate } from 'react-router-dom';
import { HiOutlineChevronRight, HiOutlineSpeakerWave } from 'react-icons/hi2';
import { Card, CardContent } from '../ui/Card';
import { TranscriptBadge } from './TranscriptBadge';
import { cn } from '../../lib/cn';
import { formatTime, parseDuration, formatDurationMs } from '../../lib/date';
import { ROUTES, LANGUAGE_NAMES } from '../../lib/constants';
import type { Recording } from '../../types';

// ═══════════════════════════════════════════════════════════════════════════
// TYPES
// ═══════════════════════════════════════════════════════════════════════════

interface RecordingCardProps {
  /** Recording data */
  recording: Recording;
  /** Additional class names */
  className?: string;
}

// ═══════════════════════════════════════════════════════════════════════════
// RECORDING CARD
// ═══════════════════════════════════════════════════════════════════════════

export function RecordingCard({ recording, className }: RecordingCardProps) {
  const navigate = useNavigate();

  const handleClick = useCallback(() => {
    navigate(ROUTES.RECORDING_DETAIL.replace(':recordingId', String(recording.profileCueRecordingId)));
  }, [navigate, recording.profileCueRecordingId]);

  // Get language name from cue content
  const languageCode = recording.cue?.content?.languageCode;
  const languageName = languageCode
    ? LANGUAGE_NAMES[languageCode] || languageCode
    : '';

  // Get cue text (title)
  const cueText = recording.cue?.content?.title || 'Recording';

  // Get duration from file metadata
  const durationStr = recording.file?.metadata?.duration;
  const durationMs = durationStr ? parseDuration(durationStr) : 0;

  // Get transcript status
  const transcriptStatus = recording.report?.status;

  return (
    <Card
      interactive
      onClick={handleClick}
      className={cn('group', className)}
    >
      <CardContent className="flex items-center gap-4 py-4">
        {/* Icon */}
        <div
          className={cn(
            'w-12 h-12 flex-shrink-0 rounded-xl',
            'bg-surface-tertiary',
            'flex items-center justify-center',
            'transition-colors duration-150',
            'group-hover:bg-surface-secondary'
          )}
        >
          <HiOutlineSpeakerWave className="w-6 h-6 text-text-secondary" />
        </div>

        {/* Content */}
        <div className="flex-1 min-w-0">
          {/* Cue text */}
          <p className="text-body-md font-medium text-text-primary line-clamp-2">
            {cueText}
          </p>
          
          {/* Meta info */}
          <div className="flex items-center gap-2 mt-1">
            {/* Time */}
            <span className="text-body-sm text-text-tertiary">
              {formatTime(recording.createdAt)}
            </span>
            
            {/* Duration */}
            {durationMs > 0 && (
              <>
                <span className="text-text-tertiary">•</span>
                <span className="text-body-sm text-text-tertiary">
                  {formatDurationMs(durationMs)}
                </span>
              </>
            )}
            
            {/* Language */}
            {languageName && (
              <>
                <span className="text-text-tertiary">•</span>
                <span className="text-body-sm text-text-tertiary">
                  {languageName}
                </span>
              </>
            )}
          </div>

          {/* Transcript badge */}
          {transcriptStatus && (
            <div className="mt-2">
              <TranscriptBadge status={transcriptStatus} />
            </div>
          )}
        </div>

        {/* Chevron */}
        <HiOutlineChevronRight
          className={cn(
            'w-5 h-5 flex-shrink-0 text-text-tertiary',
            'transition-transform duration-150',
            'group-hover:translate-x-0.5'
          )}
        />
      </CardContent>
    </Card>
  );
}
