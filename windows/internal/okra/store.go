package okra

import (
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"
	"sort"
	"strings"
	"sync"
	"time"
)

// Store persists runs under runsRoot, one directory per run:
//
//	<runsRoot>/<run-id>/run.json           manifest (Run)
//	<runsRoot>/<run-id>/events.jsonl       append-only run event ledger
//	<runsRoot>/<run-id>/page-progress.json checkpoint of completed pages
//	<runsRoot>/<run-id>/page-results/page-%04d.json  StructuredExtractionPage
//	<runsRoot>/<run-id>/pages/page-%04d.png          rendered page images (OCR)
//	<runsRoot>/<run-id>/result.md          assembled Markdown output
//	<runsRoot>/<run-id>/result.json        StructuredExtractionDocument
type Store struct {
	runsRoot string
	mu       sync.Mutex
	runLocks map[string]*sync.Mutex
}

func NewStore(runsRoot string) (*Store, error) {
	if err := os.MkdirAll(runsRoot, 0o755); err != nil {
		return nil, err
	}
	s := &Store{runsRoot: runsRoot, runLocks: map[string]*sync.Mutex{}}
	s.recoverOrphanedRuns()
	return s, nil
}

func (s *Store) RunsRoot() string { return s.runsRoot }

func (s *Store) runLock(runID string) *sync.Mutex {
	s.mu.Lock()
	defer s.mu.Unlock()
	l, ok := s.runLocks[runID]
	if !ok {
		l = &sync.Mutex{}
		s.runLocks[runID] = l
	}
	return l
}

// LockRun serializes page-level mutations for one run.
func (s *Store) LockRun(runID string) func() {
	l := s.runLock(runID)
	l.Lock()
	return l.Unlock
}

// CreateRun starts a new run and writes its manifest + first event.
func (s *Store) CreateRun(in Run) (*Run, error) {
	now := time.Now().UTC()
	in.ID = NewRunID(now)
	in.Status = RunStatusRunning
	in.StartedAt = now
	in.CompletedPageCount = intPtr(0)
	in.TotalPageCount = intPtr(in.PageCount)
	in.Progress = floatPtr(0)
	in.ResumeCount = intPtr(0)
	in.EventSequence = intPtr(0)
	in.UpdatedAt = timePtr(now)
	in.PageLifecycles = make([]PageLifecycle, 0, in.PageCount)
	for page := 1; page <= in.PageCount; page++ {
		in.PageLifecycles = append(in.PageLifecycles, PageLifecycle{
			ParserID:   in.ProviderID,
			PageNumber: page,
			State:      PageStateIdle,
			UpdatedAt:  now,
		})
	}

	dir := RunDirectory(s.runsRoot, in.ID)
	for _, sub := range []string{"", "page-results", "pages"} {
		if err := os.MkdirAll(filepath.Join(dir, sub), 0o755); err != nil {
			return nil, err
		}
	}
	if err := writeJSONAtomic(filepath.Join(dir, "run.json"), &in); err != nil {
		return nil, err
	}
	progress := pageProgress{SchemaVersion: 1, CompletedPages: []int{}, UpdatedAt: now}
	if err := writeJSONAtomic(filepath.Join(dir, "page-progress.json"), &progress); err != nil {
		return nil, err
	}
	s.appendEventLocked(&in, "run-started", "Parse started.")
	return &in, nil
}

func (s *Store) GetRun(runID string) (*Run, error) {
	var run Run
	err := readJSON(filepath.Join(RunDirectory(s.runsRoot, runID), "run.json"), &run)
	if err != nil {
		return nil, err
	}
	return &run, nil
}

// CompletedPages returns the checkpointed page numbers for a run.
func (s *Store) CompletedPages(runID string) ([]int, error) {
	var progress pageProgress
	path := filepath.Join(RunDirectory(s.runsRoot, runID), "page-progress.json")
	if err := readJSON(path, &progress); err != nil {
		if os.IsNotExist(err) {
			return []int{}, nil
		}
		return nil, err
	}
	return progress.CompletedPages, nil
}

// SavePageResult persists a finished page and updates progress + manifest.
func (s *Store) SavePageResult(runID string, page Page) error {
	dir := RunDirectory(s.runsRoot, runID)
	name := fmt.Sprintf("page-%04d.json", page.PageNumber)
	if err := writeJSONAtomic(filepath.Join(dir, "page-results", name), &page); err != nil {
		return err
	}

	var progress pageProgress
	progressPath := filepath.Join(dir, "page-progress.json")
	if err := readJSON(progressPath, &progress); err != nil {
		progress = pageProgress{SchemaVersion: 1, CompletedPages: []int{}}
	}
	found := false
	for _, n := range progress.CompletedPages {
		if n == page.PageNumber {
			found = true
			break
		}
	}
	if !found {
		progress.CompletedPages = append(progress.CompletedPages, page.PageNumber)
		sort.Ints(progress.CompletedPages)
	}
	progress.UpdatedAt = time.Now().UTC()
	if err := writeJSONAtomic(progressPath, &progress); err != nil {
		return err
	}

	run, err := s.GetRun(runID)
	if err != nil {
		return err
	}
	completed := len(progress.CompletedPages)
	run.CompletedPageCount = intPtr(completed)
	run.Progress = floatPtr(ratio(completed, run.PageCount))
	run.UpdatedAt = timePtr(time.Now().UTC())
	run.setPageLifecycle(page.PageNumber, PageStateSucceeded, nil)
	if err := s.writeRun(run); err != nil {
		return err
	}
	s.appendEventLocked(run, "page-succeeded", fmt.Sprintf("Page %d of %d extracted.", page.PageNumber, run.PageCount))
	return nil
}

// MarkPageRunning records that a page started processing.
func (s *Store) MarkPageRunning(runID string, pageNumber int) {
	run, err := s.GetRun(runID)
	if err != nil {
		return
	}
	run.setPageLifecycle(pageNumber, PageStateRunning, nil)
	run.UpdatedAt = timePtr(time.Now().UTC())
	_ = s.writeRun(run)
}

// MarkPageFailed records a page failure without failing the whole run.
func (s *Store) MarkPageFailed(runID string, pageNumber int, message string) {
	run, err := s.GetRun(runID)
	if err != nil {
		return
	}
	run.setPageLifecycle(pageNumber, PageStateFailed, &message)
	run.UpdatedAt = timePtr(time.Now().UTC())
	_ = s.writeRun(run)
	s.appendEventLocked(run, "page-failed", fmt.Sprintf("Page %d failed: %s", pageNumber, message))
}

// CompleteRun assembles result.md + result.json and marks the run succeeded.
func (s *Store) CompleteRun(runID string) (*Run, error) {
	run, err := s.GetRun(runID)
	if err != nil {
		return nil, err
	}
	if run.Status != RunStatusRunning {
		return nil, fmt.Errorf("run %s is %s, not running", runID, run.Status)
	}

	pages, err := s.loadPageResults(runID)
	if err != nil {
		return nil, err
	}
	if len(pages) == 0 {
		return nil, fmt.Errorf("no completed pages for run %s", runID)
	}

	dir := RunDirectory(s.runsRoot, runID)
	mdParts := make([]string, 0, len(pages))
	for _, page := range pages {
		mdParts = append(mdParts, page.Markdown)
	}
	markdown := strings.Join(mdParts, "\n\n") + "\n"
	mdPath := filepath.Join(dir, "result.md")
	if err := os.WriteFile(mdPath, []byte(markdown), 0o644); err != nil {
		return nil, err
	}

	completed := len(pages)
	doc := StructuredDocument{
		SchemaVersion:      StructuredSchemaVersion,
		Object:             StructuredObject,
		Provider:           DocumentProvider{ID: run.ProviderID, Name: run.ProviderName},
		Title:              strings.TrimSuffix(run.FileName, filepath.Ext(run.FileName)),
		PageCount:          run.PageCount,
		CompletedPageCount: completed,
		Complete:           completed == run.PageCount,
		Simulation:         false,
		Pages:              pages,
	}
	jsonPath := filepath.Join(dir, "result.json")
	if err := writeJSONAtomic(jsonPath, &doc); err != nil {
		return nil, err
	}

	now := time.Now().UTC()
	run.Status = RunStatusSucceeded
	run.OutputPath = strPtr(mdPath)
	run.StructuredOutputPath = strPtr(jsonPath)
	run.CompletedAt = timePtr(now)
	run.UpdatedAt = timePtr(now)
	run.CompletedPageCount = intPtr(completed)
	run.Progress = floatPtr(ratio(completed, run.PageCount))
	message := "Extraction complete."
	if completed != run.PageCount {
		message = fmt.Sprintf("Completed %d of %d pages.", completed, run.PageCount)
	}
	run.StatusMessage = strPtr(message)
	if err := s.writeRun(run); err != nil {
		return nil, err
	}
	s.appendEventLocked(run, "run-succeeded", message)
	return run, nil
}

// FailRun marks a run failed with an error message.
func (s *Store) FailRun(runID, message string) (*Run, error) {
	run, err := s.GetRun(runID)
	if err != nil {
		return nil, err
	}
	if run.Status != RunStatusRunning {
		return run, nil
	}
	now := time.Now().UTC()
	run.Status = RunStatusFailed
	run.ErrorMessage = strPtr(message)
	run.CompletedAt = timePtr(now)
	run.UpdatedAt = timePtr(now)
	for i := range run.PageLifecycles {
		if run.PageLifecycles[i].State == PageStateRunning {
			run.PageLifecycles[i].State = PageStateFailed
			run.PageLifecycles[i].Detail = strPtr(message)
			run.PageLifecycles[i].UpdatedAt = now
		}
	}
	if err := s.writeRun(run); err != nil {
		return nil, err
	}
	s.appendEventLocked(run, "run-failed", message)
	return run, nil
}

// CancelRun marks a running run canceled, keeping page checkpoints for resume.
func (s *Store) CancelRun(runID string) (*Run, error) {
	run, err := s.GetRun(runID)
	if err != nil {
		return nil, err
	}
	if run.Status != RunStatusRunning {
		return run, nil
	}
	now := time.Now().UTC()
	run.Status = RunStatusCanceled
	run.CancelRequestedAt = timePtr(now)
	run.CompletedAt = timePtr(now)
	run.UpdatedAt = timePtr(now)
	run.StatusMessage = strPtr("Canceled. Completed pages are kept for resume.")
	for i := range run.PageLifecycles {
		if run.PageLifecycles[i].State == PageStateRunning {
			run.PageLifecycles[i].State = PageStateCanceled
			run.PageLifecycles[i].UpdatedAt = now
		}
	}
	if err := s.writeRun(run); err != nil {
		return nil, err
	}
	s.appendEventLocked(run, "run-canceled", "Parse canceled.")
	return run, nil
}

// ResumeRun moves a canceled/failed/interrupted run back to running, keeping
// completed page checkpoints. The provider stays pinned to the original run.
func (s *Store) ResumeRun(runID string) (*Run, error) {
	run, err := s.GetRun(runID)
	if err != nil {
		return nil, err
	}
	switch run.Status {
	case RunStatusCanceled, RunStatusFailed, RunStatusInterrupted:
	default:
		return nil, fmt.Errorf("run %s is %s and cannot resume", runID, run.Status)
	}
	now := time.Now().UTC()
	run.Status = RunStatusRunning
	run.ErrorMessage = nil
	run.CompletedAt = nil
	run.CancelRequestedAt = nil
	run.UpdatedAt = timePtr(now)
	run.ResumeCount = intPtr(derefInt(run.ResumeCount) + 1)
	run.StatusMessage = strPtr("Resuming from completed pages.")
	for i := range run.PageLifecycles {
		if run.PageLifecycles[i].State == PageStateRunning ||
			run.PageLifecycles[i].State == PageStateCanceled ||
			run.PageLifecycles[i].State == PageStateFailed {
			run.PageLifecycles[i].State = PageStateIdle
			run.PageLifecycles[i].Detail = nil
			run.PageLifecycles[i].UpdatedAt = now
		}
	}
	if err := s.writeRun(run); err != nil {
		return nil, err
	}
	s.appendEventLocked(run, "run-resumed", "Parse resumed.")
	return run, nil
}

// ListRuns returns run manifests, newest first, optionally filtered by source.
func (s *Store) ListRuns(sourcePath string, limit int) ([]Run, error) {
	entries, err := os.ReadDir(s.runsRoot)
	if err != nil {
		if os.IsNotExist(err) {
			return []Run{}, nil
		}
		return nil, err
	}
	runs := make([]Run, 0, len(entries))
	for _, entry := range entries {
		if !entry.IsDir() {
			continue
		}
		var run Run
		if err := readJSON(filepath.Join(s.runsRoot, entry.Name(), "run.json"), &run); err != nil {
			continue
		}
		if sourcePath != "" && !strings.EqualFold(run.SourcePath, sourcePath) {
			continue
		}
		runs = append(runs, run)
	}
	sort.Slice(runs, func(i, j int) bool { return runs[i].StartedAt.After(runs[j].StartedAt) })
	if limit > 0 && len(runs) > limit {
		runs = runs[:limit]
	}
	return runs, nil
}

// LoadOutput reads result.md / result.json for a finished run.
func (s *Store) LoadOutput(runID string) (markdown string, doc *StructuredDocument, err error) {
	dir := RunDirectory(s.runsRoot, runID)
	mdBytes, mdErr := os.ReadFile(filepath.Join(dir, "result.md"))
	if mdErr == nil {
		markdown = string(mdBytes)
	}
	var structured StructuredDocument
	if err := readJSON(filepath.Join(dir, "result.json"), &structured); err == nil {
		doc = &structured
	}
	if mdErr != nil && doc == nil {
		return "", nil, fmt.Errorf("run %s has no output yet", runID)
	}
	return markdown, doc, nil
}

// SaveRedactions persists detector candidates beside the immutable parse
// output. Human review and PDF export remain separate explicit steps.
func (s *Store) SaveRedactions(runID string, detection *RedactionDetection) error {
	if _, err := s.GetRun(runID); err != nil {
		return err
	}
	return writeJSONAtomic(filepath.Join(RunDirectory(s.runsRoot, runID), "redactions.json"), detection)
}

// LoadRedactions reads the latest detector candidate set for a run.
func (s *Store) LoadRedactions(runID string) (*RedactionDetection, error) {
	var detection RedactionDetection
	err := readJSON(filepath.Join(RunDirectory(s.runsRoot, runID), "redactions.json"), &detection)
	if err != nil {
		return nil, err
	}
	return &detection, nil
}

// recoverOrphanedRuns marks runs left "running" by a previous app exit.
func (s *Store) recoverOrphanedRuns() {
	runs, err := s.ListRuns("", 0)
	if err != nil {
		return
	}
	for i := range runs {
		run := &runs[i]
		if run.Status != RunStatusRunning {
			continue
		}
		now := time.Now().UTC()
		run.Status = RunStatusInterrupted
		run.StatusMessage = strPtr("The app closed before the run finished. Resume to continue from completed pages.")
		run.UpdatedAt = timePtr(now)
		for j := range run.PageLifecycles {
			if run.PageLifecycles[j].State == PageStateRunning {
				run.PageLifecycles[j].State = PageStateCanceled
				run.PageLifecycles[j].UpdatedAt = now
			}
		}
		_ = s.writeRun(run)
		s.appendEventLocked(run, "run-interrupted", "The app closed before the run finished.")
	}
}

func (s *Store) loadPageResults(runID string) ([]Page, error) {
	dir := filepath.Join(RunDirectory(s.runsRoot, runID), "page-results")
	entries, err := os.ReadDir(dir)
	if err != nil {
		return nil, err
	}
	pages := make([]Page, 0, len(entries))
	for _, entry := range entries {
		if entry.IsDir() || !strings.HasSuffix(entry.Name(), ".json") {
			continue
		}
		var page Page
		if err := readJSON(filepath.Join(dir, entry.Name()), &page); err != nil {
			return nil, err
		}
		pages = append(pages, page)
	}
	sort.Slice(pages, func(i, j int) bool { return pages[i].PageNumber < pages[j].PageNumber })
	return pages, nil
}

func (s *Store) writeRun(run *Run) error {
	return writeJSONAtomic(filepath.Join(RunDirectory(s.runsRoot, run.ID), "run.json"), run)
}

func (s *Store) appendEventLocked(run *Run, eventType, message string) {
	seq := derefInt(run.EventSequence) + 1
	run.EventSequence = intPtr(seq)
	event := RunEvent{
		Sequence:           seq,
		Type:               eventType,
		RunID:              run.ID,
		Status:             run.Status,
		Progress:           derefFloat(run.Progress),
		CompletedPageCount: derefInt(run.CompletedPageCount),
		TotalPageCount:     run.PageCount,
		Message:            message,
		CreatedAt:          time.Now().UTC(),
	}
	line, err := json.Marshal(&event)
	if err != nil {
		return
	}
	path := filepath.Join(RunDirectory(s.runsRoot, run.ID), "events.jsonl")
	f, err := os.OpenFile(path, os.O_APPEND|os.O_CREATE|os.O_WRONLY, 0o644)
	if err != nil {
		return
	}
	defer f.Close()
	_, _ = f.Write(append(line, '\n'))
	_ = s.writeRun(run) // persist bumped eventSequence
}

func (run *Run) setPageLifecycle(pageNumber int, state string, detail *string) {
	for i := range run.PageLifecycles {
		if run.PageLifecycles[i].PageNumber == pageNumber {
			run.PageLifecycles[i].State = state
			run.PageLifecycles[i].Detail = detail
			run.PageLifecycles[i].UpdatedAt = time.Now().UTC()
			return
		}
	}
}

type pageProgress struct {
	SchemaVersion  int       `json:"schemaVersion"`
	CompletedPages []int     `json:"completedPages"`
	UpdatedAt      time.Time `json:"updatedAt"`
}

func ratio(part, whole int) float64 {
	if whole <= 0 {
		return 0
	}
	return float64(part) / float64(whole)
}

func derefInt(v *int) int {
	if v == nil {
		return 0
	}
	return *v
}

func derefFloat(v *float64) float64 {
	if v == nil {
		return 0
	}
	return *v
}

func writeJSONAtomic(path string, value any) error {
	data, err := json.MarshalIndent(value, "", "  ")
	if err != nil {
		return err
	}
	tmp := path + ".tmp"
	if err := os.WriteFile(tmp, data, 0o644); err != nil {
		return err
	}
	_ = os.Remove(path)
	return os.Rename(tmp, path)
}

func readJSON(path string, value any) error {
	data, err := os.ReadFile(path)
	if err != nil {
		return err
	}
	return json.Unmarshal(data, value)
}
