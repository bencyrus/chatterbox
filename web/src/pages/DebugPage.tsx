import { useState, useEffect } from 'react';
import { Button } from '../components/ui/Button';
import { getTokens, isPWAMode, clearTokens } from '../lib/storage';
import { useNavigate } from 'react-router-dom';
import { ROUTES } from '../lib/constants';
import { useAuth } from '../contexts/AuthContext';

// ═══════════════════════════════════════════════════════════════════════════
// DEBUG PAGE
// ═══════════════════════════════════════════════════════════════════════════

function DebugPage() {
  const navigate = useNavigate();
  const { isAuthenticated, account } = useAuth();
  const [tokens, setTokensState] = useState(getTokens());
  const [localStorageKeys, setLocalStorageKeys] = useState<string[]>([]);

  useEffect(() => {
    // Get all localStorage keys
    const keys: string[] = [];
    for (let i = 0; i < localStorage.length; i++) {
      const key = localStorage.key(i);
      if (key) keys.push(key);
    }
    setLocalStorageKeys(keys);
  }, []);

  const handleRefresh = () => {
    setTokensState(getTokens());
    
    const keys: string[] = [];
    for (let i = 0; i < localStorage.length; i++) {
      const key = localStorage.key(i);
      if (key) keys.push(key);
    }
    setLocalStorageKeys(keys);
  };

  const handleClearTokens = () => {
    clearTokens();
    handleRefresh();
  };

  const inPWA = isPWAMode();
  const hasTokens = !!(tokens.accessToken && tokens.refreshToken);
  
  // Diagnosis
  let diagnosis = '';
  let diagnosisColor = '';
  
  if (isAuthenticated && account) {
    diagnosis = '✅ SUCCESS - You are logged in!';
    diagnosisColor = 'bg-success-50 border-success-600 text-success-700';
  } else if (hasTokens && !isAuthenticated) {
    diagnosis = '⚠️ ISSUE - Tokens found but not authenticated. Tokens may be expired or invalid.';
    diagnosisColor = 'bg-warning-50 border-warning-600 text-warning-700';
  } else if (!hasTokens) {
    diagnosis = '❌ PROBLEM - No tokens found in localStorage. Tokens were not saved or you\'re on a different domain.';
    diagnosisColor = 'bg-error-50 border-error-600 text-error-700';
  }

  return (
    <div className="min-h-screen bg-app-sand-light p-6">
      <div className="max-w-2xl mx-auto">
        <h1 className="text-heading-xl font-bold text-text-primary mb-6">
          🔍 Debug Info
        </h1>
        
        {/* Diagnosis Banner */}
        <div className={`${diagnosisColor} border-2 rounded-2xl p-4 mb-6 font-semibold text-center`}>
          {diagnosis}
        </div>

        {/* Auth Status */}
        <div className="bg-white rounded-3xl shadow-card border border-border-secondary p-6 mb-4">
          <h2 className="text-heading-lg font-semibold text-text-primary mb-4">
            Auth Status
          </h2>
          <div className="space-y-3">
            <div className="p-3 bg-app-sand-light rounded-xl">
              <div className="flex items-center justify-between">
                <span className="font-semibold">Logged In:</span>
                <span className={`text-lg ${isAuthenticated ? 'text-success-600' : 'text-error-600'}`}>
                  {isAuthenticated ? '✅ YES' : '❌ NO'}
                </span>
              </div>
            </div>
            {account && (
              <div className="p-3 bg-success-50 rounded-xl">
                <p className="text-sm text-success-700 font-semibold">Account ID:</p>
                <p className="text-xs font-mono text-success-600 break-all">{account.accountId}</p>
              </div>
            )}
          </div>
        </div>

        {/* Environment Info */}
        <div className="bg-white rounded-3xl shadow-card border border-border-secondary p-6 mb-4">
          <h2 className="text-heading-lg font-semibold text-text-primary mb-4">
            Environment
          </h2>
          <div className="space-y-3">
            <div className="p-3 bg-app-sand-light rounded-xl">
              <p className="font-semibold text-sm mb-1">Mode:</p>
              <p className={`text-lg font-bold ${inPWA ? 'text-success-600' : 'text-warning-600'}`}>
                {inPWA ? '📱 PWA (Standalone)' : '🌐 Browser (Safari)'}
              </p>
            </div>
            <div className="p-3 bg-app-sand-light rounded-xl">
              <p className="font-semibold text-sm mb-1">Origin (IMPORTANT!):</p>
              <p className="text-sm font-mono text-text-primary break-all bg-white p-2 rounded border">
                {window.location.origin}
              </p>
              <p className="text-xs text-text-secondary mt-1">
                This must be EXACTLY the same in both Safari and PWA for tokens to be shared!
              </p>
            </div>
            <div className="p-3 bg-app-sand-light rounded-xl">
              <p className="font-semibold text-sm mb-1">Full URL:</p>
              <p className="text-xs font-mono text-text-secondary break-all">
                {window.location.href}
              </p>
            </div>
          </div>
        </div>

        {/* Token Info */}
        <div className="bg-white rounded-3xl shadow-card border border-border-secondary p-6 mb-4">
          <h2 className="text-heading-lg font-semibold text-text-primary mb-4">
            Auth Tokens
          </h2>
          <div className="space-y-2 text-body-md font-mono">
            <div className="flex">
              <span className="font-semibold w-32">Access Token:</span>
              <span className={tokens.accessToken ? 'text-success-600' : 'text-error-600'}>
                {tokens.accessToken ? `✅ ${tokens.accessToken.substring(0, 20)}...` : '❌ Not found'}
              </span>
            </div>
            <div className="flex">
              <span className="font-semibold w-32">Refresh Token:</span>
              <span className={tokens.refreshToken ? 'text-success-600' : 'text-error-600'}>
                {tokens.refreshToken ? `✅ ${tokens.refreshToken.substring(0, 20)}...` : '❌ Not found'}
              </span>
            </div>
          </div>
        </div>

        {/* LocalStorage Contents */}
        <div className="bg-white rounded-3xl shadow-card border border-border-secondary p-6 mb-4">
          <h2 className="text-heading-lg font-semibold text-text-primary mb-4">
            localStorage Contents
          </h2>
          {localStorageKeys.length === 0 ? (
            <p className="text-body-md text-text-secondary">No items in localStorage</p>
          ) : (
            <div className="space-y-2">
              {localStorageKeys.map((key) => (
                <div key={key} className="flex flex-col border-b border-border-secondary pb-2">
                  <span className="font-semibold text-sm">{key}</span>
                  <span className="text-xs text-text-secondary font-mono break-all">
                    {localStorage.getItem(key)?.substring(0, 100)}
                    {(localStorage.getItem(key)?.length || 0) > 100 ? '...' : ''}
                  </span>
                </div>
              ))}
            </div>
          )}
        </div>

        {/* Actions */}
        <div className="space-y-3">
          <Button
            variant="primary"
            onClick={handleRefresh}
            className="w-full bg-success-600 text-white hover:bg-success-700"
          >
            🔄 Refresh Debug Info
          </Button>
          {hasTokens && (
            <Button
              variant="secondary"
              onClick={handleClearTokens}
              className="w-full bg-warning-100 text-warning-700 border border-warning-300 hover:bg-warning-200"
            >
              🗑️ Clear Tokens (Logout)
            </Button>
          )}
          {isAuthenticated ? (
            <Button
              variant="secondary"
              onClick={() => navigate(ROUTES.APP)}
              className="w-full bg-app-beige text-text-primary border border-border-secondary hover:bg-app-beige-dark"
            >
              Go to App
            </Button>
          ) : (
            <Button
              variant="secondary"
              onClick={() => navigate(ROUTES.LOGIN)}
              className="w-full bg-app-beige text-text-primary border border-border-secondary hover:bg-app-beige-dark"
            >
              Go to Login
            </Button>
          )}
        </div>

        {/* Instructions */}
        <div className="mt-6 p-4 bg-blue-50 border-2 border-blue-200 rounded-2xl">
          <h3 className="font-semibold text-blue-900 mb-3 text-lg">📋 How to diagnose:</h3>
          <ol className="text-body-sm text-blue-800 space-y-2 list-decimal list-inside pl-2">
            <li><strong>After clicking magic link</strong> (in Safari): Tap "🔍 View Debug Info"</li>
            <li><strong>Screenshot the Origin</strong> shown above (or write it down)</li>
            <li><strong>Close Safari</strong> completely</li>
            <li><strong>Open PWA</strong> from home screen</li>
            <li><strong>Go to this page</strong> by typing in URL: <code className="bg-white px-1 rounded">/debug</code></li>
            <li><strong>Compare Origins</strong>: They must be EXACTLY the same!</li>
          </ol>
          
          <div className="mt-4 p-3 bg-blue-100 rounded-xl">
            <p className="text-sm font-semibold text-blue-900 mb-1">✅ GOOD (will work):</p>
            <p className="text-xs font-mono text-blue-700">Safari: https://chatterboxtalk.com</p>
            <p className="text-xs font-mono text-blue-700">PWA: https://chatterboxtalk.com</p>
          </div>
          
          <div className="mt-2 p-3 bg-red-100 rounded-xl">
            <p className="text-sm font-semibold text-red-900 mb-1">❌ BAD (won't work):</p>
            <p className="text-xs font-mono text-red-700">Safari: https://chatterboxtalk.com</p>
            <p className="text-xs font-mono text-red-700">PWA: https://www.chatterboxtalk.com</p>
            <p className="text-xs text-red-600 mt-1">⚠️ Different! The "www" makes them different origins!</p>
          </div>
        </div>
      </div>
    </div>
  );
}

export default DebugPage;
