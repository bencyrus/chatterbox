import {
  createContext,
  useContext,
  useReducer,
  useCallback,
  type ReactNode,
} from 'react';
import type { Profile, ActiveProfileSummary } from '../types';

// ═══════════════════════════════════════════════════════════════════════════
// TYPES
// ═══════════════════════════════════════════════════════════════════════════

interface ProfileState {
  activeProfile: ActiveProfileSummary | null;
  allProfiles: Profile[];
  isLoading: boolean;
}

type ProfileAction =
  | { type: 'SET_ACTIVE_PROFILE'; payload: ActiveProfileSummary | null }
  | { type: 'SET_ALL_PROFILES'; payload: Profile[] }
  | { type: 'SET_LOADING'; payload: boolean }
  | { type: 'RESET' };

interface ProfileContextValue extends ProfileState {
  setActiveProfile: (profile: ActiveProfileSummary | null) => void;
  setAllProfiles: (profiles: Profile[]) => void;
  setLoading: (isLoading: boolean) => void;
  reset: () => void;
}

// ═══════════════════════════════════════════════════════════════════════════
// INITIAL STATE
// ═══════════════════════════════════════════════════════════════════════════

const initialState: ProfileState = {
  activeProfile: null,
  allProfiles: [],
  isLoading: false,
};

// ═══════════════════════════════════════════════════════════════════════════
// REDUCER
// ═══════════════════════════════════════════════════════════════════════════

function profileReducer(state: ProfileState, action: ProfileAction): ProfileState {
  switch (action.type) {
    case 'SET_ACTIVE_PROFILE':
      return { ...state, activeProfile: action.payload };
    case 'SET_ALL_PROFILES':
      return { ...state, allProfiles: action.payload };
    case 'SET_LOADING':
      return { ...state, isLoading: action.payload };
    case 'RESET':
      return initialState;
    default:
      return state;
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// CONTEXT
// ═══════════════════════════════════════════════════════════════════════════

const ProfileContext = createContext<ProfileContextValue | null>(null);

// ═══════════════════════════════════════════════════════════════════════════
// PROVIDER
// ═══════════════════════════════════════════════════════════════════════════

interface ProfileProviderProps {
  children: ReactNode;
}

export function ProfileProvider({ children }: ProfileProviderProps) {
  const [state, dispatch] = useReducer(profileReducer, initialState);

  // ─────────────────────────────────────────────────────────────────────────
  // Actions
  // ─────────────────────────────────────────────────────────────────────────

  const setActiveProfile = useCallback((profile: ActiveProfileSummary | null) => {
    dispatch({ type: 'SET_ACTIVE_PROFILE', payload: profile });
  }, []);

  const setAllProfiles = useCallback((profiles: Profile[]) => {
    dispatch({ type: 'SET_ALL_PROFILES', payload: profiles });
  }, []);

  const setLoading = useCallback((isLoading: boolean) => {
    dispatch({ type: 'SET_LOADING', payload: isLoading });
  }, []);

  const reset = useCallback(() => {
    dispatch({ type: 'RESET' });
  }, []);

  // ─────────────────────────────────────────────────────────────────────────
  // Value
  // ─────────────────────────────────────────────────────────────────────────

  const value: ProfileContextValue = {
    ...state,
    setActiveProfile,
    setAllProfiles,
    setLoading,
    reset,
  };

  return (
    <ProfileContext.Provider value={value}>
      {children}
    </ProfileContext.Provider>
  );
}

// ═══════════════════════════════════════════════════════════════════════════
// HOOK
// ═══════════════════════════════════════════════════════════════════════════

export function useProfile(): ProfileContextValue {
  const context = useContext(ProfileContext);
  if (!context) {
    throw new Error('useProfile must be used within a ProfileProvider');
  }
  return context;
}
