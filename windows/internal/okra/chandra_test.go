package okra

import (
	"context"
	"image"
	"image/color"
	"image/png"
	"os"
	"path/filepath"
	"strings"
	"testing"
	"time"
)

func TestChandraManifestIsComplete(t *testing.T) {
	if len(ChandraModelArtifacts) != 10 {
		t.Fatalf("expected 10 artifacts, got %d", len(ChandraModelArtifacts))
	}
	total := ChandraTotalBytes()
	if total < 10_000_000_000 || total > 11_000_000_000 {
		t.Fatalf("unexpected total size: %d", total)
	}
	for _, artifact := range ChandraModelArtifacts {
		if len(artifact.SHA256) != 64 {
			t.Fatalf("artifact %s has malformed sha256", artifact.Path)
		}
		if !strings.Contains(ArtifactDownloadURL(artifact), ChandraModelRevision) {
			t.Fatalf("download URL not pinned: %s", ArtifactDownloadURL(artifact))
		}
	}
}

func TestChandraReadyMarkerRoundTrip(t *testing.T) {
	path := filepath.Join(t.TempDir(), ".ready")
	for _, lock := range []string{ChandraRuntimeLockCUDA, ChandraRuntimeLockCPU} {
		marker := NewChandraReadyMarker(lock)
		if !marker.MatchesCurrentRuntime() {
			t.Fatalf("fresh marker with %s should match the current runtime lock", lock)
		}
		if err := marker.Write(path); err != nil {
			t.Fatalf("Write: %v", err)
		}
		loaded, err := ReadChandraReadyMarker(path)
		if err != nil {
			t.Fatalf("Read: %v", err)
		}
		if !loaded.MatchesCurrentRuntime() {
			t.Fatal("loaded marker should match the current runtime lock")
		}
	}
	loaded, err := ReadChandraReadyMarker(path)
	if err != nil {
		t.Fatalf("Read: %v", err)
	}
	loaded.RuntimeLockVersion = "python>=3.10|torch==0|v0"
	if loaded.MatchesCurrentRuntime() {
		t.Fatal("tampered marker must not match the current runtime lock")
	}
}

// TestChandraSimulationEndToEnd drives the real client-server contract: Go
// spawns the Python worker (simulation mode), waits for readiness, and
// processes a page through loopback HTTP. Skipped when Python is absent.
func TestChandraSimulationEndToEnd(t *testing.T) {
	if _, _, err := findSystemPython(); err != nil {
		t.Skipf("python not available: %v", err)
	}
	root := t.TempDir()
	provider := &ChandraOCRProvider{root: root, simulation: true}
	defer provider.Shutdown()

	if availability := provider.Availability(context.Background()); !availability.IsReady() {
		t.Fatalf("simulation availability = %+v", availability)
	}

	imagePath := filepath.Join(root, "page.png")
	writeTestPNG(t, imagePath)

	ctx, cancel := context.WithTimeout(context.Background(), 3*time.Minute)
	defer cancel()
	page, err := provider.ProcessPage(ctx, PageRequest{
		RunID:      "test-run",
		PageNumber: 1,
		ImagePath:  imagePath,
		ImageFile:  "pages/page-0001.png",
	})
	if err != nil {
		t.Fatalf("ProcessPage: %v", err)
	}
	if page.PageNumber != 1 {
		t.Fatalf("pageNumber = %d", page.PageNumber)
	}
	if page.Provenance == nil || !strings.Contains(*page.Provenance, "chandra-ocr-2:simulation") {
		t.Fatalf("unexpected provenance: %v", page.Provenance)
	}
	if len(page.Blocks) != 2 {
		t.Fatalf("expected 2 simulated blocks, got %d", len(page.Blocks))
	}
	heading := page.Blocks[0]
	if heading.Type != "heading" || heading.SourceType != "Section-Header" {
		t.Fatalf("unexpected first block: %+v", heading)
	}
	if heading.BBox == nil || heading.BBox.Unit != "normalized" || heading.BBox.Origin != "top-left" {
		t.Fatalf("bad bbox: %+v", heading.BBox)
	}
	if heading.SourceBBoxScale == nil || *heading.SourceBBoxScale != 1000 {
		t.Fatalf("expected sourceBboxScale 1000, got %+v", heading.SourceBBoxScale)
	}
	if page.Diagnostics.BlockCount == nil || *page.Diagnostics.BlockCount != 2 {
		t.Fatalf("bad diagnostics: %+v", page.Diagnostics)
	}

	// A second page reuses the same persistent worker (no respawn).
	if _, err := provider.ProcessPage(ctx, PageRequest{
		RunID: "test-run", PageNumber: 2, ImagePath: imagePath, ImageFile: "pages/page-0002.png",
	}); err != nil {
		t.Fatalf("ProcessPage 2: %v", err)
	}
	provider.workerMu.Lock()
	worker := provider.worker
	provider.workerMu.Unlock()
	if worker == nil || !worker.alive() {
		t.Fatal("worker should still be alive after two pages")
	}
}

// TestChandraWorkerSurvivesRequestCancellation is the regression test for the
// page-2 hang: the worker must not be tied to a page request's context, so
// canceling request 1 must not kill the worker used by request 2.
func TestChandraWorkerSurvivesRequestCancellation(t *testing.T) {
	if _, _, err := findSystemPython(); err != nil {
		t.Skipf("python not available: %v", err)
	}
	root := t.TempDir()
	provider := &ChandraOCRProvider{root: root, simulation: true}
	defer provider.Shutdown()

	imagePath := filepath.Join(root, "page.png")
	writeTestPNG(t, imagePath)

	ctx1, cancel1 := context.WithTimeout(context.Background(), 2*time.Minute)
	if _, err := provider.ProcessPage(ctx1, PageRequest{
		RunID: "run", PageNumber: 1, ImagePath: imagePath, ImageFile: "pages/page-0001.png",
	}); err != nil {
		cancel1()
		t.Fatalf("ProcessPage 1: %v", err)
	}
	cancel1() // the page-1 HTTP request finished; its context is canceled
	time.Sleep(500 * time.Millisecond)

	ctx2, cancel2 := context.WithTimeout(context.Background(), 2*time.Minute)
	defer cancel2()
	if _, err := provider.ProcessPage(ctx2, PageRequest{
		RunID: "run", PageNumber: 2, ImagePath: imagePath, ImageFile: "pages/page-0002.png",
	}); err != nil {
		t.Fatalf("ProcessPage 2 after request-1 cancellation: %v", err)
	}
}

func writeTestPNG(t *testing.T, path string) {
	t.Helper()
	img := image.NewRGBA(image.Rect(0, 0, 64, 64))
	for y := 0; y < 64; y++ {
		for x := 0; x < 64; x++ {
			img.Set(x, y, color.White)
		}
	}
	f, err := os.Create(path)
	if err != nil {
		t.Fatalf("create png: %v", err)
	}
	defer f.Close()
	if err := png.Encode(f, img); err != nil {
		t.Fatalf("encode png: %v", err)
	}
}
