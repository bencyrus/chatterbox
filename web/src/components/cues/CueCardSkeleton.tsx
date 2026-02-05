import { Card, CardContent } from '../ui/Card';
import { cn } from '../../lib/cn';

// ═══════════════════════════════════════════════════════════════════════════
// CUE CARD SKELETON
// ═══════════════════════════════════════════════════════════════════════════

interface CueCardSkeletonProps {
  className?: string;
}

export function CueCardSkeleton({ className }: CueCardSkeletonProps) {
  return (
    <Card className={cn('animate-pulse', className)}>
      <CardContent className="flex items-center gap-4 py-4">
        {/* Icon skeleton */}
        <div className="w-12 h-12 flex-shrink-0 rounded-xl bg-surface-tertiary" />

        {/* Content skeleton */}
        <div className="flex-1 min-w-0">
          <div className="h-5 bg-surface-tertiary rounded w-3/4 mb-2" />
          <div className="h-4 bg-surface-tertiary rounded w-1/4" />
        </div>

        {/* Chevron skeleton */}
        <div className="w-5 h-5 flex-shrink-0 rounded bg-surface-tertiary" />
      </CardContent>
    </Card>
  );
}
