/**
 * Base API client with authentication handling
 * Handles snake_case <-> camelCase conversion like iOS
 */

import { getTokens, setTokens, clearTokens } from '../lib/storage';
import { API_BASE_URL } from '../lib/constants';

// ═══════════════════════════════════════════════════════════════════════════
// TYPES
// ═══════════════════════════════════════════════════════════════════════════

interface ApiRequestOptions extends Omit<RequestInit, 'body'> {
  body?: unknown;
  requiresAuth?: boolean;
}

// ═══════════════════════════════════════════════════════════════════════════
// ERROR CLASS
// ═══════════════════════════════════════════════════════════════════════════

export class ApiError extends Error {
  constructor(
    public status: number,
    message: string,
    public code?: string,
    public hint?: string
  ) {
    super(message);
    this.name = 'ApiError';
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// CASE CONVERSION UTILITIES
// ═══════════════════════════════════════════════════════════════════════════

/**
 * Convert camelCase to snake_case
 */
function toSnakeCase(str: string): string {
  return str.replace(/[A-Z]/g, (letter) => `_${letter.toLowerCase()}`);
}

/**
 * Convert snake_case to camelCase
 */
function toCamelCase(str: string): string {
  return str.replace(/_([a-z])/g, (_, letter) => letter.toUpperCase());
}

/**
 * Recursively convert object keys from camelCase to snake_case
 */
function convertKeysToSnakeCase(obj: unknown): unknown {
  if (obj === null || obj === undefined) {
    return obj;
  }
  
  if (Array.isArray(obj)) {
    return obj.map(convertKeysToSnakeCase);
  }
  
  if (typeof obj === 'object') {
    const converted: Record<string, unknown> = {};
    for (const [key, value] of Object.entries(obj as Record<string, unknown>)) {
      converted[toSnakeCase(key)] = convertKeysToSnakeCase(value);
    }
    return converted;
  }
  
  return obj;
}

/**
 * Recursively convert object keys from snake_case to camelCase
 */
function convertKeysToCamelCase(obj: unknown): unknown {
  if (obj === null || obj === undefined) {
    return obj;
  }
  
  if (Array.isArray(obj)) {
    return obj.map(convertKeysToCamelCase);
  }
  
  if (typeof obj === 'object') {
    const converted: Record<string, unknown> = {};
    for (const [key, value] of Object.entries(obj as Record<string, unknown>)) {
      converted[toCamelCase(key)] = convertKeysToCamelCase(value);
    }
    return converted;
  }
  
  return obj;
}

// ═══════════════════════════════════════════════════════════════════════════
// LOGOUT EVENT
// ═══════════════════════════════════════════════════════════════════════════

/**
 * Dispatch a custom event to trigger logout across the app
 * Components can listen for this event via window.addEventListener('auth:logout', handler)
 */
function dispatchLogoutEvent(): void {
  window.dispatchEvent(new CustomEvent('auth:logout'));
}

// ═══════════════════════════════════════════════════════════════════════════
// API REQUEST
// ═══════════════════════════════════════════════════════════════════════════

async function request<T>(
  endpoint: string,
  options: ApiRequestOptions = {}
): Promise<T> {
  const { body, requiresAuth = true, headers: customHeaders, ...fetchOptions } = options;
  
  // Build headers
  const headers: HeadersInit = {
    'Content-Type': 'application/json',
    'Accept': 'application/json',
    ...customHeaders,
  };
  
  // Add auth headers if required
  if (requiresAuth) {
    const { accessToken, refreshToken } = getTokens();
    if (accessToken) {
      (headers as Record<string, string>)['Authorization'] = `Bearer ${accessToken}`;
    }
    if (refreshToken) {
      (headers as Record<string, string>)['X-Refresh-Token'] = refreshToken;
    }
  }
  
  // Convert body keys to snake_case before sending
  const convertedBody = body ? convertKeysToSnakeCase(body) : undefined;
  
  // Make request
  const response = await fetch(`${API_BASE_URL}${endpoint}`, {
    ...fetchOptions,
    headers,
    body: convertedBody ? JSON.stringify(convertedBody) : undefined,
  });
  
  // Handle token refresh (gateway returns new tokens in headers)
  const newAccessToken = response.headers.get('X-New-Access-Token');
  const newRefreshToken = response.headers.get('X-New-Refresh-Token');
  if (newAccessToken && newRefreshToken) {
    setTokens(newAccessToken, newRefreshToken);
  }
  
  // Handle 401 - trigger logout
  if (response.status === 401) {
    clearTokens();
    dispatchLogoutEvent();
    throw new ApiError(401, 'Session expired');
  }
  
  // Handle other errors
  if (!response.ok) {
    let errorMessage = 'Request failed';
    let errorCode: string | undefined;
    let errorHint: string | undefined;
    
    try {
      const errorData = await response.json();
      // PostgREST error format: { message, detail, hint, code }
      errorMessage = errorData.message || errorData.detail || errorMessage;
      errorCode = errorData.code;
      errorHint = errorData.hint;
    } catch {
      // Failed to parse error response, use default message
    }
    
    throw new ApiError(response.status, errorMessage, errorCode, errorHint);
  }
  
  // Parse response
  const text = await response.text();
  if (!text) {
    return {} as T;
  }
  
  try {
    const parsed = JSON.parse(text);
    // Convert response keys to camelCase
    return convertKeysToCamelCase(parsed) as T;
  } catch {
    return {} as T;
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// API CLIENT
// ═══════════════════════════════════════════════════════════════════════════

export const apiClient = {
  /**
   * Make a GET request
   */
  get: <T>(endpoint: string, options?: ApiRequestOptions) =>
    request<T>(endpoint, { ...options, method: 'GET' }),
  
  /**
   * Make a POST request
   */
  post: <T>(endpoint: string, body?: unknown, options?: ApiRequestOptions) =>
    request<T>(endpoint, { ...options, method: 'POST', body }),
  
  /**
   * Make a PUT request
   */
  put: <T>(endpoint: string, body?: unknown, options?: ApiRequestOptions) =>
    request<T>(endpoint, { ...options, method: 'PUT', body }),
  
  /**
   * Make a DELETE request
   */
  delete: <T>(endpoint: string, options?: ApiRequestOptions) =>
    request<T>(endpoint, { ...options, method: 'DELETE' }),
};

// ═══════════════════════════════════════════════════════════════════════════
// RAW FETCH (for file uploads)
// ═══════════════════════════════════════════════════════════════════════════

/**
 * Upload a file directly to a signed URL (GCS)
 * This bypasses the API client since it goes directly to storage
 */
export async function uploadToSignedUrl(
  signedUrl: string,
  file: Blob,
  contentType: string
): Promise<void> {
  const response = await fetch(signedUrl, {
    method: 'PUT',
    headers: {
      'Content-Type': contentType,
    },
    body: file,
  });
  
  if (!response.ok) {
    throw new ApiError(response.status, 'Failed to upload file');
  }
}
