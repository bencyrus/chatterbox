import { HiOutlineEnvelope, HiOutlineUser } from 'react-icons/hi2';
import { Card, CardContent } from '../ui/Card';
import { cn } from '../../lib/cn';
import type { Account } from '../../types';

// ═══════════════════════════════════════════════════════════════════════════
// TYPES
// ═══════════════════════════════════════════════════════════════════════════

interface AccountInfoProps {
  /** Account data */
  account: Account | null;
  /** Additional class names */
  className?: string;
}

// ═══════════════════════════════════════════════════════════════════════════
// ACCOUNT INFO
// ═══════════════════════════════════════════════════════════════════════════

export function AccountInfo({ account, className }: AccountInfoProps) {
  if (!account) {
    return null;
  }

  return (
    <Card className={className}>
      <CardContent className="py-4">
        <div className="flex items-center gap-4">
          {/* Avatar */}
          <div
            className={cn(
              'w-14 h-14 rounded-full flex items-center justify-center',
              'bg-brand-primary/10 text-brand-primary'
            )}
          >
            <HiOutlineUser className="w-7 h-7" />
          </div>

          {/* Info */}
          <div className="flex-1 min-w-0">
            {/* Email */}
            <div className="flex items-center gap-2">
              <HiOutlineEnvelope className="w-4 h-4 text-text-tertiary flex-shrink-0" />
              <p className="text-body-md text-text-primary truncate">
                {account.email || 'No email'}
              </p>
            </div>

            {/* Account ID (optional, for debugging) */}
            {/* <p className="text-body-sm text-text-tertiary mt-1 truncate">
              ID: {account.id}
            </p> */}
          </div>
        </div>
      </CardContent>
    </Card>
  );
}
