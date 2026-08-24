package okra

import (
	"os"
	"path/filepath"
	"time"
)

// Paths mirror the macOS layout:
//   macOS:   ~/Library/Application Support/Okra/Runs/<run-id>
//   Windows: %APPDATA%\Okra\Runs\<run-id>
// Managed provider assets live under ~/.okra/providers on both platforms.

// RunsRoot returns the root directory that holds one subdirectory per run.
func RunsRoot() string {
	if override := os.Getenv("OKRA_RUNS_ROOT"); override != "" {
		return override
	}
	base, err := os.UserConfigDir() // %APPDATA% on Windows
	if err != nil || base == "" {
		home, _ := os.UserHomeDir()
		base = filepath.Join(home, ".okra")
	}
	return filepath.Join(base, "Okra", "Runs")
}

// ProvidersRoot returns the root for managed provider assets (bridges, models).
func ProvidersRoot() string {
	home, err := os.UserHomeDir()
	if err != nil || home == "" {
		return filepath.Join(".", ".okra", "providers")
	}
	return filepath.Join(home, ".okra", "providers")
}

// RunDirectory returns the directory for a single run under runsRoot.
func RunDirectory(runsRoot, runID string) string {
	return filepath.Join(runsRoot, runID)
}

// NewRunID builds a sortable, unique run identifier.
func NewRunID(now time.Time) string {
	return now.UTC().Format("20060102-150405") + "-" + randomHex(4)
}
