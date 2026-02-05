import {
  createContext,
  useContext,
  useState,
  useCallback,
  useRef,
  type ReactNode,
} from 'react';

// ═══════════════════════════════════════════════════════════════════════════
// TYPES
// ═══════════════════════════════════════════════════════════════════════════

interface AudioContextValue {
  /** Currently playing audio ID */
  currentPlayingId: string | null;
  /** Register audio as playing */
  setPlaying: (id: string | null) => void;
  /** Stop any playing audio */
  stopAll: () => void;
  /** Check if a specific audio is playing */
  isPlaying: (id: string) => boolean;
  /** Global audio element ref for playback */
  audioRef: React.RefObject<HTMLAudioElement | null>;
}

// ═══════════════════════════════════════════════════════════════════════════
// CONTEXT
// ═══════════════════════════════════════════════════════════════════════════

const AudioContext = createContext<AudioContextValue | null>(null);

// ═══════════════════════════════════════════════════════════════════════════
// PROVIDER
// ═══════════════════════════════════════════════════════════════════════════

interface AudioProviderProps {
  children: ReactNode;
}

export function AudioProvider({ children }: AudioProviderProps) {
  const [currentPlayingId, setCurrentPlayingId] = useState<string | null>(null);
  const audioRef = useRef<HTMLAudioElement | null>(null);

  // ─────────────────────────────────────────────────────────────────────────
  // Set playing
  // ─────────────────────────────────────────────────────────────────────────

  const setPlaying = useCallback((id: string | null) => {
    // If setting a new ID, stop the current audio first
    if (id && currentPlayingId && id !== currentPlayingId && audioRef.current) {
      audioRef.current.pause();
      audioRef.current.currentTime = 0;
    }
    setCurrentPlayingId(id);
  }, [currentPlayingId]);

  // ─────────────────────────────────────────────────────────────────────────
  // Stop all
  // ─────────────────────────────────────────────────────────────────────────

  const stopAll = useCallback(() => {
    if (audioRef.current) {
      audioRef.current.pause();
      audioRef.current.currentTime = 0;
    }
    setCurrentPlayingId(null);
  }, []);

  // ─────────────────────────────────────────────────────────────────────────
  // Is playing
  // ─────────────────────────────────────────────────────────────────────────

  const isPlaying = useCallback(
    (id: string) => currentPlayingId === id,
    [currentPlayingId]
  );

  // ─────────────────────────────────────────────────────────────────────────
  // Value
  // ─────────────────────────────────────────────────────────────────────────

  const value: AudioContextValue = {
    currentPlayingId,
    setPlaying,
    stopAll,
    isPlaying,
    audioRef,
  };

  return (
    <AudioContext.Provider value={value}>
      {children}
      {/* Hidden audio element for global playback */}
      <audio ref={audioRef} className="hidden" />
    </AudioContext.Provider>
  );
}

// ═══════════════════════════════════════════════════════════════════════════
// HOOK
// ═══════════════════════════════════════════════════════════════════════════

export function useAudio(): AudioContextValue {
  const context = useContext(AudioContext);
  if (!context) {
    throw new Error('useAudio must be used within an AudioProvider');
  }
  return context;
}
