## User Recording Uploads

Status: current
Last verified: 2025-12-07

← Back to [`docs/postgres/README.md`](README.md)

### Why this exists

Users need to upload audio recordings of their pronunciation for specific cue cards in their learning profiles. This system provides a secure, two-phase upload flow that ensures file metadata is only created after successful upload, maintains proper authorization, and automatically generates time-limited signed URLs for both upload and download operations.

### Role in the system

- Orchestrates multi-phase upload workflow: intent creation → upload → completion.
- Maintains associations between learning profiles, cue cards, and uploaded recordings.
- Generates unique object keys to support multiple recordings per profile/cue combination.
- Provides history retrieval for user recordings with automatic download URL injection.
- Coordinates between database (business logic), gateway (URL injection), and files service (GCS signing).

### How it works

The recording upload system follows a three-phase flow with data transformations at each step:

#### Phase 1: Create Upload Intent

**Client Request:**

```http
POST /rpc/create_recording_upload_intent HTTP/1.1
Authorization: Bearer <jwt_token>
Content-Type: application/json

{
  "profile_id": 2,
  "cue_id": 1,
  "mime_type": "audio/mp4"
}
```

**Database Processing:**

Source: [`postgres/migrations/1756075400_recording_uploads.sql`](../../postgres/migrations/1756075400_recording_uploads.sql) lines 218-270

1. `api.create_recording_upload_intent` validates:
   - User is authenticated (`auth.jwt_account_id()`).
   - Profile exists and belongs to the authenticated user.
   - User owns the profile.

2. `learning.create_recording_upload_intent` validates:
   - Profile exists (via `learning.profile_by_id`).
   - Cue exists and is published (via `cues.cue_info_by_id`).
   - MIME type is `audio/mp4` (only accepted format for recordings).

3. Generates unique object key:
   - Format: `user-recordings/p-{profile_id}-c-{cue_id}-t-{epoch}.{ext}`
   - Example: `user-recordings/p-2-c-1-t-1733569047.m4a`
   - Extension dynamically determined via `files.mime_type_to_extension`.

4. Creates two database records:
   - `files.upload_intent`: stores object key, bucket, mime type, creator.
   - `learning.user_recording_upload_intent`: links intent to profile and cue.

**Database Response:**

```json
{
  "upload_intent_id": 1
}
```

**Gateway Processing:**

Source: [`gateway/internal/files/processor.go`](../../gateway/internal/files/processor.go)

1. Gateway intercepts response with `upload_intent_id` field.
2. Calls files service `POST /signed_upload_url` with:

   ```json
   {
     "upload_intent_id": 1
   }
   ```

3. Files service:
   - Calls `files.lookup_upload_intent(1)` to get upload metadata.
   - Generates GCS signed PUT URL with 15-minute TTL.
   - Returns `{ "upload_url": "<signed_url>" }`.

4. Gateway injects `upload_url` into original response.

**Final Client Response:**

```json
{
  "upload_intent_id": 1,
  "upload_url": "https://storage.googleapis.com/chatterbox-bucket-main/user-recordings/p-2-c-1-t-1733569047.m4a?X-Goog-Algorithm=GOOG4-RSA-SHA256&X-Goog-Credential=...&X-Goog-Expires=900&..."
}
```

#### Phase 2: Upload File to GCS

**Client Request:**

```http
PUT https://storage.googleapis.com/chatterbox-bucket-main/user-recordings/p-2-c-1-t-1733569047.m4a?X-Goog-Algorithm=...
Content-Type: audio/mp4
Content-Length: <file_size>

<binary audio data>
```

**Processing:**

- Direct upload to Google Cloud Storage using signed URL.
- No involvement from database, gateway, or files service.
- Client must include correct `Content-Type` header matching the MIME type from intent creation.

**GCS Response:**

```http
HTTP/1.1 200 OK
```

#### Phase 3: Complete Upload

**Client Request:**

```http
POST /rpc/complete_recording_upload HTTP/1.1
Authorization: Bearer <jwt_token>
Content-Type: application/json

{
  "upload_intent_id": 1,
  "metadata": {
    "name": "Practice pronunciation for 'Hello'"
  }
}
```

**Note:** The `metadata` parameter is optional. Only keys defined in `files.metadata_key` domain are stored (currently: `name`). Invalid keys are silently ignored.

**Database Processing:**

Source: [`postgres/migrations/1756075400_recording_uploads.sql`](../../postgres/migrations/1756075400_recording_uploads.sql) lines 460-502

1. `api.complete_recording_upload` validates:
   - User is authenticated.
   - Accepts optional `metadata` JSON object.

2. `learning.complete_recording_upload` performs:
   - Fetches `files.upload_intent` record.
   - Verifies user created the intent (ownership check).
   - Fetches `learning.user_recording_upload_intent` for metadata.
   - Checks idempotency: if already completed, returns existing record.
   - Creates `files.file` record with bucket, object_key, mime_type.
   - Creates file metadata via `files.create_file_metadata` (filters valid keys only).
   - Creates `learning.profile_cue_recording` linking file to profile and cue.

3. `api.complete_recording_upload` enriches response:
   - Calls `files.file_details` to get full file information with metadata.
   - Returns both full `file` object and `files` array for gateway injection.

**Database Response:**

```json
{
  "success": true,
  "file": {
    "file_id": 5,
    "created_at": "2025-12-07T08:47:27Z",
    "mime_type": "audio/mp4",
    "metadata": {
      "name": "Practice pronunciation for 'Hello'"
    }
  },
  "files": [5]
}
```

**Gateway Processing:**

1. Gateway intercepts response with `files` array.
2. Calls files service `POST /signed_download_url` with:

   ```json
   {
     "files": [5]
   }
   ```

3. Files service generates GCS signed GET URLs.
4. Gateway injects `processed_files` array into response.

**Final Client Response:**

```json
{
  "success": true,
  "file": {
    "file_id": 5,
    "created_at": "2025-12-07T08:47:27Z",
    "mime_type": "audio/mp4",
    "metadata": {
      "name": "Practice pronunciation for 'Hello'"
    }
  },
  "files": [5],
  "processed_files": [
    {
      "file_id": 5,
      "url": "https://storage.googleapis.com/<bucket>/<object_key>?X-Goog-Algorithm=..."
    }
  ]
}
```

#### Phase 4: Retrieve Recording History

**Client Request:**

```http
POST /rpc/get_cue_for_profile HTTP/1.1
Authorization: Bearer <jwt_token>
Content-Type: application/json

{
  "profile_id": 2,
  "cue_id": 1
}
```

**Database Processing:**

Source: [`postgres/migrations/1756075400_recording_uploads.sql`](../../postgres/migrations/1756075400_recording_uploads.sql) lines 495-542

1. `api.get_cue_for_profile` validates:
   - User is authenticated.
   - Profile exists and belongs to user.

2. `learning.cue_with_recordings_for_profile` composes:
   - Cue details via `cues.cue_info_by_id` (with localized content in profile's language).
   - Recording history via `learning.cue_recording_history_for_profile`.

3. `learning.cue_recording_history_for_profile` aggregates:
   - All `profile_cue_recording` records for the profile/cue pair.
   - Each recording includes full row data converted via `to_jsonb(pcr)`.
   - File details nested via `files.file_details(file_id)`.

4. `files.file_details` returns for each file:
   - `file_id`, `created_at`, `mime_type`.
   - `metadata` aggregated from `files.file_metadata` table as key-value object.

5. API extracts file IDs from recordings for gateway injection.

**Database Response:**

```json
{
  "cue": {
    "cue_id": 1,
    "stage": "published",
    "created_at": "2025-12-07T08:00:00Z",
    "created_by": 1,
    "content": {
      "cue_content_id": 1,
      "cue_id": 1,
      "title": "Hello",
      "details": "Say hello in English",
      "language_code": "en",
      "created_at": "2025-12-07T08:00:00Z"
    },
    "recordings": [
      {
        "profile_cue_recording_id": 1,
        "profile_id": 2,
        "cue_id": 1,
        "file_id": 5,
        "created_at": "2025-12-07T08:47:27Z",
        "file": {
          "file_id": 5,
          "created_at": "2025-12-07T08:47:27Z",
          "mime_type": "audio/mp4",
          "metadata": {}
        }
      }
    ]
  },
  "files": [5]
}
```

**Gateway Processing:**

1. Gateway intercepts `files` array.
2. Generates signed download URLs for each file.
3. Injects `processed_files` into response.

**Final Client Response:**

```json
{
  "cue": {
    "cue_id": 1,
    "stage": "published",
    "content": {
      "title": "Hello",
      "details": "Say hello in English",
      "language_code": "en"
    },
    "recordings": [
      {
        "profile_cue_recording_id": 1,
        "profile_id": 2,
        "cue_id": 1,
        "file_id": 5,
        "created_at": "2025-12-07T08:47:27Z",
        "file": {
          "file_id": 5,
          "created_at": "2025-12-07T08:47:27Z",
          "mime_type": "audio/mp4",
          "metadata": {}
        }
      }
    ]
  },
  "files": [5],
  "processed_files": [
    {
      "file_id": 5,
      "url": "https://storage.googleapis.com/<bucket>/<object_key>?X-Goog-Algorithm=..."
    }
  ]
}
```

### Database Schema

Source: [`postgres/migrations/1756075400_recording_uploads.sql`](../../postgres/migrations/1756075400_recording_uploads.sql)

#### Tables

**`files.upload_intent`** (lines 5-12)

Stores pending upload requests with generated object keys.

- `upload_intent_id` bigserial primary key
- `object_key` text unique (GCS object path)
- `bucket` text (GCS bucket name)
- `mime_type` files.mime_type
- `created_at` timestamp with time zone
- `created_by` bigint references accounts.account

**`learning.user_recording_upload_intent`** (lines 15-21)

Links upload intents to specific profiles and cues.

- `user_recording_upload_intent_id` bigserial primary key
- `upload_intent_id` bigint unique references files.upload_intent
- `profile_id` bigint references learning.profile
- `cue_id` bigint references cues.cue
- `created_at` timestamp with time zone

**`learning.profile_cue_recording`** (lines 24-30)

Associates uploaded files with learning profiles and cues.

- `profile_cue_recording_id` bigserial primary key
- `profile_id` bigint references learning.profile
- `cue_id` bigint references cues.cue
- `file_id` bigint references files.file
- `created_at` timestamp with time zone

#### Key Functions

**Helper Functions:**

- `files.mime_type_to_extension(_mime_type)` (lines 33-46): Converts MIME types to file extensions.
- `files.generate_user_recording_object_key(_profile_id, _cue_id, _mime_type)` (lines 49-67): Generates unique GCS object keys.
- `files.lookup_upload_intent(_upload_intent_id)` (lines 70-86): Retrieves intent metadata for files service.
- `cues.cue_info_by_id(_cue_id, _include_content, _language_code)` (lines 91-123): Fetches cue with optional localized content.
- `files.file_details(_file_id)` (lines 291-314): Returns UI-friendly file metadata with aggregated key-value metadata.
- `files.create_file_metadata(_file_id, _metadata)` (lines 316-352): Creates file metadata records from JSON, filtering only valid keys.

**Business Logic:**

- `learning.create_recording_upload_intent(...)` (lines 126-216): Creates upload intent with validation.
- `learning.complete_recording_upload(...)` (lines 354-431): Completes upload, creates file/metadata/recording records.
- `learning.profile_cue_recording_by_upload_intent(...)` (lines 273-289): Idempotency check for completion.
- `learning.cue_recording_history_for_profile(...)` (lines 504-526): Aggregates recording history with file details.
- `learning.cue_with_recordings_for_profile(...)` (lines 528-544): Composes cue with recordings.

**API Endpoints:**

- `api.create_recording_upload_intent(profile_id, cue_id, mime_type)` (lines 219-270): Public endpoint for intent creation.
- `api.complete_recording_upload(upload_intent_id, metadata)` (lines 460-502): Public endpoint for upload completion with optional metadata.
- `api.get_cue_for_profile(profile_id, cue_id)` (lines 546-592): Public endpoint for cue with recording history.

### Data Transformations

#### Object Key Generation

Input: `profile_id=2`, `cue_id=1`, `mime_type='audio/mp4'`

Transformation:
1. Prefix: `user-recordings/`
2. Profile identifier: `p-2`
3. Cue identifier: `-c-1`
4. Timestamp: `-t-1733569047` (epoch seconds)
5. Extension: `.m4a` (from `mime_type_to_extension`)

Output: `user-recordings/p-2-c-1-t-1733569047.m4a`

#### File Metadata Aggregation

Input: `file_id=5` with metadata rows:
- `{ key: 'name', value: '"My Recording"' }`

Transformation via `jsonb_object_agg(fm.key, fm.value)`:

Output:
```json
{
  "file_id": 5,
  "created_at": "2025-12-07T08:47:27Z",
  "mime_type": "audio/mp4",
  "metadata": {
    "name": "My Recording"
  }
}
```

#### Recording History Aggregation

Input: Multiple `profile_cue_recording` rows for profile 2, cue 1.

Transformation:
1. `to_jsonb(pcr)` converts row to JSON object.
2. Merges with `files.file_details(pcr.file_id)` nested under `file` key.
3. `jsonb_agg(... order by created_at desc)` aggregates newest first.

Output: Array of recording objects with nested file details.

### Authorization Model

- **Intent Creation**: Requires authenticated user who owns the target profile.
- **Upload Completion**: Requires authenticated user who created the upload intent.
- **History Retrieval**: Requires authenticated user who owns the target profile.
- All checks enforce row-level ownership via `account_id` comparisons.

### Idempotency

- **Upload Completion**: Checks if `profile_cue_recording` already exists for the object key before creating new records. Returns existing record if found.
- **Intent Creation**: Not idempotent; creates new intent each time (supports multiple recordings per cue).

### File Metadata

Clients can attach metadata to files during upload completion. Metadata is stored as key-value pairs in the `files.file_metadata` table.

**Supported Metadata Keys:**

Currently defined in `files.metadata_key` domain (see [`postgres/migrations/1756075300_files_service.sql`](../../postgres/migrations/1756075300_files_service.sql)):

- `name` (text): Human-readable name for the file

**Adding Metadata:**

Metadata is provided as a JSON object in the `metadata` parameter of `api.complete_recording_upload`:

```json
{
  "upload_intent_id": 1,
  "metadata": {
    "name": "Practice pronunciation for 'Hello'",
    "invalid_key": "this will be ignored"
  }
}
```

**Behavior:**

- Only keys defined in `files.metadata_key` are stored.
- Invalid keys are silently ignored (no error).
- Metadata is optional; can be omitted entirely.
- Uses upsert logic: `on conflict (file_id, key) do update`.

**To Add New Metadata Keys:**

Update the `files.metadata_key` domain:

```sql
create domain files.metadata_key as text
    check (value in ('name', 'duration', 'size', ...));
```

### Supported MIME Types

Currently restricted to `audio/mp4` for recordings. Extensions via `files.mime_type_to_extension`:

- `audio/mp4` → `m4a`
- `image/jpeg` → `jpg`
- `image/png` → `png`
- Unknown → `bin`

### Gateway Integration

Source: [`gateway/internal/files/processor.go`](../../gateway/internal/files/processor.go)

The gateway performs two types of URL injection:

1. **Upload URL Injection** (`InjectSignedUploadURL`):
   - Detects `upload_intent_id` in response.
   - Calls files service `/signed_upload_url`.
   - Injects `upload_url` field with signed PUT URL.

2. **Download URL Injection** (`InjectSignedFileURLs`):
   - Detects `files` array in response.
   - Calls files service `/signed_download_url`.
   - Injects `processed_files` array with signed GET URLs.

Configuration (see [`gateway/internal/config/config.go`](../../gateway/internal/config/config.go)):
- `UPLOAD_INTENT_FIELD_NAME`: Field name to detect (default: `upload_intent_id`)
- `UPLOAD_URL_FIELD_NAME`: Field name to inject (default: `upload_url`)
- `FILES_FIELD_NAME`: Field name to detect (default: `files`)
- `PROCESSED_FILES_FIELD_NAME`: Field name to inject (default: `processed_files`)

### Files Service Integration

Source: [`files/internal/httpserver/server.go`](../../files/internal/httpserver/server.go)

Two endpoints support the recording flow:

1. **`POST /signed_upload_url`** (`SignedUploadURLHandler`):
   - Accepts: `{ "upload_intent_id": <number> }`
   - Calls: `files.lookup_upload_intent(bigint)`
   - Generates: GCS signed PUT URL with Content-Type header
   - Returns: `{ "upload_url": "<signed_url>" }`

2. **`POST /signed_download_url`** (`SignedDownloadURLHandler`):
   - Accepts: `{ "files": [<numbers>] }`
   - Calls: `files.lookup_files(bigint[])`
   - Generates: GCS signed GET URLs
   - Returns: `[{ "file_id": <id>, "url": "<signed_url>" }]`

Both endpoints:
- Require `X-File-Service-Api-Key` header for authentication.
- Generate V4 signed URLs with configurable TTL (default 15 minutes).
- Use service account credentials for signing.

### Operations

#### Environment Variables

**Database** (via migrations):
- `GCS_CHATTERBOX_BUCKET`: GCS bucket name for file storage.

**Files Service**:
- `GCS_CHATTERBOX_BUCKET_SERVICE_ACCOUNT_EMAIL`: Service account email.
- `GCS_CHATTERBOX_BUCKET_SERVICE_ACCOUNT_PRIVATE_KEY`: Service account private key.
- `GCS_CHATTERBOX_BUCKET`: Bucket name.
- `GCS_CHATTERBOX_SIGNED_URL_TTL_SECONDS`: TTL for signed URLs (e.g., `900`).
- `FILE_SERVICE_API_KEY`: Shared secret for gateway authentication.

**Gateway**:
- `FILE_SERVICE_URL`: URL of files service.
- `FILE_SIGNED_UPLOAD_URL_PATH`: Path for upload URL endpoint (e.g., `/signed_upload_url`).
- `FILE_SIGNED_DOWNLOAD_URL_PATH`: Path for download URL endpoint (e.g., `/signed_download_url`).
- `UPLOAD_INTENT_FIELD_NAME`: Field name for upload intent detection.
- `UPLOAD_URL_FIELD_NAME`: Field name for upload URL injection.
- `FILES_FIELD_NAME`: Field name for files array detection.
- `PROCESSED_FILES_FIELD_NAME`: Field name for processed files injection.
- `FILE_SERVICE_API_KEY`: Shared secret for files service authentication.

### Examples

#### Complete Upload Flow

1. Create intent:

```bash
curl -X POST https://api.chatterbox.app/rpc/create_recording_upload_intent \
  -H "Authorization: Bearer <jwt>" \
  -H "Content-Type: application/json" \
  -d '{"profile_id": 2, "cue_id": 1, "mime_type": "audio/mp4"}'
```

Response:
```json
{
  "upload_intent_id": 1,
  "upload_url": "https://storage.googleapis.com/chatterbox-bucket-main/user-recordings/p-2-c-1-t-1733569047.m4a?..."
}
```

2. Upload file:

```bash
curl -X PUT "https://storage.googleapis.com/chatterbox-bucket-main/user-recordings/p-2-c-1-t-1733569047.m4a?..." \
  -H "Content-Type: audio/mp4" \
  --data-binary @recording.m4a
```

3. Complete upload (with metadata):

```bash
curl -X POST https://api.chatterbox.app/rpc/complete_recording_upload \
  -H "Authorization: Bearer <jwt>" \
  -H "Content-Type: application/json" \
  -d '{"upload_intent_id": 1, "metadata": {"name": "Practice pronunciation"}}'
```

Response:
```json
{
  "success": true,
  "file": {
    "file_id": 5,
    "created_at": "2025-12-07T08:47:27Z",
    "mime_type": "audio/mp4",
    "metadata": {
      "name": "Practice pronunciation"
    }
  },
  "files": [5],
  "processed_files": [
    {
      "file_id": 5,
      "url": "https://storage.googleapis.com/..."
    }
  ]
}
```

4. Get recording history:

```bash
curl -X POST https://api.chatterbox.app/rpc/get_cue_for_profile \
  -H "Authorization: Bearer <jwt>" \
  -H "Content-Type: application/json" \
  -d '{"profile_id": 2, "cue_id": 1}'
```

### Error Handling

Common validation failures returned as exceptions with hints:

- `profile_not_found`: Profile does not exist.
- `unauthorized_to_create_recording_upload_intent`: User does not own profile.
- `cue_not_found_or_not_published`: Cue does not exist or is not published.
- `invalid_mime_type_for_recording`: Only `audio/mp4` is accepted.
- `upload_intent_not_found`: Upload intent does not exist.
- `unauthorized_to_complete_upload`: User did not create the intent.
- `unauthorized_to_get_cue_for_profile`: User does not own the profile.

### Future

- Support additional audio MIME types (e.g., `audio/webm`, `audio/wav`).
- Add file size limits and validation.
- Implement automatic transcription via worker tasks.
- Add pronunciation scoring via machine learning integration.

### See also

- Files service: [`../files/README.md`](../files/README.md)
- Gateway file injection: [`../gateway/files-injection.md`](../gateway/files-injection.md)
- File service schema: [`../../postgres/migrations/1756075300_files_service.sql`](../../postgres/migrations/1756075300_files_service.sql)
- Recording uploads migration: [`../../postgres/migrations/1756075400_recording_uploads.sql`](../../postgres/migrations/1756075400_recording_uploads.sql)

