package sms

import (
	"context"
	"fmt"
	"log"

	"github.com/bencyrus/chatterbox/shared/logger"
	"github.com/bencyrus/chatterbox/worker/internal/types"
)

type Service struct{}

type SMSResponse struct {
	MessageID string `json:"message_id"`
	Status    string `json:"status"`
}

func NewService() *Service {
	return &Service{}
}

// SendSMS simulates sending an SMS by logging it to console
func (s *Service) SendSMS(ctx context.Context, payload *types.SMSPayload) (*SMSResponse, error) {
	if payload == nil {
		return nil, fmt.Errorf("sms payload is nil")
	}

	logger.Info(ctx, "sending SMS", logger.Fields{
		"message_id": payload.MessageID,
		"to_number":  payload.ToNumber,
		"body":       payload.Body,
	})

	// Log the SMS to console for now
	log.Printf("📱 SMS TO: %s\n", payload.ToNumber)
	log.Printf("📱 SMS BODY: %s\n", payload.Body)
	log.Printf("📱 SMS MESSAGE ID: %d\n", payload.MessageID)
	log.Println("📱 SMS SENT SUCCESSFULLY (simulated)")

	// Return a simulated response
	response := &SMSResponse{
		MessageID: fmt.Sprintf("sms_%d", payload.MessageID),
		Status:    "sent",
	}

	logger.Info(ctx, "SMS sent successfully", logger.Fields{
		"message_id":   payload.MessageID,
		"simulated_id": response.MessageID,
		"status":       response.Status,
	})

	return response, nil
}
