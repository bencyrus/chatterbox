import { BrowserRouter as Router, Routes, Route, Navigate } from 'react-router-dom';
import { lazy, Suspense } from 'react';

// Providers
import {
  AuthProvider,
  ToastProvider,
  ProfileProvider,
  ConfigProvider,
  AudioProvider,
} from './contexts';

// Route guards
import { ProtectedRoute } from './components/auth/ProtectedRoute';
import { PublicOnlyRoute } from './components/auth/PublicOnlyRoute';

// Layout
import { AppLayout } from './components/layout/AppLayout';

// Feedback
import { ToastContainer } from './components/feedback/Toast';
import { LoadingScreen } from './components/feedback/LoadingScreen';

// Bootstrap hook
import { useBootstrap } from './hooks/auth/useBootstrap';

// Pages (eager load critical pages)
import HomePage from './pages/HomePage';
import LoginPage from './pages/LoginPage';
import MagicLinkPage from './pages/MagicLinkPage';
import PrivacyPage from './pages/PrivacyPage';
import RequestAccountRestorePage from './pages/RequestAccountRestorePage';

// Lazy load feature pages
const CuesPage = lazy(() => import('./pages/CuesPage'));
const CueDetailPage = lazy(() => import('./pages/CueDetailPage'));
const HistoryPage = lazy(() => import('./pages/HistoryPage'));
const RecordingDetailPage = lazy(() => import('./pages/RecordingDetailPage'));
const SettingsPage = lazy(() => import('./pages/SettingsPage'));

// Constants
import { ROUTES } from './lib/constants';

// ═══════════════════════════════════════════════════════════════════════════
// APP BOOTSTRAP
// ═══════════════════════════════════════════════════════════════════════════

/**
 * Inner app component that handles auth bootstrap
 */
function AppBootstrap() {
  // Initialize auth state on mount
  useBootstrap();

  return (
    <>
      <ToastContainer />
      <Suspense fallback={<LoadingScreen message="Loading..." />}>
        <Routes>
          {/* ─────────────────────────────────────────────────────────────────
              PUBLIC ROUTES
          ───────────────────────────────────────────────────────────────── */}
          {/* Home / Landing page */}
          <Route path={ROUTES.HOME} element={<HomePage />} />

          {/* Login - redirects to app if already authenticated */}
          <Route
            path={ROUTES.LOGIN}
            element={
              <PublicOnlyRoute>
                <LoginPage />
              </PublicOnlyRoute>
            }
          />

          {/* Magic link callback */}
          <Route path={ROUTES.MAGIC_LINK} element={<MagicLinkPage />} />

          {/* Static pages */}
          <Route path={ROUTES.PRIVACY} element={<PrivacyPage />} />
          <Route
            path={ROUTES.REQUEST_ACCOUNT_RESTORE}
            element={<RequestAccountRestorePage />}
          />

          {/* ─────────────────────────────────────────────────────────────────
              PROTECTED ROUTES (under /app)
          ───────────────────────────────────────────────────────────────── */}
          <Route
            path="/app"
            element={
              <ProtectedRoute>
                <AppLayout />
              </ProtectedRoute>
            }
          >
            {/* /app -> redirect to /app/cues */}
            <Route index element={<Navigate to={ROUTES.CUES} replace />} />

            {/* Cues / Practice */}
            <Route path="cues" element={<CuesPage />} />
            <Route path="cues/:cueId" element={<CueDetailPage />} />

            {/* History */}
            <Route path="history" element={<HistoryPage />} />
            <Route path="history/:recordingId" element={<RecordingDetailPage />} />

            {/* Settings */}
            <Route path="settings" element={<SettingsPage />} />
          </Route>

          {/* ─────────────────────────────────────────────────────────────────
              FALLBACK
          ───────────────────────────────────────────────────────────────── */}
          {/* Catch-all redirect to home */}
          <Route path="*" element={<Navigate to={ROUTES.HOME} replace />} />
        </Routes>
      </Suspense>
    </>
  );
}

// ═══════════════════════════════════════════════════════════════════════════
// APP
// ═══════════════════════════════════════════════════════════════════════════

function App() {
  return (
    <Router>
      <ConfigProvider>
        <AuthProvider>
          <ProfileProvider>
            <AudioProvider>
              <ToastProvider>
                <AppBootstrap />
              </ToastProvider>
            </AudioProvider>
          </ProfileProvider>
        </AuthProvider>
      </ConfigProvider>
    </Router>
  );
}

export default App;
