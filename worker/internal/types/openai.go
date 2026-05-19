package types

import "encoding/json"

// OpenAIResponseCreatePayload is prepared by a DB before_handler for
// openai_response_create tasks.
type OpenAIResponseCreatePayload struct {
	OpenAIResponseAttemptID int64           `json:"openai_response_attempt_id"`
	RequestBody             json.RawMessage `json:"request_body"`
}

// OpenAIResponseCreateResult is recorded by the DB success_handler after
// successfully creating a background response.
type OpenAIResponseCreateResult struct {
	OpenAIResponseID string          `json:"openai_response_id"`
	Status           string          `json:"status,omitempty"`
	ResponseBody     json.RawMessage `json:"response_body"`
}

// OpenAIResponseRetrievePayload is prepared by a DB before_handler for
// openai_response_retrieve tasks.
type OpenAIResponseRetrievePayload struct {
	OpenAIResponseAttemptID int64  `json:"openai_response_attempt_id"`
	OpenAIResponseID        string `json:"openai_response_id"`
}

// OpenAIResponseRetrieveResult is recorded by the DB success_handler after
// retrieving the canonical response body.
type OpenAIResponseRetrieveResult struct {
	OpenAIResponseID string          `json:"openai_response_id"`
	Status           string          `json:"status,omitempty"`
	ResponseBody     json.RawMessage `json:"response_body"`
}
