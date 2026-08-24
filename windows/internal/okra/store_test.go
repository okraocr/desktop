package okra

import (
	"os"
	"path/filepath"
	"strings"
	"testing"
)

func testStore(t *testing.T) *Store {
	t.Helper()
	store, err := NewStore(filepath.Join(t.TempDir(), "Runs"))
	if err != nil {
		t.Fatalf("NewStore: %v", err)
	}
	return store
}

func samplePage(pageNumber int, text string) Page {
	return Page{
		PageNumber: pageNumber,
		Markdown:   text,
		PlainText:  text,
		Blocks: []Block{{
			ID:         blockID(pageNumber, 1),
			Type:       "text",
			SourceType: "pdf-text-line",
			Text:       text,
		}},
		Diagnostics: Diagnostics{Warnings: []string{}},
	}
}

func TestRunLifecycleWritesArtifacts(t *testing.T) {
	store := testStore(t)
	run, err := store.CreateRun(Run{
		SourcePath:   `C:\docs\spec.pdf`,
		FileName:     "spec.pdf",
		ProviderID:   "windows-ocr",
		ProviderName: "Windows OCR",
		PageCount:    2,
	})
	if err != nil {
		t.Fatalf("CreateRun: %v", err)
	}
	if run.Status != RunStatusRunning {
		t.Fatalf("expected running, got %s", run.Status)
	}
	if len(run.PageLifecycles) != 2 {
		t.Fatalf("expected 2 page lifecycles, got %d", len(run.PageLifecycles))
	}

	if err := store.SavePageResult(run.ID, samplePage(1, "Hello")); err != nil {
		t.Fatalf("SavePageResult 1: %v", err)
	}
	if err := store.SavePageResult(run.ID, samplePage(2, "World")); err != nil {
		t.Fatalf("SavePageResult 2: %v", err)
	}

	completed, err := store.CompletedPages(run.ID)
	if err != nil {
		t.Fatalf("CompletedPages: %v", err)
	}
	if len(completed) != 2 || completed[0] != 1 || completed[1] != 2 {
		t.Fatalf("unexpected completed pages: %v", completed)
	}

	finished, err := store.CompleteRun(run.ID)
	if err != nil {
		t.Fatalf("CompleteRun: %v", err)
	}
	if finished.Status != RunStatusSucceeded {
		t.Fatalf("expected succeeded, got %s", finished.Status)
	}
	if finished.OutputPath == nil || finished.StructuredOutputPath == nil {
		t.Fatal("expected output paths to be set")
	}

	markdown, doc, err := store.LoadOutput(run.ID)
	if err != nil {
		t.Fatalf("LoadOutput: %v", err)
	}
	if markdown != "Hello\n\nWorld\n" {
		t.Fatalf("unexpected markdown: %q", markdown)
	}
	if doc == nil {
		t.Fatal("expected structured document")
	}
	if doc.SchemaVersion != 1 || doc.Object != "local_extraction" {
		t.Fatalf("unexpected structured header: %+v", doc)
	}
	if doc.Provider.ID != "windows-ocr" || doc.Title != "spec" {
		t.Fatalf("unexpected provider/title: %+v", doc.Provider)
	}
	if !doc.Complete || doc.CompletedPageCount != 2 || len(doc.Pages) != 2 {
		t.Fatalf("unexpected document pages: %+v", doc)
	}

	// events.jsonl should have entries for start, pages, completion.
	events, err := os.ReadFile(filepath.Join(store.RunsRoot(), run.ID, "events.jsonl"))
	if err != nil {
		t.Fatalf("events.jsonl: %v", err)
	}
	for _, want := range []string{"run-started", "page-succeeded", "run-succeeded"} {
		if !strings.Contains(string(events), want) {
			t.Fatalf("events.jsonl missing %q:\n%s", want, events)
		}
	}
}

func TestCancelResumeKeepsCheckpoints(t *testing.T) {
	store := testStore(t)
	run, _ := store.CreateRun(Run{
		SourcePath: `C:\docs\big.pdf`, FileName: "big.pdf",
		ProviderID: "windows-ocr", ProviderName: "Windows OCR", PageCount: 3,
	})
	if err := store.SavePageResult(run.ID, samplePage(1, "One")); err != nil {
		t.Fatalf("SavePageResult: %v", err)
	}
	canceled, err := store.CancelRun(run.ID)
	if err != nil {
		t.Fatalf("CancelRun: %v", err)
	}
	if canceled.Status != RunStatusCanceled {
		t.Fatalf("expected canceled, got %s", canceled.Status)
	}
	completed, _ := store.CompletedPages(run.ID)
	if len(completed) != 1 {
		t.Fatalf("checkpoint lost after cancel: %v", completed)
	}

	resumed, err := store.ResumeRun(run.ID)
	if err != nil {
		t.Fatalf("ResumeRun: %v", err)
	}
	if resumed.Status != RunStatusRunning {
		t.Fatalf("expected running after resume, got %s", resumed.Status)
	}
	if resumed.ResumeCount == nil || *resumed.ResumeCount != 1 {
		t.Fatalf("expected resumeCount 1, got %+v", resumed.ResumeCount)
	}
	_ = store.SavePageResult(run.ID, samplePage(2, "Two"))
	_ = store.SavePageResult(run.ID, samplePage(3, "Three"))
	finished, err := store.CompleteRun(run.ID)
	if err != nil {
		t.Fatalf("CompleteRun after resume: %v", err)
	}
	_, doc, _ := store.LoadOutput(finished.ID)
	if doc == nil || len(doc.Pages) != 3 || !doc.Complete {
		t.Fatalf("expected complete 3-page document, got %+v", doc)
	}
}

func TestOrphanedRunRecovery(t *testing.T) {
	root := filepath.Join(t.TempDir(), "Runs")
	store, err := NewStore(root)
	if err != nil {
		t.Fatalf("NewStore: %v", err)
	}
	run, _ := store.CreateRun(Run{
		SourcePath: `C:\docs\open.pdf`, FileName: "open.pdf",
		ProviderID: "windows-ocr", ProviderName: "Windows OCR", PageCount: 1,
	})

	// Re-open the store: the still-"running" run must become interrupted.
	reopened, err := NewStore(root)
	if err != nil {
		t.Fatalf("NewStore reopen: %v", err)
	}
	recovered, err := reopened.GetRun(run.ID)
	if err != nil {
		t.Fatalf("GetRun: %v", err)
	}
	if recovered.Status != RunStatusInterrupted {
		t.Fatalf("expected interrupted, got %s", recovered.Status)
	}
}

func TestListRunsFiltersBySourcePath(t *testing.T) {
	store := testStore(t)
	_, _ = store.CreateRun(Run{SourcePath: `C:\docs\a.pdf`, FileName: "a.pdf", ProviderID: "windows-ocr", ProviderName: "Windows OCR", PageCount: 1})
	_, _ = store.CreateRun(Run{SourcePath: `C:\docs\b.pdf`, FileName: "b.pdf", ProviderID: "ollama", ProviderName: "Ollama", PageCount: 1})

	all, _ := store.ListRuns("", 100)
	if len(all) != 2 {
		t.Fatalf("expected 2 runs, got %d", len(all))
	}
	filtered, _ := store.ListRuns(`c:\docs\a.pdf`, 100)
	if len(filtered) != 1 || filtered[0].FileName != "a.pdf" {
		t.Fatalf("unexpected filter result: %+v", filtered)
	}
}
