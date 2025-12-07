package database

import (
	"context"
	"database/sql"
	"encoding/json"
	"fmt"
	"strconv"
	"strings"

	filetypes "github.com/bencyrus/chatterbox/files/internal/types"
	_ "github.com/lib/pq"
)

// Client wraps a sql.DB for the files service.
type Client struct {
	db *sql.DB
}

// NewClient initializes a database connection for the files service.
func NewClient(databaseURL string) (*Client, error) {
	db, err := sql.Open("postgres", databaseURL)
	if err != nil {
		return nil, fmt.Errorf("failed to open database: %w", err)
	}
	if err := db.Ping(); err != nil {
		return nil, fmt.Errorf("failed to ping database: %w", err)
	}
	return &Client{db: db}, nil
}

// Close closes the underlying database connection.
func (c *Client) Close() error {
	return c.db.Close()
}

// LookupFiles calls files.lookup_files(bigint[]) and returns the result as a slice of FileMetadata.
func (c *Client) LookupFiles(ctx context.Context, ids []int64) ([]filetypes.FileMetadata, error) {
	const query = `select * from files.lookup_files($1::bigint[])`

	// Format the IDs as a PostgreSQL array literal, e.g. "{1,2,3}".
	parts := make([]string, len(ids))
	for i, id := range ids {
		parts[i] = strconv.FormatInt(id, 10)
	}
	arrayLiteral := "{" + strings.Join(parts, ",") + "}"

	var raw []byte
	if err := c.db.QueryRowContext(ctx, query, arrayLiteral).Scan(&raw); err != nil {
		return nil, fmt.Errorf("query lookup_files: %w", err)
	}

	var out []filetypes.FileMetadata
	if err := json.Unmarshal(raw, &out); err != nil {
		return nil, fmt.Errorf("unmarshal lookup_files result: %w", err)
	}
	return out, nil
}
