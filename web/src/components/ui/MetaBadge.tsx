import type { ReactNode } from 'react';
import { cn } from '../../lib/cn';

// ═══════════════════════════════════════════════════════════════════════════
// TYPES
// ═══════════════════════════════════════════════════════════════════════════

type MetaBadgeTone = 'neutral' | 'blue' | 'green';
type MetaBadgeSize = 'sm' | 'md';

interface MetaBadgeProps {
  children: ReactNode;
  tone?: MetaBadgeTone;
  size?: MetaBadgeSize;
  className?: string;
}

// ═══════════════════════════════════════════════════════════════════════════
// STYLES
// ═══════════════════════════════════════════════════════════════════════════

const toneStyles: Record<MetaBadgeTone, string> = {
  // Warmer neutral grey (closer to iOS divider on sand surfaces).
  neutral: 'bg-[#D9D9D9] text-text-primary',
  blue: 'bg-app-blue text-text-primary',
  green: 'bg-app-green text-text-primary',
};

const sizeStyles: Record<MetaBadgeSize, string> = {
  sm: 'px-2 py-1 text-label-sm',
  md: 'px-2.5 py-1.5 text-label-md',
};

// ═══════════════════════════════════════════════════════════════════════════
// COMPONENT
// ═══════════════════════════════════════════════════════════════════════════

export function MetaBadge({
  children,
  tone = 'neutral',
  size = 'md',
  className,
}: MetaBadgeProps) {
  return (
    <span
      className={cn(
        'inline-flex items-center gap-1.5 rounded-md font-medium',
        toneStyles[tone],
        sizeStyles[size],
        className
      )}
    >
      {children}
    </span>
  );
}

