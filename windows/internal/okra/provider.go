package okra

import (
	"context"
	"unicode"
)

// Provider contract mirroring LocalProcessingProvider on macOS.

// ProviderDescriptor describes a selectable local parser.
type ProviderDescriptor struct {
	ID        string  `json:"id"`
	Name      string  `json:"name"`
	Summary   string  `json:"summary"`
	SetupNote *string `json:"setupNote,omitempty"`
}

// Availability states, mirroring LocalProviderAvailability.
const (
	AvailabilityReady         = "ready"
	AvailabilitySetupRequired = "setupRequired"
	AvailabilityUnavailable   = "unavailable"
)

// Availability reports whether a provider can parse right now.
type Availability struct {
	State   string `json:"state"`
	Message string `json:"message"`
}

func (a Availability) IsReady() bool { return a.State == AvailabilityReady }

// NativeLine is one embedded-text line extracted by the UI's PDF.js text
// layer, with a normalized top-left-origin bounding box (0..1 of page size).
type NativeLine struct {
	Text   string  `json:"text"`
	X      float64 `json:"x"`
	Y      float64 `json:"y"`
	Width  float64 `json:"width"`
	Height float64 `json:"height"`
}

// PageRequest carries everything a provider needs to process one page.
type PageRequest struct {
	RunID       string
	PageNumber  int
	ImagePath   string // rendered PNG path; empty when native text suffices
	ImageFile   string // image file name relative to the run directory
	NativeLines []NativeLine
	OllamaModel string
}

// Provider is a local parser: explicit action in, structured page out.
type Provider interface {
	Descriptor() ProviderDescriptor
	Availability(ctx context.Context) Availability
	ProcessPage(ctx context.Context, req PageRequest) (Page, error)
}

// NativeTextMinVisibleChars mirrors NativePDFTextQualityGate on macOS
// (minimumCharacterCount = 24): below this, a page is treated as scanned.
const NativeTextMinVisibleChars = 24

// NativePage builds a StructuredExtractionPage from embedded PDF text lines,
// mirroring AppleVisionStructuredExtractor.nativePage on macOS.
func NativePage(pageNumber int, lines []NativeLine) Page {
	blocks := make([]Block, 0, len(lines))
	textParts := make([]string, 0, len(lines))
	blockNumber := 0
	for _, line := range lines {
		text := trimSpace(line.Text)
		if text == "" {
			continue
		}
		box, ok := normalizedBox(line.X, line.Y, line.Width, line.Height)
		if !ok {
			continue
		}
		blockNumber++
		scale := 1
		blocks = append(blocks, Block{
			ID:              blockID(pageNumber, blockNumber),
			Type:            "text",
			SourceType:      "pdf-text-line",
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
		ImageFile:  "",
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

// VisibleCharCount counts non-whitespace characters across native lines.
func VisibleCharCount(lines []NativeLine) int {
	count := 0
	for _, line := range lines {
		for _, r := range line.Text {
			if isVisibleTextRune(r) {
				count++
			}
		}
	}
	return count
}

// isVisibleTextRune excludes Unicode whitespace, controls, and characters
// whose default rendering is intentionally invisible. This keeps junk text
// layers from suppressing the Windows OCR fallback.
func isVisibleTextRune(r rune) bool {
	return !unicode.IsSpace(r) &&
		!unicode.IsControl(r) &&
		!unicode.Is(unicode.Cf, r) &&
		!unicode.Is(unicode.Other_Default_Ignorable_Code_Point, r) &&
		!unicode.Is(unicode.Variation_Selector, r)
}

func blockID(pageNumber, blockNumber int) string {
	return "page-" + itoa(pageNumber) + "-block-" + itoa(blockNumber)
}

func normalizedBox(x, y, width, height float64) (*BoundingBox, bool) {
	if width <= 0 || height <= 0 {
		return nil, false
	}
	// Clip to the normalized page extents.
	if x < 0 {
		width += x
		x = 0
	}
	if y < 0 {
		height += y
		y = 0
	}
	if x+width > 1 {
		width = 1 - x
	}
	if y+height > 1 {
		height = 1 - y
	}
	if width <= 0 || height <= 0 {
		return nil, false
	}
	return &BoundingBox{
		X:      x,
		Y:      y,
		Width:  width,
		Height: height,
		Unit:   "normalized",
		Origin: "top-left",
	}, true
}

func itoa(v int) string {
	if v == 0 {
		return "0"
	}
	neg := v < 0
	if neg {
		v = -v
	}
	var buf [20]byte
	i := len(buf)
	for v > 0 {
		i--
		buf[i] = byte('0' + v%10)
		v /= 10
	}
	if neg {
		i--
		buf[i] = '-'
	}
	return string(buf[i:])
}

func trimSpace(s string) string {
	start := 0
	end := len(s)
	for start < end && (s[start] == ' ' || s[start] == '\t' || s[start] == '\n' || s[start] == '\r') {
		start++
	}
	for end > start && (s[end-1] == ' ' || s[end-1] == '\t' || s[end-1] == '\n' || s[end-1] == '\r') {
		end--
	}
	return s[start:end]
}

func joinLines(parts []string) string {
	total := 0
	for _, p := range parts {
		total += len(p) + 1
	}
	out := make([]byte, 0, total)
	for i, p := range parts {
		if i > 0 {
			out = append(out, '\n')
		}
		out = append(out, p...)
	}
	return string(out)
}
