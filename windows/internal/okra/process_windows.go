//go:build windows

package okra

import (
	"os"
	"unsafe"
)

// processAlive reports whether a process with the given PID is still running
// (GetExitCodeProcess STILL_ACTIVE), unlike exec.Cmd.ProcessState which is
// only set after Wait is called.
func processAlive(pid int) bool {
	const stillActive = 259
	handle, err := syscallOpenProcess(0x1000, false, uint32(pid)) // PROCESS_QUERY_LIMITED_INFORMATION
	if err != nil {
		return false
	}
	defer syscallCloseHandle(handle)
	var code uint32
	if err := getExitCodeProcess(handle, &code); err != nil {
		return false
	}
	return code == stillActive
}

func syscallOpenProcess(access uint32, inherit bool, pid uint32) (uintptr, error) {
	r1, _, err := procOpenProcess.Call(uintptr(access), boolToUintptr(inherit), uintptr(pid))
	if r1 == 0 {
		return 0, err
	}
	return r1, nil
}

func getExitCodeProcess(handle uintptr, code *uint32) error {
	r1, _, err := procGetExitCodeProcess.Call(handle, uintptr(unsafe.Pointer(code)))
	if r1 == 0 {
		return err
	}
	return nil
}

func syscallCloseHandle(handle uintptr) {
	procCloseHandle.Call(handle)
}

func boolToUintptr(v bool) uintptr {
	if v {
		return 1
	}
	return 0
}

var _ = os.Getpid // keep os import used on all paths
