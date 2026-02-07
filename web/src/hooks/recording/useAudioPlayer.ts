import { useState, useCallback, useRef, useEffect } from 'react';
import { useAudio } from '../../contexts/AudioContext';

// ═══════════════════════════════════════════════════════════════════════════
// TYPES
// ═══════════════════════════════════════════════════════════════════════════

interface UseAudioPlayerParams {
  /** Unique ID for this player */
  id: string;
  /** Audio URL to play */
  url: string | null;
  /** Callback when playback ends */
  onEnded?: () => void;
}

interface UseAudioPlayerReturn {
  /** Whether audio is currently playing */
  isPlaying: boolean;
  /** Current playback position (0-1) */
  progress: number;
  /** Current time in seconds */
  currentTime: number;
  /** Total duration in seconds */
  duration: number;
  /** Play audio */
  play: () => void;
  /** Pause audio */
  pause: () => void;
  /** Toggle play/pause */
  toggle: () => void;
  /** Seek to position (0-1) */
  seek: (position: number) => void;
}

// ═══════════════════════════════════════════════════════════════════════════
// HOOK
// ═══════════════════════════════════════════════════════════════════════════

export function useAudioPlayer({
  id,
  url,
  onEnded,
}: UseAudioPlayerParams): UseAudioPlayerReturn {
  const { currentPlayingId, setPlaying } = useAudio();
  const [progress, setProgress] = useState(0);
  const [currentTime, setCurrentTime] = useState(0);
  const [duration, setDuration] = useState(0);
  
  const isPlaying = currentPlayingId === id;
  const localAudioRef = useRef<HTMLAudioElement | null>(null);

  // ─────────────────────────────────────────────────────────────────────────
  // Initialize audio element when URL is available
  // ─────────────────────────────────────────────────────────────────────────

  useEffect(() => {
    if (!url) return;

    // Create audio element if it doesn't exist
    if (!localAudioRef.current) {
      const audio = new Audio(url);
      audio.preload = 'metadata';
      localAudioRef.current = audio;
    } else if (localAudioRef.current.src !== url) {
      // Update src if URL changed
      const wasPlaying = !localAudioRef.current.paused;
      localAudioRef.current.src = url;
      localAudioRef.current.preload = 'metadata';
      if (wasPlaying) {
        localAudioRef.current.play().catch(console.error);
      }
    }
  }, [url]);

  // ─────────────────────────────────────────────────────────────────────────
  // Play
  // ─────────────────────────────────────────────────────────────────────────

  const play = useCallback(() => {
    const audio = localAudioRef.current;
    if (!audio || !url) return;

    audio.play().catch(console.error);
    setPlaying(id);
  }, [id, url, setPlaying]);

  // ─────────────────────────────────────────────────────────────────────────
  // Pause
  // ─────────────────────────────────────────────────────────────────────────

  const pause = useCallback(() => {
    const audio = localAudioRef.current;
    if (audio) {
      audio.pause();
    }
    setPlaying(null);
  }, [setPlaying]);

  // ─────────────────────────────────────────────────────────────────────────
  // Toggle
  // ─────────────────────────────────────────────────────────────────────────

  const toggle = useCallback(() => {
    if (isPlaying) {
      pause();
    } else {
      play();
    }
  }, [isPlaying, play, pause]);

  // ─────────────────────────────────────────────────────────────────────────
  // Seek (accepts time in seconds)
  // ─────────────────────────────────────────────────────────────────────────

  const seek = useCallback((timeInSeconds: number) => {
    const audio = localAudioRef.current;
    if (!audio || !isFinite(audio.duration) || audio.duration <= 0) return;
    if (!isFinite(timeInSeconds)) return;

    audio.currentTime = timeInSeconds;
    setCurrentTime(timeInSeconds);
    setProgress(timeInSeconds / audio.duration);
  }, []);

  // ─────────────────────────────────────────────────────────────────────────
  // Setup audio events
  // ─────────────────────────────────────────────────────────────────────────

  useEffect(() => {
    const audio = localAudioRef.current;
    if (!audio) return;

    const handleTimeUpdate = () => {
      setCurrentTime(audio.currentTime);
      
      // Update duration if it's valid (not Infinity or 0)
      if (isFinite(audio.duration) && audio.duration > 0) {
        setDuration(audio.duration);
        setProgress(audio.currentTime / audio.duration);
      }
    };

    const handleLoadedMetadata = () => {
      // Only set duration if it's a valid finite number
      if (isFinite(audio.duration) && audio.duration > 0) {
        setDuration(audio.duration);
      }
    };

    const handleEnded = () => {
      setProgress(0);
      setCurrentTime(0);
      setPlaying(null);
      onEnded?.();
    };

    audio.addEventListener('timeupdate', handleTimeUpdate);
    audio.addEventListener('loadedmetadata', handleLoadedMetadata);
    audio.addEventListener('ended', handleEnded);

    return () => {
      audio.removeEventListener('timeupdate', handleTimeUpdate);
      audio.removeEventListener('loadedmetadata', handleLoadedMetadata);
      audio.removeEventListener('ended', handleEnded);
    };
  }, [url, setPlaying, onEnded]);

  // ─────────────────────────────────────────────────────────────────────────
  // Pause when another audio starts
  // ─────────────────────────────────────────────────────────────────────────

  useEffect(() => {
    if (currentPlayingId && currentPlayingId !== id) {
      const audio = localAudioRef.current;
      if (audio && !audio.paused) {
        audio.pause();
      }
    }
  }, [currentPlayingId, id]);

  // ─────────────────────────────────────────────────────────────────────────
  // Cleanup
  // ─────────────────────────────────────────────────────────────────────────

  useEffect(() => {
    return () => {
      const audio = localAudioRef.current;
      if (audio) {
        audio.pause();
        audio.src = '';
        localAudioRef.current = null;
      }
    };
  }, []);

  // ─────────────────────────────────────────────────────────────────────────
  // Return
  // ─────────────────────────────────────────────────────────────────────────

  return {
    isPlaying,
    progress,
    currentTime,
    duration,
    play,
    pause,
    toggle,
    seek,
  };
}
