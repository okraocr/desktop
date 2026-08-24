package webui

import "embed"

// Dist holds the built Vite UI (ui/ builds into this directory).
//
//go:embed all:dist
var Dist embed.FS
