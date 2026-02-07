import { useCallback } from 'react';
import { useNavigate } from 'react-router-dom';
import { Card, CardContent } from '../ui/Card';
import { cn } from '../../lib/cn';
import type { Cue } from '../../types';
import { ROUTES } from '../../lib/constants';

// ═══════════════════════════════════════════════════════════════════════════
// TYPES
// ═══════════════════════════════════════════════════════════════════════════

interface CueCardProps {
  /** Cue data */
  cue: Cue;
  /** Additional class names */
  className?: string;
}

// ═══════════════════════════════════════════════════════════════════════════
// CUE CARD
// ═══════════════════════════════════════════════════════════════════════════

export function CueCard({ cue, className }: CueCardProps) {
  const navigate = useNavigate();

  const handleClick = useCallback(() => {
    navigate(ROUTES.CUE_DETAIL.replace(':cueId', String(cue.cueId)));
  }, [navigate, cue.cueId]);

  // Get content from the cue
  const content = cue.content;

  return (
    <Card
      interactive
      onClick={handleClick}
      className={cn('group', className)}
    >
      <CardContent className="flex items-center gap-4 py-4">
        {/* Content */}
        <div className="flex-1 min-w-0">
          {/* Title / Main text */}
          <p className="text-body-md font-medium text-text-primary line-clamp-2">
            {content?.title || 'No prompt available'}
          </p>
          
        </div>

      </CardContent>
    </Card>
  );
}
