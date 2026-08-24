package okra

import (
	"bytes"
	"context"
	"encoding/base64"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"os"
	"sort"
	"strings"
	"time"
)

// ollamaDocumentPrompt mirrors OllamaClient.documentPrompt on macOS.
const ollamaDocumentPrompt = "Transcribe this document page into accurate Markdown. Preserve reading order, headings, lists, tables, code, and formulas. Do not describe the page or add commentary. Return only the page content in Markdown."

// OllamaModel is one installed Ollama model.
type OllamaModel struct {
	Name           string `json:"name"`
	SupportsVision bool   `json:"supportsVision"`
}

// OllamaClient talks to the Ollama loopback service (identical to macOS).
type OllamaClient struct {
	baseURL    string
	httpClient *http.Client
}

func NewOllamaClient() *OllamaClient {
	base := os.Getenv("OLLAMA_HOST")
	if base == "" {
		base = "http://127.0.0.1:11434"
	}
	return &OllamaClient{
		baseURL:    strings.TrimRight(base, "/"),
		httpClient: &http.Client{Timeout: 10 * time.Second},
	}
}

func (c *OllamaClient) BaseURL() string { return c.baseURL }

// Models lists installed models via GET /api/tags, flagging likely vision models.
func (c *OllamaClient) Models(ctx context.Context) ([]OllamaModel, error) {
	ctx, cancel := context.WithTimeout(ctx, 4*time.Second)
	defer cancel()
	req, err := http.NewRequestWithContext(ctx, http.MethodGet, c.baseURL+"/api/tags", nil)
	if err != nil {
		return nil, err
	}
	res, err := c.httpClient.Do(req)
	if err != nil {
		return nil, fmt.Errorf("Ollama is not reachable at %s", c.baseURL)
	}
	defer res.Body.Close()
	if res.StatusCode < 200 || res.StatusCode >= 300 {
		return nil, fmt.Errorf("Ollama returned status %d", res.StatusCode)
	}
	var tags struct {
		Models []struct {
			Name string `json:"name"`
		} `json:"models"`
	}
	if err := json.NewDecoder(res.Body).Decode(&tags); err != nil {
		return nil, err
	}
	models := make([]OllamaModel, 0, len(tags.Models))
	for _, m := range tags.Models {
		models = append(models, OllamaModel{Name: m.Name, SupportsVision: looksLikeVisionModel(m.Name)})
	}
	sort.Slice(models, func(i, j int) bool {
		if models[i].SupportsVision != models[j].SupportsVision {
			return models[i].SupportsVision
		}
		return models[i].Name < models[j].Name
	})
	return models, nil
}

func looksLikeVisionModel(name string) bool {
	lower := strings.ToLower(name)
	for _, token := range []string{
		"llava", "bakllava", "vision", "moondream", "minicpm-v", "minicpmv",
		"qwen2-vl", "qwen2.5-vl", "qwen3-vl", "qwen-vl", "pixtral",
		"llama3.2-vision", "llama4", "gemma3", "gemma-3", "granite3.2-vision",
		"mistral-small3", "phi-4-multimodal", "phi4-multimodal",
	} {
		if strings.Contains(lower, token) {
			return true
		}
	}
	return false
}

// ExtractMarkdown sends one page image to a vision model via POST /api/chat,
// mirroring OllamaClient.extractMarkdown on macOS.
func (c *OllamaClient) ExtractMarkdown(ctx context.Context, model string, imagePNG []byte) (string, error) {
	body := map[string]any{
		"model": model,
		"messages": []map[string]any{
			{
				"role":    "user",
				"content": ollamaDocumentPrompt,
				"images":  []string{base64.StdEncoding.EncodeToString(imagePNG)},
			},
		},
		"stream":  false,
		"options": map[string]any{"temperature": 0},
	}
	payload, err := json.Marshal(body)
	if err != nil {
		return "", err
	}
	chatCtx, cancel := context.WithTimeout(ctx, 30*time.Minute)
	defer cancel()
	req, err := http.NewRequestWithContext(chatCtx, http.MethodPost, c.baseURL+"/api/chat", bytes.NewReader(payload))
	if err != nil {
		return "", err
	}
	req.Header.Set("Content-Type", "application/json")
	req.Header.Set("Accept", "application/json")

	client := &http.Client{}
	res, err := client.Do(req)
	if err != nil {
		return "", fmt.Errorf("Ollama is not reachable at %s", c.baseURL)
	}
	defer res.Body.Close()
	data, err := io.ReadAll(res.Body)
	if err != nil {
		return "", err
	}
	if res.StatusCode < 200 || res.StatusCode >= 300 {
		var serverErr struct {
			Error string `json:"error"`
		}
		if json.Unmarshal(data, &serverErr) == nil && serverErr.Error != "" {
			return "", fmt.Errorf("Ollama: %s", serverErr.Error)
		}
		return "", fmt.Errorf("Ollama returned status %d", res.StatusCode)
	}
	var chat struct {
		Message struct {
			Content string `json:"content"`
		} `json:"message"`
	}
	if err := json.Unmarshal(data, &chat); err != nil {
		return "", err
	}
	markdown := strings.TrimSpace(chat.Message.Content)
	if markdown == "" {
		return "", fmt.Errorf("Ollama model %s finished without producing Markdown", model)
	}
	return StripOuterMarkdownFence(markdown), nil
}

// StripOuterMarkdownFence mirrors OllamaClient.stripOuterMarkdownFence on macOS.
func StripOuterMarkdownFence(text string) string {
	lines := strings.Split(text, "\n")
	if len(lines) < 2 {
		return text
	}
	first := strings.TrimSpace(lines[0])
	last := strings.TrimSpace(lines[len(lines)-1])
	if !strings.HasPrefix(first, "```") || last != "```" {
		return text
	}
	return strings.TrimSpace(strings.Join(lines[1:len(lines)-1], "\n"))
}

// OllamaProvider mirrors OllamaProcessingProvider on macOS: bring your own
// local vision model over the Ollama loopback service.
type OllamaProvider struct {
	client *OllamaClient
}

func NewOllamaProvider(client *OllamaClient) *OllamaProvider {
	return &OllamaProvider{client: client}
}

func (p *OllamaProvider) Descriptor() ProviderDescriptor {
	note := "Start Ollama and choose an installed vision model."
	return ProviderDescriptor{
		ID:        "ollama",
		Name:      "Ollama",
		Summary:   "Bring your own local vision model through the Ollama app on this PC.",
		SetupNote: &note,
	}
}

func (p *OllamaProvider) Availability(ctx context.Context) Availability {
	models, err := p.client.Models(ctx)
	if err != nil {
		return Availability{
			State:   AvailabilitySetupRequired,
			Message: "Start Ollama on this PC to use vision models.",
		}
	}
	for _, model := range models {
		if model.SupportsVision {
			return Availability{State: AvailabilityReady, Message: "Ready with a local Ollama vision model."}
		}
	}
	if len(models) > 0 {
		return Availability{
			State:   AvailabilityReady,
			Message: "No vision-tagged models found; install a vision model such as llava for best results.",
		}
	}
	return Availability{
		State:   AvailabilitySetupRequired,
		Message: "Ollama is running but has no models. Pull a vision model such as llava.",
	}
}

func (p *OllamaProvider) ProcessPage(ctx context.Context, req PageRequest) (Page, error) {
	if req.OllamaModel == "" {
		return Page{}, fmt.Errorf("choose an Ollama model before parsing")
	}
	if req.ImagePath == "" {
		return Page{}, fmt.Errorf("page %d needs a rendered image for Ollama vision parsing", req.PageNumber)
	}
	image, err := os.ReadFile(req.ImagePath)
	if err != nil {
		return Page{}, err
	}
	markdown, err := p.client.ExtractMarkdown(ctx, req.OllamaModel, image)
	if err != nil {
		return Page{}, err
	}
	return Page{
		PageNumber: req.PageNumber,
		ImageFile:  req.ImageFile,
		Markdown:   markdown,
		PlainText:  markdown,
		Blocks:     []Block{},
		Diagnostics: Diagnostics{
			RawCharacterCount:     len(markdown),
			DecodedCharacterCount: len(markdown),
			DetectionCount:        0,
			Warnings:              []string{},
		},
	}, nil
}
