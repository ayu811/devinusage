package devinusage

import (
	"encoding/json"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"strconv"
	"strings"
	"time"
)

// UsageRecord represents one model inference event extracted from the Devin CLI DB.
type UsageRecord struct {
	SessionID           string
	SessionTitle        string
	SessionModel        string
	Timestamp           time.Time
	Model               string
	InputTokens         int64
	OutputTokens        int64
	CacheReadTokens     int64
	CacheCreationTokens int64
}

func DefaultDBPath() string {
	home, err := os.UserHomeDir()
	if err != nil {
		return ""
	}
	return filepath.Join(home, ".local", "share", "devin", "cli", "sessions.db")
}

func ReadUsageRecords(dbPath string, since, until time.Time) ([]UsageRecord, error) {
	if dbPath == "" {
		dbPath = DefaultDBPath()
	}

	if _, err := os.Stat(dbPath); err != nil {
		return nil, fmt.Errorf("database not found: %w", err)
	}

	if _, err := exec.LookPath("sqlite3"); err != nil {
		return nil, fmt.Errorf("sqlite3 command not found in PATH; install SQLite to use this tool")
	}

	query := `
		WITH deduped AS (
			SELECT
				m.session_id AS session_id,
				m.created_at AS created_at,
				m.chat_message AS chat_message,
				ROW_NUMBER() OVER (
					PARTITION BY json_extract(m.chat_message, '$.message_id')
					ORDER BY m.row_id DESC
				) AS rn
			FROM message_nodes m
			WHERE json_extract(m.chat_message, '$.role') = 'assistant'
			  AND json_extract(m.chat_message, '$.metadata.metrics') IS NOT NULL
		)
		SELECT
			m.session_id AS session_id,
			s.title AS title,
			s.model AS session_model,
			m.created_at AS created_at,
			json_extract(m.chat_message, '$.metadata.generation_model') AS model,
			json_extract(m.chat_message, '$.metadata.metrics') AS metrics_json
		FROM deduped m
		JOIN sessions s ON m.session_id = s.id
		WHERE m.rn = 1
	`
	if !since.IsZero() {
		query += " AND m.created_at >= " + strconv.FormatInt(since.Unix(), 10)
	}
	if !until.IsZero() {
		query += " AND m.created_at <= " + strconv.FormatInt(until.Unix(), 10)
	}
	query += " ORDER BY m.created_at"

	cmd := exec.Command("sqlite3", "-json", dbPath, query)
	out, err := cmd.Output()
	if err != nil {
		if exitErr, ok := err.(*exec.ExitError); ok && len(exitErr.Stderr) > 0 {
			return nil, fmt.Errorf("sqlite3 error: %s", strings.TrimSpace(string(exitErr.Stderr)))
		}
		return nil, fmt.Errorf("run sqlite3: %w", err)
	}

	if len(out) == 0 {
		return []UsageRecord{}, nil
	}

	var rows []struct {
		SessionID    string `json:"session_id"`
		Title        string `json:"title"`
		SessionModel string `json:"session_model"`
		CreatedAt    int64  `json:"created_at"`
		Model        string `json:"model"`
		MetricsJSON  string `json:"metrics_json"`
	}
	if err := json.Unmarshal(out, &rows); err != nil {
		return nil, fmt.Errorf("parse sqlite3 output: %w", err)
	}

	records := make([]UsageRecord, 0, len(rows))
	for _, row := range rows {
		rec := UsageRecord{
			SessionID:    row.SessionID,
			SessionTitle: row.Title,
			SessionModel: row.SessionModel,
			Timestamp:    time.Unix(row.CreatedAt, 0).UTC(),
			Model:        row.Model,
		}

		var metrics struct {
			InputTokens         int64 `json:"input_tokens"`
			OutputTokens        int64 `json:"output_tokens"`
			CacheReadTokens     int64 `json:"cache_read_tokens"`
			CacheCreationTokens int64 `json:"cache_creation_tokens"`
		}
		if row.MetricsJSON != "" {
			_ = json.Unmarshal([]byte(row.MetricsJSON), &metrics)
		}
		rec.InputTokens = metrics.InputTokens
		rec.OutputTokens = metrics.OutputTokens
		rec.CacheReadTokens = metrics.CacheReadTokens
		rec.CacheCreationTokens = metrics.CacheCreationTokens

		records = append(records, rec)
	}

	return records, nil
}
