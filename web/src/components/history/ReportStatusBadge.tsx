import {
  HiOutlineCheckCircle,
  HiOutlineClock,
  HiOutlineDocumentText,
  HiOutlineSparkles,
} from 'react-icons/hi2';
import { MetaBadge } from '../ui/MetaBadge';
import type { ReportStatus, EvaluationStatus } from '../../types';

// ═══════════════════════════════════════════════════════════════════════════
// TYPES
// ═══════════════════════════════════════════════════════════════════════════

interface ReportStatusBadgeProps {
  transcriptionStatus: ReportStatus | null | undefined;
  evaluationStatus?: EvaluationStatus | null | undefined;
}

// ═══════════════════════════════════════════════════════════════════════════
// REPORT STATUS BADGE
// ═══════════════════════════════════════════════════════════════════════════

export function ReportStatusBadge({
  transcriptionStatus,
  evaluationStatus,
}: ReportStatusBadgeProps) {
  if (transcriptionStatus === 'ready' && evaluationStatus === 'ready') {
    return (
      <MetaBadge tone="green" size="md">
        <HiOutlineCheckCircle className="w-3.5 h-3.5" />
        Evaluated
      </MetaBadge>
    );
  }

  if (transcriptionStatus === 'ready' && evaluationStatus === 'processing') {
    return (
      <MetaBadge tone="blue" size="md">
        <HiOutlineSparkles className="w-3.5 h-3.5 animate-pulse" />
        Evaluating
      </MetaBadge>
    );
  }

  if (transcriptionStatus === 'ready') {
    return (
      <MetaBadge tone="green" size="md">
        <HiOutlineCheckCircle className="w-3.5 h-3.5" />
        Transcribed
      </MetaBadge>
    );
  }

  if (transcriptionStatus === 'processing') {
    return (
      <MetaBadge tone="blue" size="md">
        <HiOutlineClock className="w-3.5 h-3.5 animate-spin-slow" />
        Processing
      </MetaBadge>
    );
  }

  return (
    <MetaBadge tone="neutral" size="md">
      <HiOutlineDocumentText className="w-3.5 h-3.5" />
      No report
    </MetaBadge>
  );
}
