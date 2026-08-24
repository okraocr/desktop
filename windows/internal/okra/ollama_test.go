package okra

import (
	"context"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
)

func TestStripOuterMarkdownFence(t *testing.T) {
	cases := []struct{ in, want string }{
		{"```\nhello\n```", "hello"},
		{"```markdown\n# Title\n```", "# Title"},
		{"no fence", "no fence"},
		{"```\nonly-open", "```\nonly-open"},
		{"`not a fence`", "`not a fence`"},
	}
	for _, c := range cases {
		if got := StripOuterMarkdownFence(c.in); got != c.want {
			t.Fatalf("StripOuterMarkdownFence(%q) = %q, want %q", c.in, got, c.want)
		}
	}
}

func TestLooksLikeVisionModel(t *testing.T) {
	for name, want := range map[string]bool{
		"llava:13b":              true,
		"llama3.2-vision:latest": true,
		"qwen2.5-vl:7b":          true,
		"gemma3:12b":             true,
		"minicpm-v:latest":       true,
		"llama3.1:8b":            false,
		"mistral:latest":         false,
	} {
		if got := looksLikeVisionModel(name); got != want {
			t.Fatalf("looksLikeVisionModel(%q) = %v, want %v", name, got, want)
		}
	}
}

func TestOllamaModelsAndExtract(t *testing.T) {
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		switch r.URL.Path {
		case "/api/tags":
			_ = json.NewEncoder(w).Encode(map[string]any{
				"models": []map[string]string{{"name": "llava:13b"}, {"name": "llama3.1:8b"}},
			})
		case "/api/chat":
			var req map[string]any
			_ = json.NewDecoder(r.Body).Decode(&req)
			if req["model"] != "llava:13b" {
				t.Errorf("unexpected model: %v", req["model"])
			}
			messages := req["messages"].([]any)
			first := messages[0].(map[string]any)
			if first["content"] != ollamaDocumentPrompt {
				t.Errorf("prompt mismatch: %v", first["content"])
			}
			if images, ok := first["images"].([]any); !ok || len(images) != 1 {
				t.Errorf("expected one image, got %v", first["images"])
			}
			_ = json.NewEncoder(w).Encode(map[string]any{
				"message": map[string]string{"role": "assistant", "content": "```\n# Page\n```"},
			})
		default:
			http.NotFound(w, r)
		}
	}))
	defer server.Close()

	client := &OllamaClient{baseURL: server.URL, httpClient: server.Client()}
	models, err := client.Models(context.Background())
	if err != nil {
		t.Fatalf("Models: %v", err)
	}
	if len(models) != 2 || !models[0].SupportsVision || models[0].Name != "llava:13b" {
		t.Fatalf("unexpected models: %+v", models)
	}

	markdown, err := client.ExtractMarkdown(context.Background(), "llava:13b", []byte("fakepng"))
	if err != nil {
		t.Fatalf("ExtractMarkdown: %v", err)
	}
	if markdown != "# Page" {
		t.Fatalf("unexpected markdown: %q", markdown)
	}
}

func TestOllamaUnreachable(t *testing.T) {
	client := &OllamaClient{baseURL: "http://127.0.0.1:1", httpClient: http.DefaultClient}
	_, err := client.Models(context.Background())
	if err == nil || !strings.Contains(err.Error(), "not reachable") {
		t.Fatalf("expected unreachable error, got %v", err)
	}
}
