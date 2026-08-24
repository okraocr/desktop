//go:build !windows

package okra

import "os/exec"

func hideConsoleWindow(cmd *exec.Cmd) {}
