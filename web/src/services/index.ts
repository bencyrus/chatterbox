/**
 * Services barrel export
 */

export { apiClient, ApiError, uploadToSignedUrl } from './api';
export { authApi, requestMagicLink, loginWithMagicToken, me, appConfig } from './auth';
export { accountApi, logout, requestAccountDeletion } from './account';
export { cuesApi, getCues, shuffleCues, getCueForProfile } from './cues';
export { recordingsApi, getProfileRecordingHistory, createUploadIntent, completeUpload, requestTranscription } from './recordings';
export { profilesApi, setActiveProfile, getOrCreateProfile } from './profiles';
