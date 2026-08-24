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
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"sync"
	"time"
)

//go:embed chandra-ocr-worker.py
var chandraWorkerScript []byte

//go:embed install-chandra-ocr.ps1
var chandraInstallScript []byte

// Install phases for managed provider setup.
const (
	InstallPhaseIdle    = "idle"
	InstallPhaseVenv    = "venv"
	InstallPhaseRuntime = "runtime"
	InstallPhaseModel   = "model"
	InstallPhaseVerify  = "verify"
	InstallPhaseDone    = "done"
	InstallPhaseError   = "error"
)

// InstallStatus reports managed setup progress to the UI.
type InstallStatus struct {
	Phase     string     `json:"phase"`
	Message   string     `json:"message"`
	LogTail   []string   `json:"logTail,omitempty"`
	StartedAt *time.Time `json:"startedAt,omitempty"`
	Done      bool       `json:"done"`
}

// ChandraOCRProvider mirrors ChandraOCRProcessingProvider on macOS: a managed,
// pinned, offline-after-setup local parser. The Go backend (client) talks to
// a persistent Python worker (server) over loopback HTTP so the 5.3B model
// loads once per app session instead of once per page.
type ChandraOCRProvider struct {
	root       string
	simulation bool

	mu                 sync.Mutex
	cachedAvailability *Availability

	workerMu sync.Mutex
	worker   *chandraWorker

	installMu     sync.Mutex
	statusMu      sync.RWMutex
	installStatus *InstallStatus
	installCancel context.CancelFunc
}

func NewChandraOCRProvider() *ChandraOCRProvider {
	p := &ChandraOCRProvider{
		root:       filepath.Join(ProvidersRoot(), "chandra-ocr-2"),
		simulation: os.Getenv("OKRA_DESKTOP_SIMULATE_CHANDRA_OCR") == "1",
	}
	// Workers from previous app instances would otherwise linger forever
	// holding ports (and RAM) — reap them at startup.
	p.reapOrphanedWorkers()
	return p
}

// reapOrphanedWorkers kills chandra-ocr-worker processes left behind by
// previous app instances. Best-effort: any error is ignored.
func (p *ChandraOCRProvider) reapOrphanedWorkers() {
	script := `Get-CimInstance Win32_Process -Filter "Name='python.exe'" |
  Where-Object { $_.CommandLine -match 'chandra-ocr-worker\.py' } |
  ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }`
	cmd := exec.Command("powershell.exe", "-NoProfile", "-NonInteractive", "-ExecutionPolicy", "Bypass", "-Command", script)
	hideConsoleWindow(cmd)
	_ = cmd.Run()
}

func (p *ChandraOCRProvider) paths() struct {
	venvPython   string
	modelDir     string
	readyMarker  string
	cacheDir     string
	workerScript string
	installFile  string
	manifestFile string
	statusFile   string
	logFile      string
} {
	return struct {
		venvPython   string
		modelDir     string
		readyMarker  string
		cacheDir     string
		workerScript string
		installFile  string
		manifestFile string
		statusFile   string
		logFile      string
	}{
		venvPython:   filepath.Join(p.root, "venv", "Scripts", "python.exe"),
		modelDir:     filepath.Join(p.root, "model"),
		readyMarker:  filepath.Join(p.root, ".ready"),
		cacheDir:     filepath.Join(p.root, "huggingface"),
		workerScript: filepath.Join(p.root, "chandra-ocr-worker.py"),
		installFile:  filepath.Join(p.root, "install-chandra-ocr.ps1"),
		manifestFile: filepath.Join(p.root, "chandra-manifest.json"),
		statusFile:   filepath.Join(p.root, "install-status.json"),
		logFile:      filepath.Join(p.root, "install.log"),
	}
}

func (p *ChandraOCRProvider) Descriptor() ProviderDescriptor {
	note := fmt.Sprintf(
		"One-time ~%.1f GB model download plus a managed Python runtime. Extraction stays offline after setup. %s",
		float64(ChandraTotalBytes())/1_000_000_000,
		ChandraLicenseNotice,
	)
	return ProviderDescriptor{
		ID:        ChandraProviderID,
		Name:      ChandraProviderName,
		Summary:   "Datalab's Chandra OCR 2 layout parser (5.3B vision model) with labeled blocks, tables, forms, math, and source boxes — fully local after setup.",
		SetupNote: &note,
	}
}

func (p *ChandraOCRProvider) Availability(ctx context.Context) Availability {
	p.mu.Lock()
	defer p.mu.Unlock()
	if p.cachedAvailability != nil {
		return *p.cachedAvailability
	}
	availability := p.computeAvailability()
	p.cachedAvailability = &availability
	return availability
}

func (p *ChandraOCRProvider) computeAvailability() Availability {
	paths := p.paths()
	if p.simulation {
		if _, _, err := findSystemPython(); err != nil {
			return Availability{State: AvailabilityUnavailable, Message: "Python 3 is required for simulation."}
		}
		return Availability{State: AvailabilityReady, Message: "Simulation ready."}
	}

	marker, markerErr := ReadChandraReadyMarker(paths.readyMarker)
	isReady := markerErr == nil &&
		marker.MatchesCurrentRuntime() &&
		HasCurrentModelArtifacts(paths.modelDir)
	if _, err := os.Stat(paths.venvPython); err != nil {
		isReady = false
	}
	if isReady {
		return Availability{State: AvailabilityReady, Message: "Ready offline."}
	}

	// Host gate mirrors LocalParserCatalog requirements on macOS
	// (16 GB+ memory, enough free disk for setup).
	if ram := totalPhysicalMemoryGB(); ram > 0 && ram < 16 {
		return Availability{State: AvailabilityUnavailable, Message: "Chandra OCR 2 requires at least 16 GB of memory."}
	}
	if freeGB := freeDiskGB(p.root); freeGB > 0 && freeGB < 30 {
		return Availability{State: AvailabilityUnavailable, Message: "Chandra OCR 2 setup requires at least 30 GB of free disk space."}
	}
	return Availability{
		State:   AvailabilitySetupRequired,
		Message: fmt.Sprintf("Setup required · ~%.1f GB", float64(ChandraTotalBytes())/1_000_000_000),
	}
}

// ResetAvailability clears the cached probe (after setup completes).
func (p *ChandraOCRProvider) ResetAvailability() {
	p.mu.Lock()
	defer p.mu.Unlock()
	p.cachedAvailability = nil
}

// Install runs the managed setup script, mirroring install-chandra-ocr on
// macOS. Progress is reported through InstallStatus.
func (p *ChandraOCRProvider) Install(ctx context.Context) error {
	p.installMu.Lock()
	defer p.installMu.Unlock()
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
	manifestJSON, err := ChandraManifestJSON()
	if err != nil {
		return err
	}
	if err := os.WriteFile(paths.manifestFile, manifestJSON, 0o644); err != nil {
		return err
	}
	if err := os.WriteFile(paths.installFile, chandraInstallScript, 0o644); err != nil {
		return err
	}

	now := time.Now().UTC()
	p.setInstallStatus(&InstallStatus{Phase: InstallPhaseVenv, Message: "Preparing the managed runtime…", StartedAt: &now})

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
		"-ManifestPath", paths.manifestFile,
		"-StatusPath", paths.statusFile,
	)
	hideConsoleWindow(cmd)
	cmd.Stdout = logFile
	cmd.Stderr = logFile

	if err := cmd.Start(); err != nil {
		p.setInstallStatus(&InstallStatus{Phase: InstallPhaseError, Message: err.Error(), Done: true})
		return err
	}

	// Mirror script status updates into memory while it runs.
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
				if current == nil || current.Phase != InstallPhaseError {
					message := "Setup failed."
					if current != nil && current.Message != "" {
						message = current.Message
					}
					p.setInstallStatus(&InstallStatus{Phase: InstallPhaseError, Message: message, Done: true})
				}
				p.ResetAvailability()
				return fmt.Errorf("chandra OCR 2 setup failed: %w", err)
			}
			p.setInstallStatus(&InstallStatus{Phase: InstallPhaseDone, Message: "Chandra OCR 2 is ready offline.", Done: true})
			p.ResetAvailability()
			return nil
		case <-ticker.C:
			p.refreshInstallStatusFromDisk()
		}
	}
}

func (p *ChandraOCRProvider) setInstallStatus(status *InstallStatus) {
	p.statusMu.Lock()
	defer p.statusMu.Unlock()
	p.installStatus = status
}

func (p *ChandraOCRProvider) refreshInstallStatusFromDisk() {
	data, err := os.ReadFile(p.paths().statusFile)
	if err != nil {
		return
	}
	// PowerShell 5.1 writes UTF-8 with a BOM; tolerate it.
	data = bytes.TrimPrefix(data, []byte{0xEF, 0xBB, 0xBF})
	var status InstallStatus
	if err := json.Unmarshal(data, &status); err == nil && status.Phase != "" {
		if current := p.InstallStatus(); current != nil && current.StartedAt != nil {
			status.StartedAt = current.StartedAt
		}
		p.setInstallStatus(&status)
	}
	// Keep a short log tail for the UI.
	if logData, err := os.ReadFile(p.paths().logFile); err == nil {
		lines := strings.Split(strings.TrimRight(string(logData), "\r\n"), "\n")
		if len(lines) > 6 {
			lines = lines[len(lines)-6:]
		}
		if current := p.InstallStatus(); current != nil {
			current.LogTail = lines
			p.setInstallStatus(current)
		}
	}
}

// InstallStatus returns the current setup status, if any.
func (p *ChandraOCRProvider) InstallStatus() *InstallStatus {
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

// ProcessPage forwards one rendered page to the persistent worker (client →
// server) and adapts its structured page JSON to the shared contract. When
// the worker died between pages it is respawned once transparently.
func (p *ChandraOCRProvider) ProcessPage(ctx context.Context, req PageRequest) (Page, error) {
	if req.ImagePath == "" {
		return Page{}, fmt.Errorf("Chandra OCR 2 needs a rendered page image (page %d)", req.PageNumber)
	}
	page, err := p.processPageOnce(ctx, req)
	if err == nil {
		return page, nil
	}
	p.dropWorker()
	page, retryErr := p.processPageOnce(ctx, req)
	if retryErr != nil {
		p.dropWorker()
		return Page{}, err
	}
	return page, nil
}

func (p *ChandraOCRProvider) processPageOnce(ctx context.Context, req PageRequest) (Page, error) {
	worker, err := p.ensureWorker(ctx)
	if err != nil {
		return Page{}, err
	}
	if err := worker.waitReady(ctx); err != nil {
		return Page{}, err
	}
	page, err := worker.processPage(ctx, req.PageNumber, req.ImagePath, req.ImageFile)
	if err != nil {
		return Page{}, err
	}
	return page, nil
}

// Shutdown stops the persistent worker (app exit).
func (p *ChandraOCRProvider) Shutdown() {
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

func (p *ChandraOCRProvider) dropWorker() {
	p.workerMu.Lock()
	defer p.workerMu.Unlock()
	if p.worker != nil {
		p.worker.stop()
		p.worker = nil
	}
}

func (p *ChandraOCRProvider) ensureWorker(ctx context.Context) (*chandraWorker, error) {
	p.workerMu.Lock()
	defer p.workerMu.Unlock()
	if p.worker != nil && p.worker.alive() {
		return p.worker, nil
	}

	paths := p.paths()
	if err := os.MkdirAll(p.root, 0o755); err != nil {
		return nil, err
	}
	if err := os.WriteFile(paths.workerScript, chandraWorkerScript, 0o644); err != nil {
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
	} else {
		if _, err := os.Stat(paths.venvPython); err != nil {
			return nil, fmt.Errorf("set up Chandra OCR 2 before extracting")
		}
		workerArgs = append(workerArgs, "--model", paths.modelDir)
	}

	// The worker is a session-long process; it must NOT be tied to the
	// request context (a canceled page request would kill the process).
	// It is stopped by Shutdown/dropWorker instead.
	cmd := exec.CommandContext(context.Background(), python, append(pythonArgs, workerArgs...)...)
	hideConsoleWindow(cmd)
	cmd.Env = append(os.Environ(),
		"HF_HOME="+paths.cacheDir,
		"HF_HUB_OFFLINE=1",
		"TRANSFORMERS_OFFLINE=1",
		"HF_DATASETS_OFFLINE=1",
		"PYTHONUNBUFFERED=1",
		"PYTHONDONTWRITEBYTECODE=1",
	)
	stdout, err := cmd.StdoutPipe()
	if err != nil {
		return nil, err
	}
	cmd.Stderr = nil
	logFile, _ := os.OpenFile(paths.logFile, os.O_CREATE|os.O_APPEND|os.O_WRONLY, 0o644)
	if logFile != nil {
		cmd.Stderr = logFile
	}
	if err := cmd.Start(); err != nil {
		return nil, err
	}

	worker := &chandraWorker{cmd: cmd, client: &http.Client{}, simulation: p.simulation, logFile: logFile}
	// Track the pid for crash analysis and cross-instance orphan reaping.
	pidFile := filepath.Join(p.root, "worker.pid")
	_ = os.WriteFile(pidFile, []byte(fmt.Sprintf("%d", cmd.Process.Pid)), 0o644)
	worker.pidFile = pidFile
	// The worker announces {"port": N} on its first stdout line, then we
	// drain the rest into the log file.
	portChan := make(chan int, 1)
	errChan := make(chan error, 1)
	go func() {
		reader := bufio.NewReader(stdout)
		line, err := reader.ReadString('\n')
		if err != nil {
			errChan <- fmt.Errorf("worker exited before announcing its port")
			return
		}
		var announcement struct {
			Port int `json:"port"`
		}
		if err := json.Unmarshal([]byte(strings.TrimSpace(line)), &announcement); err != nil || announcement.Port <= 0 {
			errChan <- fmt.Errorf("unexpected worker announcement: %s", strings.TrimSpace(line))
			return
		}
		portChan <- announcement.Port
		if logFile != nil {
			_, _ = io.Copy(logFile, reader)
		} else {
			_, _ = io.Copy(io.Discard, reader)
		}
	}()

	select {
	case port := <-portChan:
		worker.baseURL = fmt.Sprintf("http://127.0.0.1:%d", port)
	case err := <-errChan:
		_ = cmd.Process.Kill()
		return nil, err
	case <-time.After(60 * time.Second):
		_ = cmd.Process.Kill()
		return nil, fmt.Errorf("timed out waiting for the Chandra OCR 2 worker to start")
	case <-ctx.Done():
		_ = cmd.Process.Kill()
		return nil, ctx.Err()
	}

	p.worker = worker
	return worker, nil
}

// chandraWorker is the persistent Python inference server.
type chandraWorker struct {
	cmd        *exec.Cmd
	baseURL    string
	client     *http.Client
	simulation bool
	logFile    *os.File
	pidFile    string
}

func (w *chandraWorker) alive() bool {
	if w.cmd == nil || w.cmd.Process == nil || w.cmd.ProcessState != nil {
		return false
	}
	return processAlive(w.cmd.Process.Pid)
}

func (w *chandraWorker) stop() {
	if w.cmd != nil && w.cmd.Process != nil {
		_ = w.cmd.Process.Kill()
		_ = w.cmd.Wait()
	}
	if w.logFile != nil {
		_ = w.logFile.Close()
		w.logFile = nil
	}
	if w.pidFile != "" {
		_ = os.Remove(w.pidFile)
	}
}

func (w *chandraWorker) waitReady(ctx context.Context) error {
	// Model load can take minutes on CPU; wait generously, but bail fast
	// when the worker process is gone or reports a load failure.
	readyCtx, cancel := context.WithTimeout(ctx, 20*time.Minute)
	defer cancel()
	for {
		if !w.alive() {
			return fmt.Errorf("the Chandra OCR 2 worker exited before it was ready")
		}
		req, err := http.NewRequestWithContext(readyCtx, http.MethodGet, w.baseURL+"/health", nil)
		if err != nil {
			return err
		}
		res, err := w.client.Do(req)
		if err == nil && res.StatusCode == http.StatusOK {
			var health struct {
				Loaded    bool   `json:"loaded"`
				LoadError string `json:"loadError"`
			}
			_ = json.NewDecoder(res.Body).Decode(&health)
			res.Body.Close()
			if health.LoadError != "" {
				return fmt.Errorf("the Chandra OCR 2 worker failed to load the model: %s", health.LoadError)
			}
			if health.Loaded {
				return nil
			}
		} else if res != nil {
			res.Body.Close()
		}
		select {
		case <-readyCtx.Done():
			return fmt.Errorf("the Chandra OCR 2 worker did not finish loading the model")
		case <-time.After(2 * time.Second):
		}
	}
}

func (w *chandraWorker) processPage(ctx context.Context, pageNumber int, imagePath, imageFile string) (Page, error) {
	body, err := json.Marshal(map[string]any{
		"page_number": pageNumber,
		"image_path":  imagePath,
		"image_file":  imageFile,
	})
	if err != nil {
		return Page{}, err
	}
	pageCtx, cancel := context.WithTimeout(ctx, 90*time.Minute)
	defer cancel()
	req, err := http.NewRequestWithContext(pageCtx, http.MethodPost, w.baseURL+"/page", strings.NewReader(string(body)))
	if err != nil {
		return Page{}, err
	}
	req.Header.Set("Content-Type", "application/json")
	res, err := w.client.Do(req)
	if err != nil {
		return Page{}, err
	}
	defer res.Body.Close()
	data, err := io.ReadAll(res.Body)
	if err != nil {
		return Page{}, err
	}
	if res.StatusCode != http.StatusOK {
		var workerErr struct {
			Error string `json:"error"`
		}
		if json.Unmarshal(data, &workerErr) == nil && workerErr.Error != "" {
			return Page{}, fmt.Errorf("Chandra OCR 2: %s", workerErr.Error)
		}
		return Page{}, fmt.Errorf("Chandra OCR 2 worker returned status %d", res.StatusCode)
	}
	var page Page
	if err := json.Unmarshal(data, &page); err != nil {
		return Page{}, fmt.Errorf("Chandra OCR 2 returned invalid page JSON: %w", err)
	}
	return page, nil
}

// findSystemPython locates a Python 3.10+ interpreter for simulation mode,
// returning the executable and any leading arguments (e.g. "py", "-3").
func findSystemPython() (string, []string, error) {
	candidates := [][]string{
		{"py", "-3"},
		{"python"},
		{"python3"},
	}
	for _, candidate := range candidates {
		path, err := exec.LookPath(candidate[0])
		if err != nil {
			continue
		}
		probeArgs := append(append([]string{}, candidate[1:]...), "--version")
		out, err := exec.Command(path, probeArgs...).Output()
		if err != nil {
			continue
		}
		version := strings.TrimSpace(strings.TrimPrefix(string(out), "Python "))
		parts := strings.Split(version, ".")
		if len(parts) >= 2 {
			var major, minor int
			fmt.Sscanf(parts[0], "%d", &major)
			fmt.Sscanf(parts[1], "%d", &minor)
			if major == 3 && minor >= 10 {
				return path, candidate[1:], nil
			}
		}
	}
	return "", nil, fmt.Errorf("Python 3.10 or later is required (install it from python.org)")
}
