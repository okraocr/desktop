package okra

import (
	"crypto/rand"
	"encoding/hex"
	"time"
)

// JSON models mirroring the macOS Codable contracts in
// apps/desktop/OkraPDF/LocalProcessing (StructuredExtractionOutput.swift,
// LocalProcessingProvider.swift, ParserPageLifecycle.swift).

// BoundingBox is a normalized, top-left-origin rectangle (0..1 of page size).
type BoundingBox struct {
	X      float64 `json:"x"`
	Y      float64 `json:"y"`
	Width  float64 `json:"width"`
	Height float64 `json:"height"`
	Unit   string  `json:"unit"`
	Origin string  `json:"origin"`
}

// Block is one structured extraction block on a page.
type Block struct {
	ID              string       `json:"id"`
	Type            string       `json:"type"`
	SourceType      string       `json:"sourceType"`
	Text            string       `json:"text"`
	HTML            *string      `json:"html,omitempty"`
	BBox            *BoundingBox `json:"bbox,omitempty"`
	SourceBBox      []float64    `json:"sourceBbox,omitempty"`
	SourceBBoxScale *int         `json:"sourceBboxScale,omitempty"`
}

// Diagnostics carries per-page extraction counters.
type Diagnostics struct {
	RawCharacterCount       int      `json:"rawCharacterCount"`
	DecodedCharacterCount   int      `json:"decodedCharacterCount"`
	TokenArtifactCount      int      `json:"tokenArtifactCount"`
	DetectionCount          int      `json:"detectionCount"`
	MalformedDetectionCount int      `json:"malformedDetectionCount"`
	DuplicateBlockCount     int      `json:"duplicateBlockCount"`
	LoopDetected            bool     `json:"loopDetected"`
	Warnings                []string `json:"warnings"`
	BlockCount              *int     `json:"blockCount,omitempty"`
}

// Page is the structured extraction output for one page.
type Page struct {
	PageNumber  int         `json:"pageNumber"`
	ImageFile   string      `json:"imageFile"`
	Markdown    string      `json:"markdown"`
	PlainText   string      `json:"plainText"`
	Blocks      []Block     `json:"blocks"`
	Diagnostics Diagnostics `json:"diagnostics"`
	Provenance  *string     `json:"provenance,omitempty"`
}

// DocumentProvider identifies the parser that produced a document.
type DocumentProvider struct {
	ID   string `json:"id"`
	Name string `json:"name"`
}

// StructuredDocument is the result.json contract (schemaVersion 1).
type StructuredDocument struct {
	SchemaVersion      int              `json:"schemaVersion"`
	Object             string           `json:"object"`
	Provider           DocumentProvider `json:"provider"`
	Title              string           `json:"title"`
	PageCount          int              `json:"pageCount"`
	CompletedPageCount int              `json:"completedPageCount"`
	Complete           bool             `json:"complete"`
	Simulation         bool             `json:"simulation"`
	Pages              []Page           `json:"pages"`
}

// Structured object identifiers, mirroring the macOS writers.
const (
	StructuredSchemaVersion = 1
	StructuredObject        = "local_extraction"
)

// Page lifecycle states for per-page progress.
const (
	PageStateIdle      = "idle"
	PageStateRunning   = "running"
	PageStateSucceeded = "succeeded"
	PageStateFailed    = "failed"
	PageStateCanceled  = "canceled"
)

// PageLifecycle tracks the state of one page inside a run.
type PageLifecycle struct {
	ParserID   string    `json:"parserID"`
	PageNumber int       `json:"pageNumber"`
	State      string    `json:"state"`
	Detail     *string   `json:"detail,omitempty"`
	UpdatedAt  time.Time `json:"updatedAt"`
}

// Run statuses.
const (
	RunStatusRunning     = "running"
	RunStatusSucceeded   = "succeeded"
	RunStatusFailed      = "failed"
	RunStatusCanceled    = "canceled"
	RunStatusInterrupted = "interrupted"
)

// Run is the run.json manifest, mirroring LocalProcessingRun on macOS.
type Run struct {
	ID                   string          `json:"id"`
	SourcePath           string          `json:"sourcePath"`
	FileName             string          `json:"fileName"`
	ProviderID           string          `json:"providerId"`
	ProviderName         string          `json:"providerName"`
	ExecutionMode        *string         `json:"executionMode,omitempty"`
	Status               string          `json:"status"`
	OutputPath           *string         `json:"outputPath,omitempty"`
	StructuredOutputPath *string         `json:"structuredOutputPath,omitempty"`
	ErrorMessage         *string         `json:"errorMessage,omitempty"`
	PageCount            int             `json:"pageCount"`
	CompletedPageCount   *int            `json:"completedPageCount,omitempty"`
	TotalPageCount       *int            `json:"totalPageCount,omitempty"`
	StartedAt            time.Time       `json:"startedAt"`
	CompletedAt          *time.Time      `json:"completedAt,omitempty"`
	Progress             *float64        `json:"progress,omitempty"`
	StatusMessage        *string         `json:"statusMessage,omitempty"`
	UpdatedAt            *time.Time      `json:"updatedAt,omitempty"`
	CancelRequestedAt    *time.Time      `json:"cancelRequestedAt,omitempty"`
	ResumeCount          *int            `json:"resumeCount,omitempty"`
	EventSequence        *int            `json:"eventSequence,omitempty"`
	PageLifecycles       []PageLifecycle `json:"pageLifecycles,omitempty"`
}

// RunEvent is one line in a run's events.jsonl ledger.
type RunEvent struct {
	Sequence           int       `json:"sequence"`
	Type               string    `json:"type"`
	RunID              string    `json:"runId"`
	Status             string    `json:"status"`
	Progress           float64   `json:"progress"`
	CompletedPageCount int       `json:"completedPageCount"`
	TotalPageCount     int       `json:"totalPageCount"`
	Message            string    `json:"message"`
	CreatedAt          time.Time `json:"createdAt"`
}

func randomHex(n int) string {
	buf := make([]byte, n)
	if _, err := rand.Read(buf); err != nil {
		return "00000000"
	}
	return hex.EncodeToString(buf)
}

func strPtr(s string) *string { return &s }

func intPtr(v int) *int { return &v }

func floatPtr(v float64) *float64 { return &v }

func timePtr(t time.Time) *time.Time { return &t }
