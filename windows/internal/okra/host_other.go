//go:build !windows

package okra

func totalPhysicalMemoryGB() int { return 0 }

func freeDiskGB(path string) int { return 0 }
