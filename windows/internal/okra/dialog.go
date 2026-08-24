package okra

import (
	"context"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"time"
)

// OpenPDFDialog shows a native open-file dialog via a hidden PowerShell host
// (webview_go has no dialog API). Returns "" when the user cancels.
func OpenPDFDialog(ctx context.Context) (string, error) {
	script := `Add-Type -AssemblyName System.Windows.Forms
$d = New-Object System.Windows.Forms.OpenFileDialog
$d.Title = 'Open PDF'
$d.Filter = 'PDF files (*.pdf)|*.pdf'
$d.Multiselect = $false
if ($d.ShowDialog() -eq 'OK') { [Console]::Out.Write($d.FileName) }`
	return runDialogScript(ctx, script)
}

// SaveTextDialog shows a native save-file dialog for exporting output.
func SaveTextDialog(ctx context.Context, title, defaultName, filter string) (string, error) {
	script := fmt.Sprintf(`Add-Type -AssemblyName System.Windows.Forms
$d = New-Object System.Windows.Forms.SaveFileDialog
$d.Title = %s
$d.FileName = %s
$d.Filter = %s
if ($d.ShowDialog() -eq 'OK') { [Console]::Out.Write($d.FileName) }`, psQuote(title), psQuote(defaultName), psQuote(filter))
	return runDialogScript(ctx, script)
}

// RevealPath opens Explorer with the file selected (macOS revealSelectedPDF).
func RevealPath(ctx context.Context, path string) error {
	if _, err := os.Stat(path); err != nil {
		dir := filepath.Dir(path)
		if _, dirErr := os.Stat(dir); dirErr != nil {
			return fmt.Errorf("nothing to reveal: %s", path)
		}
		return startExplorer(ctx, dir)
	}
	return startExplorer(ctx, "/select,"+path)
}

func startExplorer(ctx context.Context, arg string) error {
	cmd := exec.CommandContext(ctx, "explorer.exe", arg)
	hideConsoleWindow(cmd)
	// explorer.exe returns non-zero for successful /select launches; ignore.
	_ = cmd.Start()
	return nil
}

func runDialogScript(ctx context.Context, script string) (string, error) {
	dialogCtx, cancel := context.WithTimeout(ctx, 5*time.Minute)
	defer cancel()
	cmd := exec.CommandContext(dialogCtx, "powershell.exe",
		"-NoProfile", "-NonInteractive", "-ExecutionPolicy", "Bypass", "-Command", script)
	hideConsoleWindow(cmd)
	out, err := cmd.Output()
	if err != nil {
		return "", err
	}
	return strings.TrimSpace(string(out)), nil
}

func psQuote(value string) string {
	return "'" + strings.ReplaceAll(value, "'", "''") + "'"
}
