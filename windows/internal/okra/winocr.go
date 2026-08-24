package okra

import (
	"context"
	_ "embed"
	"encoding/json"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"sync"
	"time"
)

//go:embed ocrbridge.ps1
var ocrBridgeScript []byte

// WindowsOCRProvider is the Windows equivalent of AppleVisionProcessingProvider:
// zero-setup OCR via the built-in Windows.Media.Ocr WinRT engine, with an
// embedded-text fast path for born-digital pages (pdf-text-line blocks).
type WindowsOCRProvider struct {
	mu            sync.Mutex
	checked       bool
	availability  Availability
	bridgePath    string
	powershellBin string
}

func NewWindowsOCRProvider() *WindowsOCRProvider {
	return &WindowsOCRProvider{}
}

func (p *WindowsOCRProvider) Descriptor() ProviderDescriptor {
	return ProviderDescriptor{
		ID:      "windows-ocr",
		Name:    "Windows OCR",
		Summary: "Built into Windows. Uses embedded text when a page has it, otherwise on-device OCR. No setup.",
	}
}

func (p *WindowsOCRProvider) Availability(ctx context.Context) Availability {
	p.mu.Lock()
	defer p.mu.Unlock()
	if p.checked {
		return p.availability
	}
	p.availability = p.checkAvailability(ctx)
	p.checked = true
	return p.availability
}

// ResetAvailability clears the cached probe (used by tests and manual refresh).
func (p *WindowsOCRProvider) ResetAvailability() {
	p.mu.Lock()
	defer p.mu.Unlock()
	p.checked = false
}

func (p *WindowsOCRProvider) checkAvailability(ctx context.Context) Availability {
	if err := p.ensureBridge(); err != nil {
		return Availability{State: AvailabilityUnavailable, Message: "Could not prepare the Windows OCR bridge: " + err.Error()}
	}
	checkCtx, cancel := context.WithTimeout(ctx, 60*time.Second)
	defer cancel()
	out, err := p.runBridge(checkCtx, "-Check")
	if err != nil {
		return Availability{State: AvailabilityUnavailable, Message: "Windows OCR is not available: " + err.Error()}
	}
	var res ocrBridgeResponse
	if err := json.Unmarshal(out, &res); err != nil {
		return Availability{State: AvailabilityUnavailable, Message: "Windows OCR bridge returned an unexpected response."}
	}
	if !res.Available {
		return Availability{State: AvailabilityUnavailable, Message: "Windows OCR reported no available recognition engine."}
	}
	return Availability{State: AvailabilityReady, Message: "Ready offline (" + res.Language + ")."}
}

// ProcessPage mirrors the Apple Vision flow: prefer embedded text when it
// passes the quality gate, otherwise OCR the rendered page image.
func (p *WindowsOCRProvider) ProcessPage(ctx context.Context, req PageRequest) (Page, error) {
	if VisibleCharCount(req.NativeLines) >= NativeTextMinVisibleChars {
		return NativePage(req.PageNumber, req.NativeLines), nil
	}
	if req.ImagePath == "" {
		return Page{}, fmt.Errorf("page %d has no usable embedded text and no rendered image was provided for OCR", req.PageNumber)
	}
	if err := p.ensureBridge(); err != nil {
		return Page{}, err
	}
	ocrCtx, cancel := context.WithTimeout(ctx, 3*time.Minute)
	defer cancel()
	out, err := p.runBridge(ocrCtx, "-Path", req.ImagePath)
	if err != nil {
		return Page{}, err
	}
	var res ocrBridgeResponse
	if err := json.Unmarshal(out, &res); err != nil {
		snippet := string(out)
		if len(snippet) > 200 {
			snippet = snippet[:200]
		}
		return Page{}, fmt.Errorf("Windows OCR bridge returned invalid output: %w (%q)", err, snippet)
	}
	return ocrPage(req.PageNumber, req.ImageFile, res), nil
}

// ocrPage converts WinRT OCR lines (pixel coordinates) into normalized blocks,
// mirroring AppleVisionStructuredExtractor.scannedPage on macOS.
func ocrPage(pageNumber int, imageFile string, res ocrBridgeResponse) Page {
	blocks := make([]Block, 0, len(res.Lines))
	textParts := make([]string, 0, len(res.Lines))
	blockNumber := 0
	for _, line := range res.Lines {
		text := trimSpace(line.Text)
		if text == "" || res.ImageWidth <= 0 || res.ImageHeight <= 0 {
			continue
		}
		box, ok := normalizedBox(
			line.X/float64(res.ImageWidth),
			line.Y/float64(res.ImageHeight),
			line.Width/float64(res.ImageWidth),
			line.Height/float64(res.ImageHeight),
		)
		if !ok {
			continue
		}
		blockNumber++
		scale := 1
		blocks = append(blocks, Block{
			ID:              blockID(pageNumber, blockNumber),
			Type:            "text",
			SourceType:      "windows-ocr-line",
			Text:            text,
			BBox:            box,
			SourceBBox:      []float64{box.X, box.Y, box.X + box.Width, box.Y + box.Height},
			SourceBBoxScale: &scale,
		})
		textParts = append(textParts, text)
	}
	text := joinLines(textParts)
	return Page{
		PageNumber: pageNumber,
		ImageFile:  imageFile,
		Markdown:   text,
		PlainText:  text,
		Blocks:     blocks,
		Diagnostics: Diagnostics{
			RawCharacterCount:     len(text),
			DecodedCharacterCount: len(text),
			DetectionCount:        len(blocks),
			Warnings:              []string{},
		},
	}
}

func (p *WindowsOCRProvider) ensureBridge() error {
	if p.bridgePath != "" {
		return nil
	}
	dir := filepath.Join(ProvidersRoot(), "windows-ocr")
	if err := os.MkdirAll(dir, 0o755); err != nil {
		return err
	}
	path := filepath.Join(dir, "ocrbridge.ps1")
	// Always refresh the script so app updates propagate.
	if err := os.WriteFile(path, ocrBridgeScript, 0o644); err != nil {
		return err
	}
	p.bridgePath = path
	p.powershellBin = "powershell.exe"
	return nil
}

func (p *WindowsOCRProvider) runBridge(ctx context.Context, args ...string) ([]byte, error) {
	fullArgs := append([]string{
		"-NoProfile", "-NonInteractive", "-ExecutionPolicy", "Bypass",
		"-File", p.bridgePath,
	}, args...)
	cmd := exec.CommandContext(ctx, p.powershellBin, fullArgs...)
	hideConsoleWindow(cmd)
	out, err := cmd.Output()
	if err != nil {
		if exitErr, ok := err.(*exec.ExitError); ok && len(exitErr.Stderr) > 0 {
			return nil, fmt.Errorf("%s", trimSpace(string(exitErr.Stderr)))
		}
		return nil, err
	}
	return out, nil
}

type ocrBridgeResponse struct {
	Available         bool            `json:"available"`
	Language          string          `json:"language"`
	MaxImageDimension int             `json:"maxImageDimension"`
	ImageWidth        int             `json:"imageWidth"`
	ImageHeight       int             `json:"imageHeight"`
	Lines             []ocrBridgeLine `json:"lines"`
}

type ocrBridgeLine struct {
	Text   string  `json:"text"`
	X      float64 `json:"x"`
	Y      float64 `json:"y"`
	Width  float64 `json:"width"`
	Height float64 `json:"height"`
}
