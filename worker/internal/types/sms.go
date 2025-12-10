package types

// SMSPayload represents the payload structure for SMS tasks.
type SMSPayload struct {
	MessageID int64  `json:"message_id"`
	ToNumber  string `json:"to_number"`
	Body      string `json:"body"`
}
