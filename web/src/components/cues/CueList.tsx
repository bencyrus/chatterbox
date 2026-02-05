import { CueCard } from './CueCard';
import { CueCardSkeleton } from './CueCardSkeleton';
import { EmptyState } from '../feedback/EmptyState';
import { ErrorState } from '../feedback/ErrorState';
import { HiOutlineSpeakerWave } from 'react-icons/hi2';
import { cn } from '../../lib/cn';
import type { Cue } from '../../types';

// ═══════════════════════════════════════════════════════════════════════════
// TYPES
// ═══════════════════════════════════════════════════════════════════════════

interface CueListProps {
  /** List of cues */
  cues: Cue[];
  /** Whether cues are loading */
  isLoading: boolean;
  /** Error message if any */
  error: string | null;
  /** Retry handler for error state */
  onRetry?: () => void;
  /** Empty state action handler */
  onEmptyAction?: () => void;
  /** Additional class names */
  className?: string;
}

// ═══════════════════════════════════════════════════════════════════════════
// CUE LIST
// ═══════════════════════════════════════════════════════════════════════════

export function CueList({
  cues,
  isLoading,
  error,
  onRetry,
  onEmptyAction,
  className,
}: CueListProps) {
  // ─────────────────────────────────────────────────────────────────────────
  // Loading state
  // ─────────────────────────────────────────────────────────────────────────

  if (isLoading) {
    return (
      <div className={cn('space-y-3', className)}>
        {Array.from({ length: 5 }).map((_, index) => (
          <CueCardSkeleton key={index} />
        ))}
      </div>
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Error state
  // ─────────────────────────────────────────────────────────────────────────

  if (error) {
    return (
      <ErrorState
        title="Couldn't load cues"
        message={error}
        onRetry={onRetry}
        className={className}
      />
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Empty state
  // ─────────────────────────────────────────────────────────────────────────

  if (cues.length === 0) {
    return (
      <EmptyState
        icon={<HiOutlineSpeakerWave className="w-12 h-12" />}
        title="No cues available"
        description="Tap shuffle to get new practice prompts."
        actionLabel={onEmptyAction ? 'Shuffle' : undefined}
        onAction={onEmptyAction}
        className={className}
      />
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Cue list
  // ─────────────────────────────────────────────────────────────────────────

  return (
    <div className={cn('space-y-3', className)}>
      {cues.map((cue) => (
        <CueCard key={cue.id} cue={cue} />
      ))}
    </div>
  );
}
