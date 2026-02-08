import {
  HiOutlineCheckCircle,
  HiOutlineClock,
  HiOutlineDocumentText,
} from 'react-icons/hi2';
import { MetaBadge } from '../ui/MetaBadge';
import type { ReportStatus } from '../../types';

// ═══════════════════════════════════════════════════════════════════════════
// TYPES
// ═══════════════════════════════════════════════════════════════════════════

interface ReportStatusBadgeProps {
  /** Report/transcription status */
  status: ReportStatus | null | undefined;
}

// ═══════════════════════════════════════════════════════════════════════════
// REPORT STATUS BADGE
// ═══════════════════════════════════════════════════════════════════════════

export function ReportStatusBadge({ status }: ReportStatusBadgeProps) {
  switch (status) {
    case 'ready':
      return (
        <MetaBadge tone="green" size="md">
          <HiOutlineCheckCircle className="w-3.5 h-3.5" />
          Ready
        </MetaBadge>
      );

    case 'processing':
      return (
        <MetaBadge tone="blue" size="md">
          <HiOutlineClock className="w-3.5 h-3.5 animate-spin-slow" />
          Processing
        </MetaBadge>
      );

    case 'none':
    case null:
    case undefined:
    default:
      return (
        <MetaBadge tone="neutral" size="md">
          <HiOutlineDocumentText className="w-3.5 h-3.5" />
          No report
        </MetaBadge>
      );
  }
}

