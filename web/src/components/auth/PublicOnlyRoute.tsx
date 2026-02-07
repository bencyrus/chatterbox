import { Navigate, useLocation } from 'react-router-dom';
import { useAuth } from '../../contexts/AuthContext';
import { Spinner } from '../ui/Spinner';
import { ROUTES } from '../../lib/constants';

// ═══════════════════════════════════════════════════════════════════════════
// TYPES
// ═══════════════════════════════════════════════════════════════════════════

interface PublicOnlyRouteProps {
  children: React.ReactNode;
}

interface LocationState {
  from?: {
    pathname: string;
  };
}

// ═══════════════════════════════════════════════════════════════════════════
// PUBLIC ONLY ROUTE
// ═══════════════════════════════════════════════════════════════════════════

/**
 * Route guard that allows only unauthenticated users.
 * Redirects to home page if already authenticated.
 */
export function PublicOnlyRoute({ children }: PublicOnlyRouteProps) {
  const { isAuthenticated, isLoading } = useAuth();
  const location = useLocation();

  // Show loading state while checking auth
  if (isLoading) {
    return (
      <div className="min-h-screen flex items-center justify-center bg-app-sand-light">
        <Spinner size="lg" />
      </div>
    );
  }

  // Redirect to home (or intended destination) if already authenticated
  if (isAuthenticated) {
    const state = location.state as LocationState | null;
    const from = state?.from?.pathname || ROUTES.HOME;
    return <Navigate to={from} replace />;
  }

  return <>{children}</>;
}
