// okraPDF for Windows — local-first PDF reader and parser.
//
// Mirrors the Ollama Windows desktop stack: a Go loopback server hosts the
// API, and a WebView2 window (webview_go) renders the React UI.
package main

import (
	"crypto/rand"
	"encoding/hex"
	"flag"
	"fmt"
	"io/fs"
	"net"
	"net/http"
	"os"
	"strings"

	webview "github.com/webview/webview_go"

	"github.com/okrapdf/desktop/windows/internal/okra"
	"github.com/okrapdf/desktop/windows/internal/webui"
)

func main() {
	dev := flag.Bool("dev", false, "load the UI from the Vite dev server at http://localhost:5173 and enable WebView2 devtools")
	serveOnly := flag.Bool("serve-only", false, "run the loopback API without opening a window")
	port := flag.Int("port", 0, "loopback port (0 = random)")
	flag.Parse()

	store, err := okra.NewStore(okra.RunsRoot())
	if err != nil {
		fatal("could not prepare the runs directory", err)
	}
	ollamaClient := okra.NewOllamaClient()
	chandraProvider := okra.NewChandraOCRProvider()
	providers := []okra.Provider{
		okra.NewWindowsOCRProvider(),
		chandraProvider,
		okra.NewOllamaProvider(ollamaClient),
	}

	token := randomToken()
	if *serveOnly {
		// Headless/testing mode: allow a fixed token via the environment so
		// API clients can authenticate without reading stdout.
		if fixed := os.Getenv("OKRA_SERVE_TOKEN"); fixed != "" {
			token = fixed
		}
	}
	staticFS, err := fs.Sub(webui.Dist, "dist")
	if err != nil {
		fatal("embedded UI is missing", err)
	}
	server := okra.NewServer(store, providers, ollamaClient, token, staticFS)
	defer server.Shutdown()

	listener, err := net.Listen("tcp", fmt.Sprintf("127.0.0.1:%d", *port))
	if err != nil {
		fatal("could not start the local server", err)
	}
	go func() {
		_ = http.Serve(listener, server.Handler())
	}()

	url := fmt.Sprintf("http://127.0.0.1:%d/", listener.Addr().(*net.TCPAddr).Port)
	if *dev {
		url = "http://localhost:5173/"
	}

	// Command-line PDF (mirrors openCommandLinePDFIfPresent on macOS).
	for _, arg := range flag.Args() {
		if strings.HasSuffix(strings.ToLower(arg), ".pdf") {
			if _, err := os.Stat(arg); err == nil {
				server.SetPendingOpen(arg)
			}
			break
		}
	}

	if *serveOnly {
		fmt.Printf("okraPDF server listening at %s (token: %s)\n", url, token)
		select {}
	}

	w := webview.New(*dev)
	defer w.Destroy()
	defer chandraProvider.Shutdown() // stop the persistent worker on exit
	w.SetTitle("okraPDF")
	w.SetSize(1360, 860, webview.HintMin)
	w.Init(fmt.Sprintf("window.__OKRA_TOKEN = %q;", token))
	w.Navigate(url)
	w.Run()
}

func randomToken() string {
	buf := make([]byte, 16)
	if _, err := rand.Read(buf); err != nil {
		return ""
	}
	return hex.EncodeToString(buf)
}

func fatal(message string, err error) {
	fmt.Fprintf(os.Stderr, "%s: %v\n", message, err)
	os.Exit(1)
}
