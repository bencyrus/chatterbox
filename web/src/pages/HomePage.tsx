import { Link } from 'react-router-dom';
import { useAuth } from '../contexts/AuthContext';
import { ROUTES } from '../lib/constants';

// ═══════════════════════════════════════════════════════════════════════════
// HOME PAGE
// ═══════════════════════════════════════════════════════════════════════════

/**
 * Home page - public landing page
 * Accessible to both authenticated and unauthenticated users
 */
function HomePage() {
  const { isAuthenticated } = useAuth();

  return (
    <div className="min-h-screen bg-surface-primary flex flex-col items-center justify-center p-6">
      <div className="max-w-md w-full text-center space-y-8">
        {/* Logo/Brand */}
        <div className="space-y-4">
          <h1 className="text-heading-xl font-bold text-text-primary">
            Chatterbox
          </h1>
          <p className="text-body-lg text-text-secondary">
            Practice speaking with confidence
          </p>
        </div>

        {/* CTA - different based on auth state */}
        {isAuthenticated ? (
          <Link
            to={ROUTES.APP}
            className="btn-base bg-brand-500 text-white hover:bg-brand-600 active:bg-brand-700 shadow-button text-label-lg px-8 py-4 inline-block"
          >
            Open App
          </Link>
        ) : (
          <Link
            to={ROUTES.LOGIN}
            className="btn-base bg-brand-500 text-white hover:bg-brand-600 active:bg-brand-700 shadow-button text-label-lg px-8 py-4 inline-block"
          >
            Get Started
          </Link>
        )}

        {/* Footer links */}
        <div className="pt-8">
          <Link
            to={ROUTES.PRIVACY}
            className="text-body-sm text-text-tertiary hover:text-text-secondary"
          >
            Privacy Policy
          </Link>
        </div>
      </div>
    </div>
  );
}

export default HomePage;
