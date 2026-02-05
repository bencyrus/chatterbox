/**
 * Cue types
 * Matches PostgREST RPC response shapes
 */

// ═══════════════════════════════════════════════════════════════════════════
// CUE CONTENT
// ═══════════════════════════════════════════════════════════════════════════

export interface CueContent {
  cueContentId: number;
  cueId: number;
  title: string;
  details: string;
  languageCode: string;
  createdAt: string;
}

// ═══════════════════════════════════════════════════════════════════════════
// CUE
// ═══════════════════════════════════════════════════════════════════════════

export interface Cue {
  cueId: number;
  stage: string;
  createdAt: string;
  createdBy: number;
  content: CueContent;
}

// ═══════════════════════════════════════════════════════════════════════════
// CUE WITH RECORDINGS (from get_cue_for_profile)
// ═══════════════════════════════════════════════════════════════════════════

export interface CueWithRecordings {
  cueId: number;
  stage: string;
  createdAt: string;
  createdBy: number;
  content: CueContent;
  recordings: CueRecording[] | null;
}

export interface CueWithRecordingsResponse {
  cue: CueWithRecordings | null;
  files: number[];
  processedFiles?: ProcessedFile[];
}

// Import from recording types for CueRecording
import type { CueRecording, ProcessedFile } from './recording';

// ═══════════════════════════════════════════════════════════════════════════
// API REQUESTS
// ═══════════════════════════════════════════════════════════════════════════

export interface GetCuesRequest {
  profileId: number;
  count?: number;
}

export interface ShuffleCuesRequest {
  profileId: number;
  count?: number;
}

export interface GetCueForProfileRequest {
  profileId: number;
  cueId: number;
}
