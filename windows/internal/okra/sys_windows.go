//go:build windows

package okra

import (
	"os/exec"
	"syscall"
)

// hideConsoleWindow prevents a console window flash when spawning helper
// processes (PowerShell bridges) from the GUI app.
func hideConsoleWindow(cmd *exec.Cmd) {
	cmd.SysProcAttr = &syscall.SysProcAttr{HideWindow: true}
}
