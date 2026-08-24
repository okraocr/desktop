//go:build windows

package okra

import (
	"path/filepath"
	"unsafe"

	"golang.org/x/sys/windows"
)

// totalPhysicalMemoryGB returns installed RAM in GiB (0 on failure), used by
// the managed-parser host gate (mirrors LocalParserHostProfile on macOS).
func totalPhysicalMemoryGB() int {
	var status struct {
		Length               uint32
		MemoryLoad           uint32
		TotalPhys            uint64
		AvailPhys            uint64
		TotalPageFile        uint64
		AvailPageFile        uint64
		TotalVirtual         uint64
		AvailVirtual         uint64
		AvailExtendedVirtual uint64
	}
	status.Length = uint32(unsafe.Sizeof(status))
	r1, _, err := procGlobalMemoryStatusEx.Call(uintptr(unsafe.Pointer(&status)))
	if r1 == 0 {
		_ = err
		return 0
	}
	return int(status.TotalPhys / (1024 * 1024 * 1024))
}

// freeDiskGB returns free bytes on the volume hosting path, in GiB (0 on failure).
func freeDiskGB(path string) int {
	abs, err := filepath.Abs(path)
	if err != nil {
		return 0
	}
	volume := filepath.VolumeName(abs) + `\`
	volumePtr, err := windows.UTF16PtrFromString(volume)
	if err != nil {
		return 0
	}
	var freeBytesAvailable, totalBytes, totalFreeBytes uint64
	if err := windows.GetDiskFreeSpaceEx(volumePtr, &freeBytesAvailable, &totalBytes, &totalFreeBytes); err != nil {
		return 0
	}
	return int(freeBytesAvailable / (1024 * 1024 * 1024))
}
