import { useCallback } from 'react';
import { useNavigate } from 'react-router-dom';
import { HiOutlineSpeakerWave, HiOutlineChevronRight } from 'react-icons/hi2';
import { Card, CardContent } from '../ui/Card';
import { cn } from '../../lib/cn';
import type { Cue } from '../../types';
import { ROUTES, LANGUAGE_NAMES } from '../../lib/constants';

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
  const languageName = content?.languageCode
    ? LANGUAGE_NAMES[content.languageCode] || content.languageCode
    : '';

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
            'bg-brand-primary/10',
            'flex items-center justify-center',
            'transition-colors duration-150',
            'group-hover:bg-brand-primary/15'
          )}
        >
          <HiOutlineSpeakerWave className="w-6 h-6 text-brand-primary" />
        </div>

        {/* Content */}
        <div className="flex-1 min-w-0">
          {/* Title / Main text */}
          <p className="text-body-md font-medium text-text-primary line-clamp-2">
            {content?.title || 'No prompt available'}
          </p>
          
          {/* Language badge */}
          {languageName && (
            <p className="text-body-sm text-text-tertiary mt-1">
              {languageName}
            </p>
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
