import { Link } from 'react-router-dom';
import { ROUTES } from '../../lib/constants';

// ═══════════════════════════════════════════════════════════════════════════
// MARKETING HEADER
// ═══════════════════════════════════════════════════════════════════════════

interface MarketingHeaderProps {
  actions?: React.ReactNode[];
  sticky?: boolean;
}

export function MarketingHeader({ actions, sticky = true }: MarketingHeaderProps) {
  return (
    <header
      className={`bg-white border-b border-border-secondary ${
        sticky ? 'sticky top-0 z-sticky' : ''
      }`}
    >
      <div className="max-w-6xl mx-auto px-6 py-4 flex items-center justify-between">
        <Link to={ROUTES.HOME} className="flex items-center gap-3">
          <img
            src="https://storage.googleapis.com/chatterbox-public-assets/public-chatterbox-logo-color-bg.png"
            alt="Chatterbox"
            className="w-10 h-10 rounded-2xl shadow-card"
          />
          <span className="text-heading-sm font-semibold text-text-primary">
            Chatterbox
          </span>
        </Link>
        {actions && actions.length > 0 ? (
          <div className="flex items-center gap-3">{actions}</div>
        ) : null}
      </div>
    </header>
  );
}
