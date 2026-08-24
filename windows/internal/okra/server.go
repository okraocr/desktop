package okra

import (
	"bytes"
	"context"
	"encoding/base64"
	"encoding/json"
	"fmt"
	"io"
	"io/fs"
	"net/http"
	"os"
	"path/filepath"
	"strings"
	"sync"
)

// Server is the loopback HTTP API the WebView2 UI talks to (the okraPDF
// equivalent of the Ollama app's local UI server).
type Server struct {
	store     *Store
	providers map[string]Provider
	ollama    *OllamaClient
	presidio  *PresidioService
	token     string
	static    http.Handler

	mu      sync.Mutex
	current *CurrentDocument
	pending *string // CLI-provided PDF path, consumed once by the UI
}

// CurrentDocument is the open document registered by the UI after PDF.js
// loads it (the UI owns page counting, like PDFKit does on macOS).
type CurrentDocument struct {
	Path      string `json:"path"`
	FileName  string `json:"fileName"`
	PageCount int    `json:"pageCount"`
}

func NewServer(store *Store, providers []Provider, ollama *OllamaClient, token string, static fs.FS) *Server {
	byID := map[string]Provider{}
	for _, provider := range providers {
		byID[provider.Descriptor().ID] = provider
	}
	return &Server{
		store:     store,
		providers: byID,
		ollama:    ollama,
		presidio:  NewPresidioService(),
		token:     token,
		static:    http.FileServer(http.FS(static)),
	}
}

// SetPendingOpen registers a PDF path the UI should open on launch.
func (s *Server) SetPendingOpen(path string) {
	s.mu.Lock()
	defer s.mu.Unlock()
	if abs, err := filepath.Abs(path); err == nil {
		path = abs
	}
	s.pending = &path
}

func (s *Server) Handler() http.Handler {
	mux := http.NewServeMux()
	mux.HandleFunc("GET /api/health", s.handleHealth)
	mux.HandleFunc("GET /api/document/pending", s.handlePendingDocument)
	mux.HandleFunc("GET /api/document/current", s.handleCurrentDocument)
	mux.HandleFunc("GET /api/document/file", s.handleDocumentFile)
	mux.HandleFunc("POST /api/document/dialog", s.handleOpenDialog)
	mux.HandleFunc("POST /api/document/select", s.handleSelectDocument)
	mux.HandleFunc("POST /api/document/reveal", s.handleRevealDocument)
	mux.HandleFunc("POST /api/document/save-copy", s.handleSaveDocumentCopy)
	mux.HandleFunc("GET /api/providers", s.handleProviders)
	mux.HandleFunc("POST /api/providers/{id}/install", s.handleProviderInstall)
	mux.HandleFunc("GET /api/providers/{id}/install-status", s.handleProviderInstallStatus)
	mux.HandleFunc("GET /api/ollama/models", s.handleOllamaModels)
	mux.HandleFunc("GET /api/redaction/presidio/status", s.handlePresidioStatus)
	mux.HandleFunc("POST /api/redaction/presidio/install", s.handlePresidioInstall)
	mux.HandleFunc("GET /api/redaction/presidio/install-status", s.handlePresidioInstallStatus)
	mux.HandleFunc("POST /api/runs", s.handleCreateRun)
	mux.HandleFunc("GET /api/runs", s.handleListRuns)
	mux.HandleFunc("GET /api/runs/{id}", s.handleGetRun)
	mux.HandleFunc("GET /api/runs/{id}/output", s.handleRunOutput)
	mux.HandleFunc("POST /api/runs/{id}/pages", s.handleRunPage)
	mux.HandleFunc("POST /api/runs/{id}/complete", s.handleCompleteRun)
	mux.HandleFunc("POST /api/runs/{id}/cancel", s.handleCancelRun)
	mux.HandleFunc("POST /api/runs/{id}/fail", s.handleFailRun)
	mux.HandleFunc("POST /api/runs/{id}/resume", s.handleResumeRun)
	mux.HandleFunc("POST /api/runs/{id}/reveal", s.handleRevealRun)
	mux.HandleFunc("POST /api/runs/{id}/save-as", s.handleSaveAs)
	mux.HandleFunc("GET /api/runs/{id}/redactions", s.handleGetRedactions)
	mux.HandleFunc("POST /api/runs/{id}/redactions/detect", s.handleDetectRedactions)
	mux.HandleFunc("POST /api/runs/{id}/redactions/save", s.handleSaveRedactedPDF)
	mux.Handle("/", s.withToken(s.static))
	return s.withToken(mux)
}

// Shutdown stops managed session workers owned by the loopback server.
func (s *Server) Shutdown() {
	if s.presidio != nil {
		s.presidio.Shutdown()
	}
}

// withToken guards the loopback API with a per-launch token injected into the
// WebView before navigation (blocks cross-site requests from other origins).
func (s *Server) withToken(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.URL.Path == "/api/health" || s.token == "" {
			next.ServeHTTP(w, r)
			return
		}
		if strings.HasPrefix(r.URL.Path, "/api/") {
			if r.Header.Get("X-Okra-Token") != s.token {
				http.Error(w, "forbidden", http.StatusForbidden)
				return
			}
		}
		next.ServeHTTP(w, r)
	})
}

func (s *Server) handleHealth(w http.ResponseWriter, r *http.Request) {
	writeJSON(w, http.StatusOK, map[string]any{"ok": true, "app": "okraPDF", "platform": "windows"})
}

func (s *Server) handlePendingDocument(w http.ResponseWriter, r *http.Request) {
	s.mu.Lock()
	defer s.mu.Unlock()
	if s.pending == nil {
		writeJSON(w, http.StatusOK, map[string]any{"path": nil})
		return
	}
	path := *s.pending
	s.pending = nil
	writeJSON(w, http.StatusOK, map[string]any{"path": path})
}

func (s *Server) handleCurrentDocument(w http.ResponseWriter, r *http.Request) {
	s.mu.Lock()
	defer s.mu.Unlock()
	if s.current == nil {
		writeJSON(w, http.StatusOK, map[string]any{"document": nil})
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{"document": s.current})
}

func (s *Server) handleDocumentFile(w http.ResponseWriter, r *http.Request) {
	path := r.URL.Query().Get("path")
	if path == "" || !strings.EqualFold(filepath.Ext(path), ".pdf") {
		http.Error(w, "a .pdf path is required", http.StatusBadRequest)
		return
	}
	info, err := os.Stat(path)
	if err != nil || info.IsDir() {
		http.Error(w, "file not found", http.StatusNotFound)
		return
	}
	w.Header().Set("Content-Type", "application/pdf")
	http.ServeFile(w, r, path)
}

func (s *Server) handleOpenDialog(w http.ResponseWriter, r *http.Request) {
	path, err := OpenPDFDialog(r.Context())
	if err != nil {
		writeError(w, http.StatusInternalServerError, err)
		return
	}
	if path == "" {
		writeJSON(w, http.StatusOK, map[string]any{"path": nil})
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{"path": path, "fileName": filepath.Base(path)})
}

type selectDocumentRequest struct {
	Path      string `json:"path"`
	FileName  string `json:"fileName"`
	PageCount int    `json:"pageCount"`
}

func (s *Server) handleSelectDocument(w http.ResponseWriter, r *http.Request) {
	var req selectDocumentRequest
	if err := decodeJSON(r, &req); err != nil {
		writeError(w, http.StatusBadRequest, err)
		return
	}
	if req.Path == "" || !strings.EqualFold(filepath.Ext(req.Path), ".pdf") {
		writeError(w, http.StatusBadRequest, fmt.Errorf("choose a PDF file"))
		return
	}
	if _, err := os.Stat(req.Path); err != nil {
		writeError(w, http.StatusBadRequest, fmt.Errorf("could not open %s", req.FileName))
		return
	}
	if req.PageCount <= 0 {
		writeError(w, http.StatusBadRequest, fmt.Errorf("the PDF does not contain any pages"))
		return
	}
	doc := CurrentDocument{Path: req.Path, FileName: req.FileName, PageCount: req.PageCount}
	s.mu.Lock()
	s.current = &doc
	s.mu.Unlock()
	writeJSON(w, http.StatusOK, map[string]any{"document": doc})
}

type revealRequest struct {
	Path string `json:"path"`
}

func (s *Server) handleRevealDocument(w http.ResponseWriter, r *http.Request) {
	var req revealRequest
	if err := decodeJSON(r, &req); err != nil {
		writeError(w, http.StatusBadRequest, err)
		return
	}
	if err := RevealPath(r.Context(), req.Path); err != nil {
		writeError(w, http.StatusNotFound, err)
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{"ok": true})
}

type providerStatus struct {
	ProviderDescriptor
	Availability Availability `json:"availability"`
}

func (s *Server) handleProviders(w http.ResponseWriter, r *http.Request) {
	statuses := make([]providerStatus, 0, len(s.providers))
	// Stable order: built-in first, managed parsers next, Ollama last.
	order := []string{"windows-ocr", "chandra-ocr-2", "ollama"}
	for _, id := range order {
		provider, ok := s.providers[id]
		if !ok {
			continue
		}
		statuses = append(statuses, providerStatus{
			ProviderDescriptor: provider.Descriptor(),
			Availability:       provider.Availability(r.Context()),
		})
	}
	writeJSON(w, http.StatusOK, map[string]any{"providers": statuses})
}

// Installer is implemented by providers with a managed setup (e.g. Chandra).
type Installer interface {
	Install(ctx context.Context) error
	InstallStatus() *InstallStatus
}

func (s *Server) handleProviderInstall(w http.ResponseWriter, r *http.Request) {
	provider, ok := s.providers[r.PathValue("id")]
	if !ok {
		writeError(w, http.StatusNotFound, fmt.Errorf("unknown provider"))
		return
	}
	installer, ok := provider.(Installer)
	if !ok {
		writeError(w, http.StatusBadRequest, fmt.Errorf("this provider has no managed setup"))
		return
	}
	if status := installer.InstallStatus(); status != nil && !status.Done && status.Phase != InstallPhaseIdle && status.Phase != InstallPhaseError {
		writeError(w, http.StatusConflict, fmt.Errorf("setup is already running"))
		return
	}
	// Setup downloads gigabytes; run it in the background and poll status.
	go func() {
		_ = installer.Install(context.Background())
	}()
	writeJSON(w, http.StatusOK, map[string]any{"started": true})
}

func (s *Server) handleProviderInstallStatus(w http.ResponseWriter, r *http.Request) {
	provider, ok := s.providers[r.PathValue("id")]
	if !ok {
		writeError(w, http.StatusNotFound, fmt.Errorf("unknown provider"))
		return
	}
	installer, ok := provider.(Installer)
	if !ok {
		writeJSON(w, http.StatusOK, map[string]any{"status": nil})
		return
	}
	status := installer.InstallStatus()
	writeJSON(w, http.StatusOK, map[string]any{"status": status})
}

func (s *Server) handleOllamaModels(w http.ResponseWriter, r *http.Request) {
	models, err := s.ollama.Models(r.Context())
	if err != nil {
		writeJSON(w, http.StatusOK, map[string]any{"models": []OllamaModel{}, "error": err.Error()})
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{"models": models})
}

func (s *Server) handlePresidioStatus(w http.ResponseWriter, r *http.Request) {
	writeJSON(w, http.StatusOK, map[string]any{"status": s.presidio.Status(r.Context())})
}

func (s *Server) handlePresidioInstall(w http.ResponseWriter, r *http.Request) {
	if status := s.presidio.InstallStatus(); status != nil && !status.Done && status.Phase != InstallPhaseIdle && status.Phase != InstallPhaseError {
		writeError(w, http.StatusConflict, fmt.Errorf("setup is already running"))
		return
	}
	go func() {
		_ = s.presidio.Install(context.Background())
	}()
	writeJSON(w, http.StatusOK, map[string]any{"started": true})
}

func (s *Server) handlePresidioInstallStatus(w http.ResponseWriter, r *http.Request) {
	writeJSON(w, http.StatusOK, map[string]any{"status": s.presidio.InstallStatus()})
}

type createRunRequest struct {
	ProviderID  string `json:"providerId"`
	SourcePath  string `json:"sourcePath"`
	FileName    string `json:"fileName"`
	PageCount   int    `json:"pageCount"`
	OllamaModel string `json:"ollamaModel"`
}

func (s *Server) handleCreateRun(w http.ResponseWriter, r *http.Request) {
	var req createRunRequest
	if err := decodeJSON(r, &req); err != nil {
		writeError(w, http.StatusBadRequest, err)
		return
	}
	provider, ok := s.providers[req.ProviderID]
	if !ok {
		writeError(w, http.StatusBadRequest, fmt.Errorf("unknown provider %q", req.ProviderID))
		return
	}
	if req.PageCount <= 0 {
		writeError(w, http.StatusBadRequest, fmt.Errorf("the PDF does not contain any pages"))
		return
	}
	if _, err := os.Stat(req.SourcePath); err != nil {
		writeError(w, http.StatusBadRequest, fmt.Errorf("could not open %s", req.FileName))
		return
	}
	if req.ProviderID == "ollama" && strings.TrimSpace(req.OllamaModel) == "" {
		writeError(w, http.StatusBadRequest, fmt.Errorf("choose an Ollama model before parsing"))
		return
	}
	run, err := s.store.CreateRun(Run{
		SourcePath:   req.SourcePath,
		FileName:     req.FileName,
		ProviderID:   req.ProviderID,
		ProviderName: provider.Descriptor().Name,
		PageCount:    req.PageCount,
	})
	if err != nil {
		writeError(w, http.StatusInternalServerError, err)
		return
	}
	// Stash the chosen Ollama model on the run directory for page requests.
	if req.OllamaModel != "" {
		_ = os.WriteFile(filepath.Join(RunDirectory(s.store.RunsRoot(), run.ID), "ollama-model.txt"), []byte(req.OllamaModel), 0o644)
	}
	writeJSON(w, http.StatusOK, map[string]any{"run": run})
}

func (s *Server) handleListRuns(w http.ResponseWriter, r *http.Request) {
	sourcePath := r.URL.Query().Get("sourcePath")
	runs, err := s.store.ListRuns(sourcePath, 100)
	if err != nil {
		writeError(w, http.StatusInternalServerError, err)
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{"runs": runs})
}

func (s *Server) handleGetRun(w http.ResponseWriter, r *http.Request) {
	run, err := s.store.GetRun(r.PathValue("id"))
	if err != nil {
		writeError(w, http.StatusNotFound, fmt.Errorf("run not found"))
		return
	}
	completed, _ := s.store.CompletedPages(run.ID)
	writeJSON(w, http.StatusOK, map[string]any{"run": run, "completedPages": completed})
}

func (s *Server) handleRunOutput(w http.ResponseWriter, r *http.Request) {
	markdown, doc, err := s.store.LoadOutput(r.PathValue("id"))
	if err != nil {
		writeError(w, http.StatusNotFound, err)
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{"markdown": markdown, "structured": doc})
}

func (s *Server) handleGetRedactions(w http.ResponseWriter, r *http.Request) {
	detection, err := s.store.LoadRedactions(r.PathValue("id"))
	if err != nil {
		if os.IsNotExist(err) {
			writeJSON(w, http.StatusOK, map[string]any{"detection": nil})
			return
		}
		writeError(w, http.StatusNotFound, err)
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{"detection": detection})
}

func (s *Server) handleDetectRedactions(w http.ResponseWriter, r *http.Request) {
	runID := r.PathValue("id")
	run, err := s.store.GetRun(runID)
	if err != nil {
		writeError(w, http.StatusNotFound, fmt.Errorf("run not found"))
		return
	}
	if run.Status != RunStatusSucceeded {
		writeError(w, http.StatusConflict, fmt.Errorf("finish parsing before detecting PII"))
		return
	}
	var input PresidioAnalyzeRequest
	if err := decodeJSON(r, &input); err != nil {
		writeError(w, http.StatusBadRequest, err)
		return
	}
	_, doc, err := s.store.LoadOutput(runID)
	if err != nil {
		writeError(w, http.StatusConflict, err)
		return
	}
	detection, err := s.presidio.Detect(r.Context(), runID, doc, input)
	if err != nil {
		writeError(w, http.StatusBadGateway, err)
		return
	}
	if err := s.store.SaveRedactions(runID, detection); err != nil {
		writeError(w, http.StatusInternalServerError, err)
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{"detection": detection})
}

func (s *Server) handleSaveRedactedPDF(w http.ResponseWriter, r *http.Request) {
	run, err := s.store.GetRun(r.PathValue("id"))
	if err != nil {
		writeError(w, http.StatusNotFound, fmt.Errorf("run not found"))
		return
	}
	r.Body = http.MaxBytesReader(w, r.Body, 512*1024*1024)
	defer r.Body.Close()
	data, err := io.ReadAll(r.Body)
	if err != nil {
		writeError(w, http.StatusRequestEntityTooLarge, fmt.Errorf("redacted PDF is too large"))
		return
	}
	if !bytes.HasPrefix(data, []byte("%PDF-")) {
		writeError(w, http.StatusBadRequest, fmt.Errorf("request is not a PDF"))
		return
	}
	base := strings.TrimSuffix(run.FileName, filepath.Ext(run.FileName))
	destination, err := SaveTextDialog(r.Context(), "Save redacted PDF", base+".redacted.pdf", "PDF files (*.pdf)|*.pdf")
	if err != nil {
		writeError(w, http.StatusInternalServerError, err)
		return
	}
	if destination == "" {
		writeJSON(w, http.StatusOK, map[string]any{"saved": nil})
		return
	}
	if err := os.WriteFile(destination, data, 0o644); err != nil {
		writeError(w, http.StatusInternalServerError, err)
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{"saved": destination})
}

func (s *Server) handleSaveDocumentCopy(w http.ResponseWriter, r *http.Request) {
	r.Body = http.MaxBytesReader(w, r.Body, 512*1024*1024)
	defer r.Body.Close()
	data, err := io.ReadAll(r.Body)
	if err != nil {
		writeError(w, http.StatusRequestEntityTooLarge, fmt.Errorf("edited PDF is too large"))
		return
	}
	if !bytes.HasPrefix(data, []byte("%PDF-")) {
		writeError(w, http.StatusBadRequest, fmt.Errorf("request is not a PDF"))
		return
	}
	fileName := filepath.Base(strings.TrimSpace(r.URL.Query().Get("fileName")))
	if fileName == "." || fileName == "" {
		fileName = "document.pdf"
	}
	base := strings.TrimSuffix(fileName, filepath.Ext(fileName))
	destination, err := SaveTextDialog(r.Context(), "Save edited PDF", base+".edited.pdf", "PDF files (*.pdf)|*.pdf")
	if err != nil {
		writeError(w, http.StatusInternalServerError, err)
		return
	}
	if destination == "" {
		writeJSON(w, http.StatusOK, map[string]any{"saved": nil})
		return
	}
	if err := os.WriteFile(destination, data, 0o644); err != nil {
		writeError(w, http.StatusInternalServerError, err)
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{"saved": destination})
}

type runPageRequest struct {
	PageNumber  int          `json:"pageNumber"`
	ImageBase64 string       `json:"imageBase64"`
	NativeLines []NativeLine `json:"nativeLines"`
}

func (s *Server) handleRunPage(w http.ResponseWriter, r *http.Request) {
	runID := r.PathValue("id")
	run, err := s.store.GetRun(runID)
	if err != nil {
		writeError(w, http.StatusNotFound, fmt.Errorf("run not found"))
		return
	}
	if run.Status != RunStatusRunning {
		writeError(w, http.StatusConflict, fmt.Errorf("run is %s, not running", run.Status))
		return
	}
	var req runPageRequest
	if err := decodeJSON(r, &req); err != nil {
		writeError(w, http.StatusBadRequest, err)
		return
	}
	if req.PageNumber < 1 || req.PageNumber > run.PageCount {
		writeError(w, http.StatusBadRequest, fmt.Errorf("page %d is out of range", req.PageNumber))
		return
	}

	unlock := s.store.LockRun(runID)
	defer unlock()

	// Skip pages already checkpointed (resume safety).
	completed, _ := s.store.CompletedPages(runID)
	for _, n := range completed {
		if n == req.PageNumber {
			var page Page
			path := filepath.Join(RunDirectory(s.store.RunsRoot(), runID), "page-results", fmt.Sprintf("page-%04d.json", req.PageNumber))
			if err := readJSON(path, &page); err == nil {
				writeJSON(w, http.StatusOK, map[string]any{"page": page, "skipped": true})
				return
			}
		}
	}

	s.store.MarkPageRunning(runID, req.PageNumber)

	imagePath := ""
	imageFile := ""
	if req.ImageBase64 != "" {
		data, err := base64.StdEncoding.DecodeString(req.ImageBase64)
		if err != nil {
			writeError(w, http.StatusBadRequest, fmt.Errorf("invalid page image payload"))
			return
		}
		imageFile = filepath.Join("pages", fmt.Sprintf("page-%04d.png", req.PageNumber))
		imagePath = filepath.Join(RunDirectory(s.store.RunsRoot(), runID), imageFile)
		if err := os.WriteFile(imagePath, data, 0o644); err != nil {
			writeError(w, http.StatusInternalServerError, err)
			return
		}
	}

	provider := s.providers[run.ProviderID]
	if provider == nil {
		writeError(w, http.StatusInternalServerError, fmt.Errorf("provider %q is not installed", run.ProviderID))
		return
	}
	ollamaModel := ""
	if run.ProviderID == "ollama" {
		if data, err := os.ReadFile(filepath.Join(RunDirectory(s.store.RunsRoot(), runID), "ollama-model.txt")); err == nil {
			ollamaModel = strings.TrimSpace(string(data))
		}
	}

	page, err := provider.ProcessPage(r.Context(), PageRequest{
		RunID:       runID,
		PageNumber:  req.PageNumber,
		ImagePath:   imagePath,
		ImageFile:   filepath.ToSlash(imageFile),
		NativeLines: req.NativeLines,
		OllamaModel: ollamaModel,
	})
	if err != nil {
		s.store.MarkPageFailed(runID, req.PageNumber, err.Error())
		if _, failErr := s.store.FailRun(runID, err.Error()); failErr != nil {
			writeError(w, http.StatusInternalServerError, failErr)
			return
		}
		writeError(w, http.StatusUnprocessableEntity, err)
		return
	}
	if err := s.store.SavePageResult(runID, page); err != nil {
		writeError(w, http.StatusInternalServerError, err)
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{"page": page})
}

func (s *Server) handleCompleteRun(w http.ResponseWriter, r *http.Request) {
	run, err := s.store.CompleteRun(r.PathValue("id"))
	if err != nil {
		writeError(w, http.StatusConflict, err)
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{"run": run})
}

func (s *Server) handleCancelRun(w http.ResponseWriter, r *http.Request) {
	run, err := s.store.CancelRun(r.PathValue("id"))
	if err != nil {
		writeError(w, http.StatusNotFound, err)
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{"run": run})
}

func (s *Server) handleFailRun(w http.ResponseWriter, r *http.Request) {
	var req struct {
		Message string `json:"message"`
	}
	if err := decodeJSON(r, &req); err != nil {
		writeError(w, http.StatusBadRequest, err)
		return
	}
	if strings.TrimSpace(req.Message) == "" {
		req.Message = "Parse failed."
	}
	run, err := s.store.FailRun(r.PathValue("id"), req.Message)
	if err != nil {
		writeError(w, http.StatusNotFound, err)
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{"run": run})
}

func (s *Server) handleResumeRun(w http.ResponseWriter, r *http.Request) {
	run, err := s.store.ResumeRun(r.PathValue("id"))
	if err != nil {
		writeError(w, http.StatusConflict, err)
		return
	}
	completed, _ := s.store.CompletedPages(run.ID)
	writeJSON(w, http.StatusOK, map[string]any{"run": run, "completedPages": completed})
}

func (s *Server) handleRevealRun(w http.ResponseWriter, r *http.Request) {
	run, err := s.store.GetRun(r.PathValue("id"))
	if err != nil {
		writeError(w, http.StatusNotFound, fmt.Errorf("run not found"))
		return
	}
	target := RunDirectory(s.store.RunsRoot(), run.ID)
	if run.OutputPath != nil {
		target = *run.OutputPath
	}
	if err := RevealPath(r.Context(), target); err != nil {
		writeError(w, http.StatusNotFound, err)
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{"ok": true})
}

type saveAsRequest struct {
	Kind string `json:"kind"` // "markdown" | "json"
}

func (s *Server) handleSaveAs(w http.ResponseWriter, r *http.Request) {
	run, err := s.store.GetRun(r.PathValue("id"))
	if err != nil {
		writeError(w, http.StatusNotFound, fmt.Errorf("run not found"))
		return
	}
	var req saveAsRequest
	if err := decodeJSON(r, &req); err != nil {
		writeError(w, http.StatusBadRequest, err)
		return
	}
	var source, defaultName, filter, title string
	base := strings.TrimSuffix(run.FileName, filepath.Ext(run.FileName))
	switch req.Kind {
	case "markdown":
		if run.OutputPath == nil {
			writeError(w, http.StatusConflict, fmt.Errorf("run has no Markdown output"))
			return
		}
		source = *run.OutputPath
		defaultName = base + ".md"
		filter = "Markdown files (*.md)|*.md"
		title = "Save Markdown"
	case "json":
		if run.StructuredOutputPath == nil {
			writeError(w, http.StatusConflict, fmt.Errorf("run has no JSON output"))
			return
		}
		source = *run.StructuredOutputPath
		defaultName = base + ".json"
		filter = "JSON files (*.json)|*.json"
		title = "Save JSON"
	default:
		writeError(w, http.StatusBadRequest, fmt.Errorf("unknown output kind %q", req.Kind))
		return
	}
	destination, err := SaveTextDialog(r.Context(), title, defaultName, filter)
	if err != nil {
		writeError(w, http.StatusInternalServerError, err)
		return
	}
	if destination == "" {
		writeJSON(w, http.StatusOK, map[string]any{"saved": nil})
		return
	}
	data, err := os.ReadFile(source)
	if err != nil {
		writeError(w, http.StatusInternalServerError, err)
		return
	}
	if err := os.WriteFile(destination, data, 0o644); err != nil {
		writeError(w, http.StatusInternalServerError, err)
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{"saved": destination})
}

func decodeJSON(r *http.Request, value any) error {
	defer r.Body.Close()
	decoder := json.NewDecoder(r.Body)
	if err := decoder.Decode(value); err != nil {
		return fmt.Errorf("invalid request body: %w", err)
	}
	return nil
}

func writeJSON(w http.ResponseWriter, status int, value any) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(status)
	_ = json.NewEncoder(w).Encode(value)
}

func writeError(w http.ResponseWriter, status int, err error) {
	writeJSON(w, status, map[string]any{"error": err.Error()})
}
