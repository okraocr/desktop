package okra

import (
	"context"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"os"
	"testing"
)

func TestLoopbackBaseURL(t *testing.T) {
	for _, value := range []string{"http://127.0.0.1:3000", "http://localhost:5002/", "http://[::1]:3000"} {
		if _, err := loopbackBaseURL(value); err != nil {
			t.Fatalf("expected %s to be accepted: %v", value, err)
		}
	}
	for _, value := range []string{"https://presidio.example.com", "file:///tmp/presidio", "not-a-url"} {
		if _, err := loopbackBaseURL(value); err == nil {
			t.Fatalf("expected %s to be rejected", value)
		}
	}
}

func TestPresidioDetectMapsSpansToSourceBoxes(t *testing.T) {
	service := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		switch r.URL.Path {
		case "/health":
			_ = json.NewEncoder(w).Encode(map[string]any{"status": "ok"})
		case "/analyze":
			var body map[string]any
			_ = json.NewDecoder(r.Body).Decode(&body)
			if body["text"] != "Contact Ada Lovelace\nEmail ada@example.com" {
				t.Fatalf("unexpected text sent to Presidio: %q", body["text"])
			}
			_ = json.NewEncoder(w).Encode([]map[string]any{
				{"entity_type": "PERSON", "start": 8, "end": 20, "score": 0.91, "text": "Ada Lovelace"},
				{"entity_type": "EMAIL_ADDRESS", "start": 27, "end": 42, "score": 0.99, "text": "ada@example.com"},
			})
		default:
			http.NotFound(w, r)
		}
	}))
	defer service.Close()

	p := &PresidioService{externalURL: service.URL}
	doc := &StructuredDocument{Pages: []Page{{
		PageNumber: 1,
		Blocks: []Block{
			{ID: "p1-b0", Text: "Contact Ada Lovelace", BBox: &BoundingBox{X: 0.1, Y: 0.2, Width: 0.4, Height: 0.04}},
			{ID: "p1-b1", Text: "Email ada@example.com", BBox: &BoundingBox{X: 0.1, Y: 0.3, Width: 0.5, Height: 0.04}},
		},
	}}}
	detection, err := p.Detect(context.Background(), "run-1", doc, PresidioAnalyzeRequest{MinScore: 0.5})
	if err != nil {
		t.Fatal(err)
	}
	if len(detection.Boxes) != 2 {
		t.Fatalf("got %d boxes, want 2", len(detection.Boxes))
	}
	if detection.Boxes[0].Type != "PERSON" || detection.Boxes[0].BlockID != "p1-b0" {
		t.Fatalf("unexpected first box: %+v", detection.Boxes[0])
	}
	if detection.Boxes[1].Type != "EMAIL_ADDRESS" || detection.Boxes[1].BlockID != "p1-b1" {
		t.Fatalf("unexpected second box: %+v", detection.Boxes[1])
	}
	if detection.Stats.Total != 2 || detection.Stats.ByType["PERSON"] != 1 || detection.Stats.BySource["presidio"] != 2 {
		t.Fatalf("unexpected stats: %+v", detection.Stats)
	}
}

func TestPresidioSimulationWorker(t *testing.T) {
	if _, _, err := findSystemPython(); err != nil {
		t.Skip("Python 3.10+ is not installed")
	}
	p := &PresidioService{root: t.TempDir(), simulation: true}
	defer p.Shutdown()
	doc := &StructuredDocument{Pages: []Page{{
		PageNumber: 1,
		Blocks: []Block{{
			ID: "p1-b0", Text: "Email ada@example.com", BBox: &BoundingBox{X: 0.1, Y: 0.2, Width: 0.5, Height: 0.04},
		}},
	}}}
	detection, err := p.Detect(context.Background(), "run-sim", doc, PresidioAnalyzeRequest{MinScore: 0.5})
	if err != nil {
		t.Fatal(err)
	}
	if len(detection.Boxes) != 1 || detection.Boxes[0].Text != "ada@example.com" {
		t.Fatalf("unexpected simulation result: %+v", detection.Boxes)
	}
}

func TestPresidioManagedRuntimeOptIn(t *testing.T) {
	if os.Getenv("OKRA_TEST_REAL_PRESIDIO") != "1" {
		t.Skip("set OKRA_TEST_REAL_PRESIDIO=1 after managed setup")
	}
	p := NewPresidioService()
	defer p.Shutdown()
	if availability := p.Availability(context.Background()); availability.State != AvailabilityReady {
		t.Fatalf("managed Presidio is not ready: %s", availability.Message)
	}
	doc := &StructuredDocument{Pages: []Page{{
		PageNumber: 1,
		Blocks: []Block{{
			ID: "p1-b0", Text: "Email ada@example.com", BBox: &BoundingBox{X: 0.1, Y: 0.2, Width: 0.5, Height: 0.04},
		}},
	}}}
	detection, err := p.Detect(context.Background(), "run-real", doc, PresidioAnalyzeRequest{MinScore: 0.5})
	if err != nil {
		t.Fatal(err)
	}
	for _, box := range detection.Boxes {
		if box.Type == "EMAIL_ADDRESS" && box.Text == "ada@example.com" {
			return
		}
	}
	t.Fatalf("managed Presidio missed the synthetic email: %+v", detection.Boxes)
}
