package okra

import (
	"bufio"
	"bytes"
	"context"
	_ "embed"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"net/url"
	"os"
	"os/exec"
	"path/filepath"
	"sort"
	"strings"
	"sync"
	"time"
	"unicode/utf8"
)

const (
	presidioVersion   = "2.2.364"
	spacyModelVersion = "3.8.0"
)

//go:embed presidio-worker.py
var presidioWorkerScript []byte

//go:embed install-presidio.ps1
var presidioInstallScript []byte

// PresidioStatus describes the local detector independently from parser
// providers. Detection is a post-parse operation, not another OCR provider.
type PresidioStatus struct {
	Availability    Availability `json:"availability"`
	Running         bool         `json:"running"`
	Managed         bool         `json:"managed"`
	OllamaSupported bool         `json:"ollamaSupported"`
}

type PresidioAnalyzeRequest struct {
	Entities    []string `json:"entities,omitempty"`
	MinScore    float64  `json:"minScore,omitempty"`
	OllamaModel string   `json:"ollamaModel,omitempty"`
}

type presidioResult struct {
	EntityType string  `json:"entity_type"`
	Start      int     `json:"start"`
	End        int     `json:"end"`
	Score      float64 `json:"score"`
	Text       string  `json:"text,omitempty"`
}

// RedactionBox is the shared S-REDACT box-JSON seam: normalized top-left
// coordinates, detector provenance, and the source block used for review.
type RedactionBox struct {
	ID      string  `json:"id"`
	Page    int     `json:"page"`
	X       float64 `json:"x"`
	Y       float64 `json:"y"`
	Width   float64 `json:"w"`
	Height  float64 `json:"h"`
	Type    string  `json:"type"`
	Text    string  `json:"text"`
	Score   float64 `json:"score"`
	Source  string  `json:"source"`
	BlockID string  `json:"blockId"`
}

type RedactionStats struct {
	Total    int            `json:"total"`
	ByType   map[string]int `json:"byType"`
	BySource map[string]int `json:"bySource"`
}

type RedactionDetection struct {
	SchemaVersion int            `json:"schemaVersion"`
	Object        string         `json:"object"`
	RunID         string         `json:"runId"`
	CreatedAt     time.Time      `json:"createdAt"`
	OllamaModel   string         `json:"ollamaModel,omitempty"`
	Boxes         []RedactionBox `json:"boxes"`
	Stats         RedactionStats `json:"stats"`
}

type PresidioService struct {
	root        string
	externalURL string
	simulation  bool

	workerMu sync.Mutex
	worker   *presidioWorker

	installMu     sync.Mutex
	statusMu      sync.RWMutex
	installStatus *InstallStatus
	installCancel context.CancelFunc
}

func NewPresidioService() *PresidioService {
	external := strings.TrimRight(strings.TrimSpace(os.Getenv("OKRA_PRESIDIO_URL")), "/")
	p := &PresidioService{
		root:        filepath.Join(ProvidersRoot(), "presidio"),
		externalURL: external,
		simulation:  os.Getenv("OKRA_DESKTOP_SIMULATE_PRESIDIO") == "1",
	}
	p.reapOrphanedWorkers()
	return p
}

func (p *PresidioService) paths() struct {
	venvPython   string
	readyMarker  string
	workerScript string
	installFile  string
	statusFile   string
	logFile      string
} {
	return struct {
		venvPython   string
		readyMarker  string
		workerScript string
		installFile  string
		statusFile   string
		logFile      string
	}{
		venvPython:   filepath.Join(p.root, "venv", "Scripts", "python.exe"),
		readyMarker:  filepath.Join(p.root, ".ready"),
		workerScript: filepath.Join(p.root, "presidio-worker.py"),
		installFile:  filepath.Join(p.root, "install-presidio.ps1"),
		statusFile:   filepath.Join(p.root, "install-status.json"),
		logFile:      filepath.Join(p.root, "presidio.log"),
	}
}

func (p *PresidioService) reapOrphanedWorkers() {
	if p.externalURL != "" {
		return
	}
	script := `Get-CimInstance Win32_Process -Filter "Name='python.exe'" |
  Where-Object { $_.CommandLine -match 'presidio-worker\.py' } |
  ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }`
	cmd := exec.Command("powershell.exe", "-NoProfile", "-NonInteractive", "-ExecutionPolicy", "Bypass", "-Command", script)
	hideConsoleWindow(cmd)
	_ = cmd.Run()
}

func (p *PresidioService) Status(ctx context.Context) PresidioStatus {
	availability := p.Availability(ctx)
	p.workerMu.Lock()
	running := p.worker != nil && p.worker.alive()
	p.workerMu.Unlock()
	return PresidioStatus{
		Availability:    availability,
		Running:         running,
		Managed:         p.externalURL == "",
		OllamaSupported: p.externalURL == "",
	}
}

func (p *PresidioService) Availability(ctx context.Context) Availability {
	if p.externalURL != "" {
		if _, err := loopbackBaseURL(p.externalURL); err != nil {
			return Availability{State: AvailabilityUnavailable, Message: err.Error()}
		}
		probeCtx, cancel := context.WithTimeout(ctx, 1500*time.Millisecond)
		defer cancel()
		req, _ := http.NewRequestWithContext(probeCtx, http.MethodGet, p.externalURL+"/health", nil)
		res, err := http.DefaultClient.Do(req)
		if err != nil {
			return Availability{State: AvailabilityUnavailable, Message: "Presidio is not reachable on loopback."}
		}
		res.Body.Close()
		if res.StatusCode != http.StatusOK {
			return Availability{State: AvailabilityUnavailable, Message: fmt.Sprintf("Presidio returned status %d.", res.StatusCode)}
		}
		return Availability{State: AvailabilityReady, Message: "Connected to local Presidio."}
	}
	if p.simulation {
		if _, _, err := findSystemPython(); err != nil {
			return Availability{State: AvailabilityUnavailable, Message: "Python 3.10+ is required for Presidio simulation."}
		}
		return Availability{State: AvailabilityReady, Message: "Presidio simulation ready."}
	}
	paths := p.paths()
	if _, err := os.Stat(paths.venvPython); err != nil {
		return Availability{State: AvailabilitySetupRequired, Message: "Setup required · Microsoft Presidio + English spaCy model"}
	}
	var marker struct {
		PresidioVersion   string `json:"presidioVersion"`
		SpacyModelVersion string `json:"spacyModelVersion"`
	}
	if err := readJSON(paths.readyMarker, &marker); err != nil || marker.PresidioVersion != presidioVersion || marker.SpacyModelVersion != spacyModelVersion {
		return Availability{State: AvailabilitySetupRequired, Message: "Setup update required · Microsoft Presidio + English spaCy model"}
	}
	return Availability{State: AvailabilityReady, Message: "Ready locally."}
}

func (p *PresidioService) Install(ctx context.Context) error {
	p.installMu.Lock()
	defer p.installMu.Unlock()
	if p.externalURL != "" {
		return fmt.Errorf("managed setup is disabled when OKRA_PRESIDIO_URL is set")
	}
	if p.simulation {
		return fmt.Errorf("simulation mode does not require setup")
	}
	if status := p.InstallStatus(); status != nil && !status.Done && status.Phase != InstallPhaseIdle && status.Phase != InstallPhaseError {
		return fmt.Errorf("setup is already running")
	}
	paths := p.paths()
	if err := os.MkdirAll(p.root, 0o755); err != nil {
		return err
	}
	if err := os.WriteFile(paths.installFile, presidioInstallScript, 0o644); err != nil {
		return err
	}
	now := time.Now().UTC()
	p.setInstallStatus(&InstallStatus{Phase: InstallPhaseVenv, Message: "Preparing the managed Presidio runtime…", StartedAt: &now})

	installCtx, cancel := context.WithCancel(context.Background())
	p.installCancel = cancel
	defer func() { p.installCancel = nil }()
	logFile, err := os.Create(paths.logFile)
	if err != nil {
		return err
	}
	defer logFile.Close()
	cmd := exec.CommandContext(installCtx, "powershell.exe",
		"-NoProfile", "-NonInteractive", "-ExecutionPolicy", "Bypass",
		"-File", paths.installFile,
		"-Root", p.root,
		"-StatusPath", paths.statusFile,
	)
	hideConsoleWindow(cmd)
	cmd.Stdout = logFile
	cmd.Stderr = logFile
	if err := cmd.Start(); err != nil {
		p.setInstallStatus(&InstallStatus{Phase: InstallPhaseError, Message: err.Error(), Done: true})
		return err
	}
	done := make(chan error, 1)
	go func() { done <- cmd.Wait() }()
	ticker := time.NewTicker(1500 * time.Millisecond)
	defer ticker.Stop()
	for {
		select {
		case err := <-done:
			p.refreshInstallStatusFromDisk()
			if err != nil {
				current := p.InstallStatus()
				message := "Presidio setup failed."
				if current != nil && current.Message != "" {
					message = current.Message
				}
				p.setInstallStatus(&InstallStatus{Phase: InstallPhaseError, Message: message, Done: true})
				return fmt.Errorf("presidio setup failed: %w", err)
			}
			p.setInstallStatus(&InstallStatus{Phase: InstallPhaseDone, Message: "Microsoft Presidio is ready locally.", Done: true})
			return nil
		case <-ticker.C:
			p.refreshInstallStatusFromDisk()
		}
	}
}

func (p *PresidioService) setInstallStatus(status *InstallStatus) {
	p.statusMu.Lock()
	defer p.statusMu.Unlock()
	p.installStatus = status
}

func (p *PresidioService) refreshInstallStatusFromDisk() {
	data, err := os.ReadFile(p.paths().statusFile)
	if err != nil {
		return
	}
	data = bytes.TrimPrefix(data, []byte{0xEF, 0xBB, 0xBF})
	var status InstallStatus
	if err := json.Unmarshal(data, &status); err == nil && status.Phase != "" {
		p.statusMu.RLock()
		current := p.installStatus
		p.statusMu.RUnlock()
		if current != nil && current.StartedAt != nil {
			status.StartedAt = current.StartedAt
		}
		p.setInstallStatus(&status)
	}
	if logData, err := os.ReadFile(p.paths().logFile); err == nil {
		lines := strings.Split(strings.TrimRight(string(logData), "\r\n"), "\n")
		if len(lines) > 6 {
			lines = lines[len(lines)-6:]
		}
		p.statusMu.RLock()
		current := p.installStatus
		p.statusMu.RUnlock()
		if current != nil {
			current.LogTail = lines
			p.setInstallStatus(current)
		}
	}
}

func (p *PresidioService) InstallStatus() *InstallStatus {
	p.statusMu.RLock()
	status := p.installStatus
	p.statusMu.RUnlock()
	if status != nil {
		return status
	}
	p.refreshInstallStatusFromDisk()
	p.statusMu.RLock()
	defer p.statusMu.RUnlock()
	return p.installStatus
}

func (p *PresidioService) Detect(ctx context.Context, runID string, doc *StructuredDocument, input PresidioAnalyzeRequest) (*RedactionDetection, error) {
	if doc == nil {
		return nil, fmt.Errorf("run %s has no structured output", runID)
	}
	if input.MinScore <= 0 {
		input.MinScore = 0.5
	}
	if input.MinScore > 1 {
		return nil, fmt.Errorf("minScore must be between 0 and 1")
	}
	baseURL, managed, err := p.baseURL(ctx)
	if err != nil {
		return nil, err
	}
	if input.OllamaModel != "" && !managed {
		return nil, fmt.Errorf("model selection is available only with Okra's managed Presidio worker")
	}

	boxes := make([]RedactionBox, 0)
	seen := map[string]int{}
	for _, page := range doc.Pages {
		text, spans := joinPositionedBlocks(page.Blocks)
		if text == "" {
			continue
		}
		results, err := analyzeWithPresidio(ctx, baseURL, text, input)
		if err != nil {
			return nil, fmt.Errorf("page %d: %w", page.PageNumber, err)
		}
		for resultIndex, result := range results {
			if result.Score < input.MinScore || result.End <= result.Start {
				continue
			}
			for _, span := range spans {
				if result.End <= span.Start || result.Start >= span.End || span.Block.BBox == nil {
					continue
				}
				bbox := span.Block.BBox
				if bbox.Width <= 0 || bbox.Height <= 0 {
					continue
				}
				value := result.Text
				if value == "" {
					value = runeSlice(text, result.Start, result.End)
				}
				source := "presidio"
				if input.OllamaModel != "" {
					source = "presidio+ollama"
				}
				key := fmt.Sprintf("%d|%s|%s|%d|%d", page.PageNumber, span.Block.ID, result.EntityType, result.Start, result.End)
				if existing, ok := seen[key]; ok {
					if result.Score > boxes[existing].Score {
						boxes[existing].Score = result.Score
					}
					continue
				}
				box := RedactionBox{
					ID:      fmt.Sprintf("pii-%d-%d-%d", page.PageNumber, span.Index, resultIndex),
					Page:    page.PageNumber,
					X:       clamp01(bbox.X),
					Y:       clamp01(bbox.Y),
					Width:   clampSize(bbox.X, bbox.Width),
					Height:  clampSize(bbox.Y, bbox.Height),
					Type:    result.EntityType,
					Text:    value,
					Score:   result.Score,
					Source:  source,
					BlockID: span.Block.ID,
				}
				seen[key] = len(boxes)
				boxes = append(boxes, box)
			}
		}
	}
	sort.Slice(boxes, func(i, j int) bool {
		if boxes[i].Page != boxes[j].Page {
			return boxes[i].Page < boxes[j].Page
		}
		if boxes[i].Y != boxes[j].Y {
			return boxes[i].Y < boxes[j].Y
		}
		if boxes[i].X != boxes[j].X {
			return boxes[i].X < boxes[j].X
		}
		return boxes[i].Type < boxes[j].Type
	})
	stats := RedactionStats{Total: len(boxes), ByType: map[string]int{}, BySource: map[string]int{}}
	for _, box := range boxes {
		stats.ByType[box.Type]++
		stats.BySource[box.Source]++
	}
	return &RedactionDetection{
		SchemaVersion: 1,
		Object:        "pii_redaction_candidates",
		RunID:         runID,
		CreatedAt:     time.Now().UTC(),
		OllamaModel:   input.OllamaModel,
		Boxes:         boxes,
		Stats:         stats,
	}, nil
}

type positionedBlockSpan struct {
	Index int
	Start int
	End   int
	Block Block
}

func joinPositionedBlocks(blocks []Block) (string, []positionedBlockSpan) {
	var builder strings.Builder
	spans := make([]positionedBlockSpan, 0, len(blocks))
	offset := 0
	for index, block := range blocks {
		text := strings.TrimSpace(block.Text)
		if text == "" || block.BBox == nil {
			continue
		}
		if builder.Len() > 0 {
			builder.WriteByte('\n')
			offset++
		}
		start := offset
		builder.WriteString(text)
		offset += utf8.RuneCountInString(text)
		spans = append(spans, positionedBlockSpan{Index: index, Start: start, End: offset, Block: block})
	}
	return builder.String(), spans
}

func analyzeWithPresidio(ctx context.Context, baseURL, text string, input PresidioAnalyzeRequest) ([]presidioResult, error) {
	body, err := json.Marshal(map[string]any{
		"text":            text,
		"language":        "en",
		"entities":        input.Entities,
		"score_threshold": input.MinScore,
		"ollama_model":    input.OllamaModel,
	})
	if err != nil {
		return nil, err
	}
	timeout := 2 * time.Minute
	if input.OllamaModel != "" {
		timeout = 20 * time.Minute
	}
	requestCtx, cancel := context.WithTimeout(ctx, timeout)
	defer cancel()
	req, err := http.NewRequestWithContext(requestCtx, http.MethodPost, baseURL+"/analyze", bytes.NewReader(body))
	if err != nil {
		return nil, err
	}
	req.Header.Set("Content-Type", "application/json")
	res, err := http.DefaultClient.Do(req)
	if err != nil {
		return nil, fmt.Errorf("Presidio is not reachable on loopback")
	}
	defer res.Body.Close()
	data, err := io.ReadAll(io.LimitReader(res.Body, 4*1024*1024))
	if err != nil {
		return nil, err
	}
	if res.StatusCode != http.StatusOK {
		var serviceError struct {
			Error string `json:"error"`
		}
		if json.Unmarshal(data, &serviceError) == nil && serviceError.Error != "" {
			return nil, fmt.Errorf("Presidio: %s", serviceError.Error)
		}
		return nil, fmt.Errorf("Presidio returned status %d", res.StatusCode)
	}
	var results []presidioResult
	if err := json.Unmarshal(data, &results); err != nil {
		return nil, fmt.Errorf("Presidio returned invalid JSON: %w", err)
	}
	return results, nil
}

func (p *PresidioService) baseURL(ctx context.Context) (string, bool, error) {
	if p.externalURL != "" {
		base, err := loopbackBaseURL(p.externalURL)
		return base, false, err
	}
	worker, err := p.ensureWorker(ctx)
	if err != nil {
		return "", true, err
	}
	if err := worker.waitReady(ctx); err != nil {
		return "", true, err
	}
	return worker.baseURL, true, nil
}

func (p *PresidioService) ensureWorker(ctx context.Context) (*presidioWorker, error) {
	p.workerMu.Lock()
	defer p.workerMu.Unlock()
	if p.worker != nil && p.worker.alive() {
		return p.worker, nil
	}
	if availability := p.Availability(ctx); availability.State != AvailabilityReady {
		return nil, fmt.Errorf("%s", availability.Message)
	}
	paths := p.paths()
	if err := os.MkdirAll(p.root, 0o755); err != nil {
		return nil, err
	}
	if err := os.WriteFile(paths.workerScript, presidioWorkerScript, 0o644); err != nil {
		return nil, err
	}

	python := paths.venvPython
	pythonArgs := []string{}
	workerArgs := []string{paths.workerScript, "serve", "--host", "127.0.0.1", "--port", "0"}
	if p.simulation {
		systemPython, leadingArgs, err := findSystemPython()
		if err != nil {
			return nil, err
		}
		python = systemPython
		pythonArgs = leadingArgs
		workerArgs = append(workerArgs, "--simulate")
	}
	cmd := exec.CommandContext(context.Background(), python, append(pythonArgs, workerArgs...)...)
	hideConsoleWindow(cmd)
	ollamaHost := "http://127.0.0.1:11434"
	if value := strings.TrimSpace(os.Getenv("OLLAMA_HOST")); value != "" {
		if normalized, err := loopbackBaseURL(value); err == nil {
			ollamaHost = normalized
		}
	}
	cmd.Env = append(os.Environ(),
		"PYTHONUNBUFFERED=1",
		"PYTHONDONTWRITEBYTECODE=1",
		"OLLAMA_HOST="+ollamaHost,
	)
	stdout, err := cmd.StdoutPipe()
	if err != nil {
		return nil, err
	}
	// Inference output is deliberately discarded: third-party recognizers may
	// include analyzed text in diagnostic logs, and raw PII must not persist.
	cmd.Stderr = io.Discard
	if err := cmd.Start(); err != nil {
		return nil, err
	}
	worker := &presidioWorker{cmd: cmd, client: &http.Client{}}
	pidFile := filepath.Join(p.root, "worker.pid")
	_ = os.WriteFile(pidFile, []byte(fmt.Sprintf("%d", cmd.Process.Pid)), 0o644)
	worker.pidFile = pidFile

	portChan := make(chan int, 1)
	errChan := make(chan error, 1)
	go func() {
		reader := bufio.NewReader(stdout)
		line, err := reader.ReadString('\n')
		if err != nil {
			errChan <- fmt.Errorf("Presidio worker exited before announcing its port")
			return
		}
		var announcement struct {
			Port int `json:"port"`
		}
		if err := json.Unmarshal([]byte(strings.TrimSpace(line)), &announcement); err != nil || announcement.Port <= 0 {
			errChan <- fmt.Errorf("unexpected Presidio worker announcement")
			return
		}
		portChan <- announcement.Port
		_, _ = io.Copy(io.Discard, reader)
	}()
	select {
	case port := <-portChan:
		worker.baseURL = fmt.Sprintf("http://127.0.0.1:%d", port)
	case err := <-errChan:
		_ = cmd.Process.Kill()
		return nil, err
	case <-time.After(60 * time.Second):
		_ = cmd.Process.Kill()
		return nil, fmt.Errorf("timed out waiting for the Presidio worker to start")
	case <-ctx.Done():
		_ = cmd.Process.Kill()
		return nil, ctx.Err()
	}
	p.worker = worker
	return worker, nil
}

func (p *PresidioService) Shutdown() {
	p.workerMu.Lock()
	defer p.workerMu.Unlock()
	if p.worker != nil {
		p.worker.stop()
		p.worker = nil
	}
	if p.installCancel != nil {
		p.installCancel()
	}
}

type presidioWorker struct {
	cmd     *exec.Cmd
	baseURL string
	client  *http.Client
	pidFile string
}

func (w *presidioWorker) alive() bool {
	return w != nil && w.cmd != nil && w.cmd.Process != nil && w.cmd.ProcessState == nil && processAlive(w.cmd.Process.Pid)
}

func (w *presidioWorker) stop() {
	if w.cmd != nil && w.cmd.Process != nil {
		_ = w.cmd.Process.Kill()
		_ = w.cmd.Wait()
	}
	if w.pidFile != "" {
		_ = os.Remove(w.pidFile)
	}
}

func (w *presidioWorker) waitReady(ctx context.Context) error {
	readyCtx, cancel := context.WithTimeout(ctx, 3*time.Minute)
	defer cancel()
	for {
		if !w.alive() {
			return fmt.Errorf("the Presidio worker exited before it was ready")
		}
		req, _ := http.NewRequestWithContext(readyCtx, http.MethodGet, w.baseURL+"/health", nil)
		res, err := w.client.Do(req)
		if err == nil && res.StatusCode == http.StatusOK {
			var health struct {
				Loaded    bool   `json:"loaded"`
				LoadError string `json:"loadError"`
			}
			_ = json.NewDecoder(res.Body).Decode(&health)
			res.Body.Close()
			if health.LoadError != "" {
				return fmt.Errorf("the Presidio worker failed to load: %s", health.LoadError)
			}
			if health.Loaded {
				return nil
			}
		} else if res != nil {
			res.Body.Close()
		}
		select {
		case <-readyCtx.Done():
			return fmt.Errorf("the Presidio worker did not finish loading")
		case <-time.After(500 * time.Millisecond):
		}
	}
}

func loopbackBaseURL(value string) (string, error) {
	parsed, err := url.Parse(strings.TrimRight(strings.TrimSpace(value), "/"))
	if err != nil || parsed.Scheme == "" || parsed.Host == "" {
		return "", fmt.Errorf("Presidio needs a valid loopback URL")
	}
	host := strings.ToLower(parsed.Hostname())
	if parsed.Scheme != "http" && parsed.Scheme != "https" {
		return "", fmt.Errorf("Presidio URL must use HTTP or HTTPS")
	}
	if host != "127.0.0.1" && host != "localhost" && host != "::1" {
		return "", fmt.Errorf("Presidio must use a loopback URL")
	}
	parsed.RawQuery = ""
	parsed.Fragment = ""
	parsed.Path = strings.TrimRight(parsed.Path, "/")
	return parsed.String(), nil
}

func runeSlice(value string, start, end int) string {
	runes := []rune(value)
	if start < 0 {
		start = 0
	}
	if end > len(runes) {
		end = len(runes)
	}
	if start >= end || start >= len(runes) {
		return ""
	}
	return string(runes[start:end])
}

func clamp01(value float64) float64 {
	if value < 0 {
		return 0
	}
	if value > 1 {
		return 1
	}
	return value
}

func clampSize(start, size float64) float64 {
	if size < 0 {
		return 0
	}
	if start+size > 1 {
		return 1 - clamp01(start)
	}
	return size
}
