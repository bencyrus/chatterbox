package types

// EmailPayload represents the payload structure for email tasks.
type EmailPayload struct {
	MessageID   int64  `json:"message_id"`
	FromAddress string `json:"from_address"`
	ToAddress   string `json:"to_address"`
	Subject     string `json:"subject"`
	HTML        string `json:"html"`
}
