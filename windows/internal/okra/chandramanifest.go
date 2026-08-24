package okra

import (
	"bytes"
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"fmt"
	"io"
	"os"
	"path/filepath"
	"time"
)

// Chandra OCR 2 pinned model manifest — the Windows counterpart of
// ChandraOCRModelManifest on macOS. macOS pins the Apple-silicon MLX 8-bit
// build (mlx-community/chandra-ocr-2-oQ8); Windows pins the upstream torch
// weights (datalab-to/chandra-ocr-2) at the same upstream revision.
const (
	ChandraModelRepository = "datalab-to/chandra-ocr-2"
	ChandraModelRevision   = "af93b47dba1b47b6640c86ccf487ed2260ab9a09"
	ChandraUpstreamURL     = "https://huggingface.co/datalab-to/chandra-ocr-2"
	ChandraLicenseURL      = "https://huggingface.co/datalab-to/chandra-ocr-2/blob/af93b47dba1b47b6640c86ccf487ed2260ab9a09/LICENSE"
	ChandraLicenseNotice   = "Use is subject to the upstream OpenRAIL license, including its use restrictions."
	// Runtime locks for the managed Windows venv (v3). The installer picks a
	// track by host: CUDA-capable NVIDIA GPU (fast, 8-bit quantized) or
	// CPU-only (slow, full bf16). Changing any pin invalidates existing
	// .ready markers, mirroring ChandraOCRReadyMarker.runtimeLockVersion.
	ChandraRuntimeLockCUDA = "python>=3.10|torch==2.13.0+cu126|torchvision==0.28.0+cu126|transformers==5.15.0|huggingface-hub==1.24.0|pillow>=11|bitsandbytes>=0.50|accelerate>=1.14|v4-cuda"
	ChandraRuntimeLockCPU  = "python>=3.10|torch==2.13.0+cpu|torchvision==0.28.0+cpu|transformers==5.15.0|huggingface-hub==1.24.0|pillow>=11|accelerate>=1.14|v4-cpu"
	ChandraProviderID      = "chandra-ocr-2"
	ChandraProviderName    = "Chandra OCR 2"
)

// ModelArtifact is one pinned, SHA-256-verified model file.
type ModelArtifact struct {
	Path   string `json:"path"`
	Size   int64  `json:"size"`
	SHA256 string `json:"sha256"`
}

// ChandraModelArtifacts lists every pinned artifact (hashes computed at the
// pinned revision; LFS objects use their published SHA-256).
var ChandraModelArtifacts = []ModelArtifact{
	{Path: "chat_template.jinja", Size: 7622, SHA256: "0d158f349ca965f7eea9db0eb45cd177b85bb0e4ae05dcdd0f060da8f7d41812"},
	{Path: "config.json", Size: 2773, SHA256: "e26f17b70463de21fd68f1ef6d8f67f8e33e65d55a7a6895242130a18db60587"},
	{Path: "generation_config.json", Size: 115, SHA256: "0c35bb39fbaed1ac0656baabc4f4e9bda20214e12336d0e4e8755aac1f487c2e"},
	{Path: "LICENSE", Size: 14742, SHA256: "126948ded70d791f4223175a8867cb64bd09bf8aeb7084b812393c876fdc6e1c"},
	{Path: "model.safetensors", Size: 10591220088, SHA256: "0804568be9f099d6479fad9ed77a4da4611f3c1e7bc6e009af7dce45e8aa3847"},
	{Path: "preprocessor_config.json", Size: 482, SHA256: "957eb01d1ea45341a92d543daec95857a7cbeff5803834bc0603b27ba7b41b3f"},
	{Path: "processor_config.json", Size: 1300, SHA256: "14932921ca485d458a04dafd8069fbb0a4505622a48208d19ed247115801385b"},
	{Path: "tokenizer.json", Size: 19989343, SHA256: "87a7830d63fcf43bf241c3c5242e96e62dd3fdc29224ca26fed8ea333db72de4"},
	{Path: "tokenizer_config.json", Size: 16710, SHA256: "316230d6a809701f4db5ea8f8fc862bc3a6f3229c937c174e674ff3ca0a64ac8"},
	{Path: "video_preprocessor_config.json", Size: 614, SHA256: "de7ba2c4528aa3c92754dc61ae83f1871369cbf7ab4298dcaa99c2f5a7c80848"},
}

// ChandraTotalBytes is the full setup download size (~10.6 GB).
func ChandraTotalBytes() int64 {
	var total int64
	for _, artifact := range ChandraModelArtifacts {
		total += artifact.Size
	}
	return total
}

// ChandraManifestJSON returns the manifest the installer consumes.
func ChandraManifestJSON() ([]byte, error) {
	type manifest struct {
		Repository      string          `json:"repository"`
		Revision        string          `json:"revision"`
		RuntimeLockCUDA string          `json:"runtimeLockCuda"`
		RuntimeLockCPU  string          `json:"runtimeLockCpu"`
		Artifacts       []ModelArtifact `json:"artifacts"`
	}
	return json.MarshalIndent(manifest{
		Repository:      ChandraModelRepository,
		Revision:        ChandraModelRevision,
		RuntimeLockCUDA: ChandraRuntimeLockCUDA,
		RuntimeLockCPU:  ChandraRuntimeLockCPU,
		Artifacts:       ChandraModelArtifacts,
	}, "", "  ")
}

// ArtifactDownloadURL mirrors LocalModelPackageManifest.downloadURL.
func ArtifactDownloadURL(artifact ModelArtifact) string {
	return fmt.Sprintf("%s/resolve/%s/%s", ChandraUpstreamURL, ChandraModelRevision, artifact.Path)
}

// ChandraReadyMarker mirrors ChandraOCRReadyMarker on macOS.
type ChandraReadyMarker struct {
	SchemaVersion      int    `json:"schemaVersion"`
	ModelRevision      string `json:"modelRevision"`
	RuntimeLockVersion string `json:"runtimeLockVersion"`
	InstalledAt        string `json:"installedAt"`
}

func NewChandraReadyMarker(runtimeLockVersion string) ChandraReadyMarker {
	return ChandraReadyMarker{
		SchemaVersion:      1,
		ModelRevision:      ChandraModelRevision,
		RuntimeLockVersion: runtimeLockVersion,
		InstalledAt:        time.Now().UTC().Format(time.RFC3339),
	}
}

func (m ChandraReadyMarker) MatchesCurrentRuntime() bool {
	lockOK := m.RuntimeLockVersion == ChandraRuntimeLockCUDA ||
		m.RuntimeLockVersion == ChandraRuntimeLockCPU
	return m.SchemaVersion == 1 &&
		m.ModelRevision == ChandraModelRevision &&
		lockOK
}

func ReadChandraReadyMarker(path string) (*ChandraReadyMarker, error) {
	data, err := os.ReadFile(path)
	if err != nil {
		return nil, err
	}
	// PowerShell 5.1 writes UTF-8 with a BOM; tolerate it.
	data = bytes.TrimPrefix(data, []byte{0xEF, 0xBB, 0xBF})
	var marker ChandraReadyMarker
	if err := json.Unmarshal(data, &marker); err != nil {
		return nil, err
	}
	return &marker, nil
}

func (m ChandraReadyMarker) Write(path string) error {
	data, err := json.MarshalIndent(m, "", "  ")
	if err != nil {
		return err
	}
	return writeJSONAtomic(path, json.RawMessage(data))
}

// HasCurrentModelArtifacts mirrors ChandraOCRRuntime.hasCurrentModelArtifacts:
// every pinned artifact exists with its exact size (hashes are verified by
// the installer before the ready marker is written).
func HasCurrentModelArtifacts(modelDir string) bool {
	for _, artifact := range ChandraModelArtifacts {
		info, err := os.Stat(filepath.Join(modelDir, artifact.Path))
		if err != nil || info.Size() != artifact.Size {
			return false
		}
	}
	return true
}

// VerifyArtifact checks one artifact's pinned SHA-256 (streaming).
func VerifyArtifact(path string, artifact ModelArtifact) error {
	info, err := os.Stat(path)
	if err != nil {
		return err
	}
	if info.Size() != artifact.Size {
		return fmt.Errorf("%s has size %d, expected %d", artifact.Path, info.Size(), artifact.Size)
	}
	f, err := os.Open(path)
	if err != nil {
		return err
	}
	defer f.Close()
	h := sha256.New()
	if _, err := io.Copy(h, f); err != nil {
		return err
	}
	if got := hex.EncodeToString(h.Sum(nil)); got != artifact.SHA256 {
		return fmt.Errorf("%s did not match the pinned Chandra OCR 2 model (sha256 %s, expected %s)", artifact.Path, got, artifact.SHA256)
	}
	return nil
}
