package logger

import (
	"context"
	"encoding/json"
	"log"
	"os"
	"time"
)

type Logger struct {
	serviceName string
}

type LogEntry struct {
	Timestamp time.Time `json:"timestamp"`
	Level     string    `json:"level"`
	Service   string    `json:"service"`
	RequestID string    `json:"request_id,omitempty"`
	Message   string    `json:"message"`
	Error     string    `json:"error,omitempty"`
	Fields    Fields    `json:"fields,omitempty"`
}

type Fields map[string]any

// Context key for request ID
type contextKey string

const RequestIDKey contextKey = "request_id"

// Global logger instance
var defaultLogger *Logger

func Init(serviceName string) {
	defaultLogger = &Logger{serviceName: serviceName}
}

func (l *Logger) log(level string, ctx context.Context, message string, err error, fields Fields) {
	entry := LogEntry{
		Timestamp: time.Now().UTC(),
		Level:     level,
		Service:   l.serviceName,
		Message:   message,
		Fields:    fields,
	}

	// Extract request ID from context if available
	if ctx != nil {
		if requestID, ok := ctx.Value(RequestIDKey).(string); ok && requestID != "" {
			entry.RequestID = requestID
		}
	}

	// Add error if provided
	if err != nil {
		entry.Error = err.Error()
	}

	// Marshal to JSON and output
	jsonData, marshalErr := json.Marshal(entry)
	if marshalErr != nil {
		// Fallback to standard log if JSON marshaling fails
		log.Printf("JSON marshal error: %v, original message: %s", marshalErr, message)
		return
	}

	// Output to stdout (which will be captured by Docker/Datadog)
	os.Stdout.Write(jsonData)
	os.Stdout.WriteString("\n")
}

// Package-level convenience functions using the default logger
func Info(ctx context.Context, message string, fields ...Fields) {
	if defaultLogger == nil {
		log.Printf("Logger not initialized, falling back to standard log: %s", message)
		return
	}
	var f Fields
	if len(fields) > 0 {
		f = fields[0]
	}
	defaultLogger.log("info", ctx, message, nil, f)
}

func Error(ctx context.Context, message string, err error, fields ...Fields) {
	if defaultLogger == nil {
		log.Printf("Logger not initialized, falling back to standard log: %s, error: %v", message, err)
		return
	}
	var f Fields
	if len(fields) > 0 {
		f = fields[0]
	}
	defaultLogger.log("error", ctx, message, err, f)
}

func Warn(ctx context.Context, message string, fields ...Fields) {
	if defaultLogger == nil {
		log.Printf("Logger not initialized, falling back to standard log: %s", message)
		return
	}
	var f Fields
	if len(fields) > 0 {
		f = fields[0]
	}
	defaultLogger.log("warn", ctx, message, nil, f)
}

func Debug(ctx context.Context, message string, fields ...Fields) {
	if defaultLogger == nil {
		log.Printf("Logger not initialized, falling back to standard log: %s", message)
		return
	}
	var f Fields
	if len(fields) > 0 {
		f = fields[0]
	}
	defaultLogger.log("debug", ctx, message, nil, f)
}

// WithRequestID adds a request ID to the context
func WithRequestID(ctx context.Context, requestID string) context.Context {
	return context.WithValue(ctx, RequestIDKey, requestID)
}
