/**
 * Recording types
 * Matches PostgREST RPC response shapes
 */

import type { CueContent } from './cue';

// ═══════════════════════════════════════════════════════════════════════════
// FILE INFO
// ═══════════════════════════════════════════════════════════════════════════

export interface FileMetadata {
  name?: string;
  duration?: string;
  [key: string]: string | undefined;
}

export interface FileInfo {
  fileId: number;
  createdAt: string;
  mimeType: string;
  metadata: FileMetadata;
}

export interface ProcessedFile {
  fileId: number;
  url: string;
}

// ═══════════════════════════════════════════════════════════════════════════
// EVALUATION
// ═══════════════════════════════════════════════════════════════════════════

export type EvaluationStatus = 'none' | 'processing' | 'ready';

export interface GrammarMistake {
  original: string;
  correction: string;
  explanation: string;
}

export interface UnnaturalPhrase {
  phrase: string;
  naturalReplacement: string;
  explanation: string;
}

export interface UnnaturalWord {
  word: string;
  betterWord: string;
  explanation: string;
}

export interface EvaluationResult {
  cefrLevel: string;
  summary: string;
  strengths: string[];
  improvementAreas: string[];
  recommendedNextSteps: string[];
  grammarMistakes: GrammarMistake[];
  unnaturalPhrases: UnnaturalPhrase[];
  unnaturalWords: UnnaturalWord[];
  improvedVersion: string;
  createdAt: string;
}

export interface RecordingEvaluation {
  status: EvaluationStatus;
  result: EvaluationResult | null;
}

// ═══════════════════════════════════════════════════════════════════════════
// REPORT
// ═══════════════════════════════════════════════════════════════════════════

export type ReportStatus = 'none' | 'processing' | 'ready';

export interface RecordingReport {
  status: ReportStatus;
  transcript: string | null;
  evaluation: RecordingEvaluation;
}

// ═══════════════════════════════════════════════════════════════════════════
// RECORDING CUE (simplified cue in recording context)
// ═══════════════════════════════════════════════════════════════════════════

export interface RecordingCue {
  cueId: number;
  stage: string;
  createdAt: string;
  createdBy: number;
  content: CueContent;
}

// ═══════════════════════════════════════════════════════════════════════════
// RECORDING
// ═══════════════════════════════════════════════════════════════════════════

export interface Recording {
  profileCueRecordingId: number;
  profileId: number;
  cueId: number;
  fileId: number;
  createdAt: string;
  file: FileInfo;
  cue: RecordingCue;
  report: RecordingReport;
}

// ═══════════════════════════════════════════════════════════════════════════
// CUE RECORDING (recording in cue context)
// ═══════════════════════════════════════════════════════════════════════════

export interface CueRecording {
  profileCueRecordingId: number;
  profileId: number;
  cueId: number;
  fileId: number;
  createdAt: string;
  file: FileInfo;
  report: RecordingReport;
}

// ═══════════════════════════════════════════════════════════════════════════
// RECORDING HISTORY RESPONSE
// ═══════════════════════════════════════════════════════════════════════════

export interface RecordingHistoryResponse {
  recordings: Recording[];
  files: number[];
  processedFiles?: ProcessedFile[];
}

// ═══════════════════════════════════════════════════════════════════════════
// API REQUESTS
// ═══════════════════════════════════════════════════════════════════════════

export interface CreateUploadIntentRequest {
  profileId: number;
  cueId: number;
  mimeType: string;
}

export interface CompleteUploadRequest {
  uploadIntentId: number;
  metadata?: Record<string, string> | null;
}

export interface RequestTranscriptionRequest {
  profileCueRecordingId: number;
}

// ═══════════════════════════════════════════════════════════════════════════
// API RESPONSES
// ═══════════════════════════════════════════════════════════════════════════

export interface CreateUploadIntentResponse {
  uploadIntentId: number;
  uploadUrl: string;
}

export interface CompleteUploadResponse {
  success: boolean;
  file: FileInfo;
  files: number[];
  processedFiles: ProcessedFile[];
}

export interface TranscriptionRequestResponse {
  status: 'started' | 'in_progress' | 'already_transcribed';
  recordingTranscriptionTaskId?: number;
}

export interface RequestEvaluationRequest {
  profileCueRecordingId: number;
}

export interface EvaluationRequestResponse {
  status: 'started' | 'in_progress' | 'already_evaluated' | 'transcript_not_ready';
  recordingEvaluationTaskId?: number;
}

// ═══════════════════════════════════════════════════════════════════════════
// RECORDER STATE (UI state for recording component)
// ═══════════════════════════════════════════════════════════════════════════

export type RecorderState = 'idle' | 'recording' | 'paused' | 'stopped';
