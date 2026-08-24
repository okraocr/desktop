import type {
  CurrentDocument,
  InstallStatus,
  NativeLine,
  OllamaModel,
  PresidioStatus,
  ProviderStatus,
  RedactionDetection,
  Run,
  RunOutput,
  StructuredPage,
} from './types'

declare global {
  interface Window {
    __OKRA_TOKEN?: string
  }
}

const token = window.__OKRA_TOKEN ?? localStorage.getItem('okraToken') ?? ''

async function request(path: string, init?: RequestInit) {
  const res = await fetch(path, {
    ...init,
    headers: {
      'Content-Type': 'application/json',
      'X-Okra-Token': token,
      ...(init?.headers ?? {}),
    },
  })
  const data = await res.json().catch(() => ({}))
  if (!res.ok) {
    throw new Error((data as { error?: string }).error ?? `Request failed (${res.status})`)
  }
  return data
}

const post = (path: string, body?: unknown) =>
  request(path, { method: 'POST', body: body === undefined ? '{}' : JSON.stringify(body) })

export const api = {
  pendingDocument: () => request('/api/document/pending') as Promise<{ path: string | null }>,
  currentDocument: () =>
    request('/api/document/current') as Promise<{ document: CurrentDocument | null }>,
  openDialog: () => post('/api/document/dialog') as Promise<{ path: string | null; fileName?: string }>,
  selectDocument: (doc: CurrentDocument) => post('/api/document/select', doc),
  revealDocument: (path: string) => post('/api/document/reveal', { path }),
  saveDocumentCopy: async (fileName: string, bytes: Uint8Array) => {
    const body = bytes.buffer.slice(bytes.byteOffset, bytes.byteOffset + bytes.byteLength)
    const res = await fetch(`/api/document/save-copy?fileName=${encodeURIComponent(fileName)}`, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/pdf',
        'X-Okra-Token': token,
      },
      body,
    })
    const data = (await res.json().catch(() => ({}))) as { saved?: string | null; error?: string }
    if (!res.ok) throw new Error(data.error ?? `Request failed (${res.status})`)
    return data as { saved: string | null }
  },

  providers: () => request('/api/providers') as Promise<{ providers: ProviderStatus[] }>,
  installProvider: (id: string) => post(`/api/providers/${id}/install`) as Promise<{ started: boolean }>,
  installStatus: (id: string) =>
    request(`/api/providers/${id}/install-status`) as Promise<{ status: InstallStatus | null }>,
  ollamaModels: () =>
    request('/api/ollama/models') as Promise<{ models: OllamaModel[]; error?: string }>,
  presidioStatus: () =>
    request('/api/redaction/presidio/status') as Promise<{ status: PresidioStatus }>,
  installPresidio: () =>
    post('/api/redaction/presidio/install') as Promise<{ started: boolean }>,
  presidioInstallStatus: () =>
    request('/api/redaction/presidio/install-status') as Promise<{ status: InstallStatus | null }>,

  createRun: (input: {
    providerId: string
    sourcePath: string
    fileName: string
    pageCount: number
    ollamaModel?: string
  }) => post('/api/runs', input) as Promise<{ run: Run }>,
  listRuns: (sourcePath?: string) =>
    request(sourcePath ? `/api/runs?sourcePath=${encodeURIComponent(sourcePath)}` : '/api/runs') as Promise<{
      runs: Run[]
    }>,
  getRun: (id: string) =>
    request(`/api/runs/${id}`) as Promise<{ run: Run; completedPages: number[] }>,
  runOutput: (id: string) => request(`/api/runs/${id}/output`) as Promise<RunOutput>,
  postPage: (id: string, payload: { pageNumber: number; imageBase64?: string; nativeLines?: NativeLine[] }) =>
    post(`/api/runs/${id}/pages`, payload) as Promise<{ page: StructuredPage; skipped?: boolean }>,
  completeRun: (id: string) => post(`/api/runs/${id}/complete`) as Promise<{ run: Run }>,
  cancelRun: (id: string) => post(`/api/runs/${id}/cancel`) as Promise<{ run: Run }>,
  failRun: (id: string, message: string) => post(`/api/runs/${id}/fail`, { message }) as Promise<{ run: Run }>,
  resumeRun: (id: string) => post(`/api/runs/${id}/resume`) as Promise<{ run: Run; completedPages: number[] }>,
  revealRun: (id: string) => post(`/api/runs/${id}/reveal`),
  saveAs: (id: string, kind: 'markdown' | 'json') =>
    post(`/api/runs/${id}/save-as`, { kind }) as Promise<{ saved: string | null }>,
  redactions: (id: string) =>
    request(`/api/runs/${id}/redactions`) as Promise<{ detection: RedactionDetection | null }>,
  detectRedactions: (id: string, input: { entities?: string[]; minScore?: number; ollamaModel?: string }) =>
    post(`/api/runs/${id}/redactions/detect`, input) as Promise<{ detection: RedactionDetection }>,
  saveRedactedPdf: async (id: string, bytes: Uint8Array) => {
    const body = bytes.buffer.slice(bytes.byteOffset, bytes.byteOffset + bytes.byteLength)
    const res = await fetch(`/api/runs/${id}/redactions/save`, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/pdf',
        'X-Okra-Token': token,
      },
      body,
    })
    const data = (await res.json().catch(() => ({}))) as { saved?: string | null; error?: string }
    if (!res.ok) throw new Error(data.error ?? `Request failed (${res.status})`)
    return data as { saved: string | null }
  },
}

export async function fetchPdfBytes(path: string): Promise<ArrayBuffer> {
  const res = await fetch(`/api/document/file?path=${encodeURIComponent(path)}`, {
    headers: { 'X-Okra-Token': token },
  })
  if (!res.ok) {
    throw new Error(`Could not open ${path}`)
  }
  return res.arrayBuffer()
}
