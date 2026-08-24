package okra

import (
	"bytes"
	"context"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"strings"
	"testing"
	"testing/fstest"
)

type fakeProvider struct {
	id string
}

func (f *fakeProvider) Descriptor() ProviderDescriptor {
	return ProviderDescriptor{ID: f.id, Name: "Fake " + f.id, Summary: "test"}
}

func (f *fakeProvider) Availability(ctx context.Context) Availability {
	return Availability{State: AvailabilityReady, Message: "Ready offline."}
}

func (f *fakeProvider) ProcessPage(ctx context.Context, req PageRequest) (Page, error) {
	if len(req.NativeLines) == 0 {
		return Page{}, &fakeError{"no lines"}
	}
	return NativePage(req.PageNumber, req.NativeLines), nil
}

type fakeError struct{ msg string }

func (e *fakeError) Error() string { return e.msg }

func newTestServer(t *testing.T) (*httptest.Server, *Store) {
	t.Helper()
	store, err := NewStore(filepath.Join(t.TempDir(), "Runs"))
	if err != nil {
		t.Fatalf("NewStore: %v", err)
	}
	static := fstest.MapFS{"index.html": &fstest.MapFile{Data: []byte("ok"), Mode: 0o444}}
	server := NewServer(store, []Provider{&fakeProvider{id: "windows-ocr"}}, NewOllamaClient(), "test-token", static)
	return httptest.NewServer(server.Handler()), store
}

func apiRequest(t *testing.T, method, url string, body any, withToken bool) (*http.Response, map[string]any) {
	t.Helper()
	var reader *bytes.Reader
	if body != nil {
		data, _ := json.Marshal(body)
		reader = bytes.NewReader(data)
	} else {
		reader = bytes.NewReader(nil)
	}
	req, err := http.NewRequest(method, url, reader)
	if err != nil {
		t.Fatalf("NewRequest: %v", err)
	}
	if withToken {
		req.Header.Set("X-Okra-Token", "test-token")
	}
	res, err := http.DefaultClient.Do(req)
	if err != nil {
		t.Fatalf("%s %s: %v", method, url, err)
	}
	defer res.Body.Close()
	var decoded map[string]any
	_ = json.NewDecoder(res.Body).Decode(&decoded)
	return res, decoded
}

func TestServerRequiresToken(t *testing.T) {
	ts, _ := newTestServer(t)
	defer ts.Close()
	res, _ := apiRequest(t, http.MethodGet, ts.URL+"/api/runs", nil, false)
	if res.StatusCode != http.StatusForbidden {
		t.Fatalf("expected 403 without token, got %d", res.StatusCode)
	}
	res, _ = apiRequest(t, http.MethodGet, ts.URL+"/api/runs", nil, true)
	if res.StatusCode != http.StatusOK {
		t.Fatalf("expected 200 with token, got %d", res.StatusCode)
	}
}

func TestSaveDocumentCopyRejectsInvalidPDF(t *testing.T) {
	ts, _ := newTestServer(t)
	defer ts.Close()
	req, err := http.NewRequest(http.MethodPost, ts.URL+"/api/document/save-copy?fileName=unsafe.txt", strings.NewReader("not a PDF"))
	if err != nil {
		t.Fatalf("NewRequest: %v", err)
	}
	req.Header.Set("X-Okra-Token", "test-token")
	req.Header.Set("Content-Type", "application/pdf")
	res, err := http.DefaultClient.Do(req)
	if err != nil {
		t.Fatalf("save document copy: %v", err)
	}
	defer res.Body.Close()
	if res.StatusCode != http.StatusBadRequest {
		t.Fatalf("expected 400 for invalid PDF, got %d", res.StatusCode)
	}
}

func TestServerRunFlowOverHTTP(t *testing.T) {
	ts, store := newTestServer(t)
	defer ts.Close()

	pdfPath := filepath.Join(t.TempDir(), "doc.pdf")
	writeFile(t, pdfPath, "%PDF-1.4 fake")

	res, body := apiRequest(t, http.MethodPost, ts.URL+"/api/runs", map[string]any{
		"providerId": "windows-ocr",
		"sourcePath": pdfPath,
		"fileName":   "doc.pdf",
		"pageCount":  1,
	}, true)
	if res.StatusCode != http.StatusOK {
		t.Fatalf("create run status %d: %v", res.StatusCode, body)
	}
	runID := body["run"].(map[string]any)["id"].(string)

	res, body = apiRequest(t, http.MethodPost, ts.URL+"/api/runs/"+runID+"/pages", map[string]any{
		"pageNumber": 1,
		"nativeLines": []map[string]any{
			{"text": "Hello from the test", "x": 0.1, "y": 0.1, "width": 0.6, "height": 0.05},
		},
	}, true)
	if res.StatusCode != http.StatusOK {
		t.Fatalf("post page status %d: %v", res.StatusCode, body)
	}
	page := body["page"].(map[string]any)
	if page["markdown"] != "Hello from the test" {
		t.Fatalf("unexpected page markdown: %v", page["markdown"])
	}

	res, body = apiRequest(t, http.MethodPost, ts.URL+"/api/runs/"+runID+"/complete", nil, true)
	if res.StatusCode != http.StatusOK {
		t.Fatalf("complete status %d: %v", res.StatusCode, body)
	}

	res, body = apiRequest(t, http.MethodGet, ts.URL+"/api/runs/"+runID+"/output", nil, true)
	if res.StatusCode != http.StatusOK {
		t.Fatalf("output status %d: %v", res.StatusCode, body)
	}
	if body["markdown"] != "Hello from the test\n" {
		t.Fatalf("unexpected markdown: %v", body["markdown"])
	}
	structured := body["structured"].(map[string]any)
	if structured["object"] != "local_extraction" || structured["complete"] != true {
		t.Fatalf("unexpected structured doc: %v", structured)
	}

	runs, err := store.ListRuns(pdfPath, 10)
	if err != nil || len(runs) != 1 {
		t.Fatalf("ListRuns: %v %d", err, len(runs))
	}
	if runs[0].Status != RunStatusSucceeded {
		t.Fatalf("run status = %s", runs[0].Status)
	}
}

func TestServerRejectsUnknownProvider(t *testing.T) {
	ts, _ := newTestServer(t)
	defer ts.Close()
	res, body := apiRequest(t, http.MethodPost, ts.URL+"/api/runs", map[string]any{
		"providerId": "nope", "sourcePath": "x.pdf", "fileName": "x.pdf", "pageCount": 1,
	}, true)
	if res.StatusCode != http.StatusBadRequest {
		t.Fatalf("expected 400, got %d", res.StatusCode)
	}
	if !strings.Contains(body["error"].(string), "unknown provider") {
		t.Fatalf("unexpected error: %v", body)
	}
}

func TestServerPresidioDetectionFlow(t *testing.T) {
	analyzer := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.URL.Path == "/health" {
			_ = json.NewEncoder(w).Encode(map[string]any{"status": "ok"})
			return
		}
		if r.URL.Path != "/analyze" {
			http.NotFound(w, r)
			return
		}
		_ = json.NewEncoder(w).Encode([]map[string]any{{
			"entity_type": "EMAIL_ADDRESS", "start": 6, "end": 21, "score": 0.99, "text": "ada@example.com",
		}})
	}))
	defer analyzer.Close()

	store, err := NewStore(filepath.Join(t.TempDir(), "Runs"))
	if err != nil {
		t.Fatal(err)
	}
	run, err := store.CreateRun(Run{
		SourcePath: "synthetic.pdf", FileName: "synthetic.pdf", ProviderID: "windows-ocr", ProviderName: "Windows OCR", PageCount: 1,
	})
	if err != nil {
		t.Fatal(err)
	}
	if err := store.SavePageResult(run.ID, Page{
		PageNumber: 1,
		Markdown:   "Email ada@example.com",
		PlainText:  "Email ada@example.com",
		Blocks: []Block{{
			ID: "p1-b0", Text: "Email ada@example.com", BBox: &BoundingBox{X: 0.1, Y: 0.2, Width: 0.5, Height: 0.04},
		}},
		Diagnostics: Diagnostics{Warnings: []string{}},
	}); err != nil {
		t.Fatal(err)
	}
	if _, err := store.CompleteRun(run.ID); err != nil {
		t.Fatal(err)
	}

	static := fstest.MapFS{"index.html": &fstest.MapFile{Data: []byte("ok"), Mode: 0o444}}
	server := NewServer(store, []Provider{&fakeProvider{id: "windows-ocr"}}, NewOllamaClient(), "test-token", static)
	server.presidio = &PresidioService{externalURL: analyzer.URL}
	defer server.Shutdown()
	ts := httptest.NewServer(server.Handler())
	defer ts.Close()

	res, body := apiRequest(t, http.MethodPost, ts.URL+"/api/runs/"+run.ID+"/redactions/detect", map[string]any{"minScore": 0.5}, true)
	if res.StatusCode != http.StatusOK {
		t.Fatalf("detect status %d: %v", res.StatusCode, body)
	}
	detection := body["detection"].(map[string]any)
	if detection["object"] != "pii_redaction_candidates" || detection["stats"].(map[string]any)["total"] != float64(1) {
		t.Fatalf("unexpected detection: %v", detection)
	}

	res, body = apiRequest(t, http.MethodGet, ts.URL+"/api/runs/"+run.ID+"/redactions", nil, true)
	if res.StatusCode != http.StatusOK || body["detection"] == nil {
		t.Fatalf("stored redactions status %d: %v", res.StatusCode, body)
	}
}

func writeFile(t *testing.T, path, content string) {
	t.Helper()
	if err := os.WriteFile(path, []byte(content), 0o644); err != nil {
		t.Fatalf("writeFile: %v", err)
	}
}
