//go:build windows

package okra

import "syscall"

var (
	modkernel32              = syscall.NewLazyDLL("kernel32.dll")
	procGlobalMemoryStatusEx = modkernel32.NewProc("GlobalMemoryStatusEx")
	procOpenProcess          = modkernel32.NewProc("OpenProcess")
	procGetExitCodeProcess   = modkernel32.NewProc("GetExitCodeProcess")
	procCloseHandle          = modkernel32.NewProc("CloseHandle")
)
