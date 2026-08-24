package okra

import (
	"context"
	"strings"
	"testing"
)

func TestNativePageBuildsNormalizedBlocks(t *testing.T) {
	lines := []NativeLine{
		{Text: "  First line  ", X: 0.1, Y: 0.2, Width: 0.5, Height: 0.03},
		{Text: "", X: 0.1, Y: 0.3, Width: 0.5, Height: 0.03},
		{Text: "Second line", X: 0.1, Y: 0.24, Width: 0.4, Height: 0.03},
	}
	page := NativePage(3, lines)
	if page.PageNumber != 3 {
		t.Fatalf("pageNumber = %d", page.PageNumber)
	}
	if len(page.Blocks) != 2 {
		t.Fatalf("expected 2 blocks, got %d", len(page.Blocks))
	}
	first := page.Blocks[0]
	if first.ID != "page-3-block-1" || first.SourceType != "pdf-text-line" {
		t.Fatalf("unexpected block: %+v", first)
	}
	if first.Text != "First line" {
		t.Fatalf("text not trimmed: %q", first.Text)
	}
	if first.BBox == nil || first.BBox.Unit != "normalized" || first.BBox.Origin != "top-left" {
		t.Fatalf("bad bbox: %+v", first.BBox)
	}
	if len(first.SourceBBox) != 4 || first.SourceBBox[2] != first.BBox.X+first.BBox.Width {
		t.Fatalf("bad sourceBbox: %v", first.SourceBBox)
	}
	if page.Markdown != "First line\nSecond line" {
		t.Fatalf("unexpected markdown: %q", page.Markdown)
	}
	if page.Diagnostics.DetectionCount != 2 {
		t.Fatalf("detectionCount = %d", page.Diagnostics.DetectionCount)
	}
}

func TestNativePageClipsOutOfRangeBoxes(t *testing.T) {
	lines := []NativeLine{
		{Text: "ok", X: -0.1, Y: 0.95, Width: 0.5, Height: 0.2},
		{Text: "degenerate", X: 0.5, Y: 0.5, Width: 0, Height: 0.1},
	}
	page := NativePage(1, lines)
	if len(page.Blocks) != 1 {
		t.Fatalf("expected 1 block, got %d", len(page.Blocks))
	}
	box := page.Blocks[0].BBox
	if box.X < 0 || box.Y < 0 || box.X+box.Width > 1 || box.Y+box.Height > 1 {
		t.Fatalf("box not clipped: %+v", box)
	}
}

func TestOCRPageNormalizesPixelCoordinates(t *testing.T) {
	res := ocrBridgeResponse{
		Available:   true,
		ImageWidth:  1000,
		ImageHeight: 2000,
		Lines: []ocrBridgeLine{
			{Text: "Hello OCR", X: 100, Y: 200, Width: 400, Height: 60},
		},
	}
	page := ocrPage(2, "pages/page-0002.png", res)
	if len(page.Blocks) != 1 {
		t.Fatalf("expected 1 block, got %d", len(page.Blocks))
	}
	block := page.Blocks[0]
	if block.SourceType != "windows-ocr-line" {
		t.Fatalf("sourceType = %s", block.SourceType)
	}
	if block.BBox.X != 0.1 || block.BBox.Y != 0.1 || block.BBox.Width != 0.4 || block.BBox.Height != 0.03 {
		t.Fatalf("bad normalized bbox: %+v", block.BBox)
	}
	if page.ImageFile != "pages/page-0002.png" {
		t.Fatalf("imageFile = %q", page.ImageFile)
	}
}

func TestVisibleCharCount(t *testing.T) {
	tests := []struct {
		name string
		text string
		want int
	}{
		{name: "ASCII whitespace", text: "ab c\t\n", want: 3},
		{name: "Unicode text", text: "café 世界", want: 6},
		{name: "no-break space", text: strings.Repeat("\u00a0", NativeTextMinVisibleChars), want: 0},
		{name: "en space", text: strings.Repeat("\u2002", NativeTextMinVisibleChars), want: 0},
		{name: "em space", text: strings.Repeat("\u2003", NativeTextMinVisibleChars), want: 0},
		{name: "figure space", text: strings.Repeat("\u2007", NativeTextMinVisibleChars), want: 0},
		{name: "thin space", text: strings.Repeat("\u2009", NativeTextMinVisibleChars), want: 0},
		{name: "narrow no-break space", text: strings.Repeat("\u202f", NativeTextMinVisibleChars), want: 0},
		{name: "zero-width space", text: strings.Repeat("\u200b", NativeTextMinVisibleChars), want: 0},
		{name: "word joiner", text: strings.Repeat("\u2060", NativeTextMinVisibleChars), want: 0},
		{name: "byte-order mark", text: strings.Repeat("\ufeff", NativeTextMinVisibleChars), want: 0},
		{name: "variation selector", text: strings.Repeat("\ufe0f", NativeTextMinVisibleChars), want: 0},
		{name: "control", text: strings.Repeat("\x00", NativeTextMinVisibleChars), want: 0},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			if got := VisibleCharCount([]NativeLine{{Text: tt.text}}); got != tt.want {
				t.Fatalf("VisibleCharCount = %d, want %d", got, tt.want)
			}
		})
	}
}

func TestWindowsOCRFallsBackForInvisibleNativeText(t *testing.T) {
	provider := NewWindowsOCRProvider()
	lines := []NativeLine{{
		Text:   strings.Repeat("\u00a0\u200b\ufeff", NativeTextMinVisibleChars),
		X:      0.1,
		Y:      0.1,
		Width:  0.8,
		Height: 0.1,
	}}

	_, err := provider.ProcessPage(context.Background(), PageRequest{PageNumber: 1, NativeLines: lines})
	if err == nil || !strings.Contains(err.Error(), "no rendered image was provided for OCR") {
		t.Fatalf("expected invisible native text to fall through to OCR image validation, got %v", err)
	}
}
