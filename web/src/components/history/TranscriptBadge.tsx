import { HiOutlineDocumentText, HiOutlineClock } from 'react-icons/hi2';
import { Badge } from '../ui/Badge';
import type { ReportStatus } from '../../types';

// ═══════════════════════════════════════════════════════════════════════════
// TYPES
// ═══════════════════════════════════════════════════════════════════════════

interface TranscriptBadgeProps {
  /** Transcription status */
  status: ReportStatus | null | undefined;
}

// ═══════════════════════════════════════════════════════════════════════════
// TRANSCRIPT BADGE
// ═══════════════════════════════════════════════════════════════════════════

export function TranscriptBadge({ status }: TranscriptBadgeProps) {
  if (!status || status === 'none') {
    return null;
  }

  switch (status) {
    case 'ready':
      return (
        <Badge variant="success">
          <HiOutlineDocumentText className="w-3 h-3 mr-1" />
          Transcript
        </Badge>
      );
    
    case 'processing':
      return (
        <Badge variant="default">
          <HiOutlineClock className="w-3 h-3 mr-1 animate-spin-slow" />
          Processing
        </Badge>
      );
    
    default:
      return null;
  }
}
