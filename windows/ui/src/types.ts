// Types mirroring the Go API (which mirrors the macOS Swift contracts).

export interface BoundingBox {
  x: number
  y: number
  width: number
  height: number
  unit: string
  origin: string
}

export interface Block {
  id: string
  type: string
  sourceType: string
  text: string
  html?: string
  bbox?: BoundingBox
  sourceBbox?: number[]
  sourceBboxScale?: number
}

export interface Diagnostics {
  rawCharacterCount: number
  decodedCharacterCount: number
  tokenArtifactCount: number
  detectionCount: number
  malformedDetectionCount: number
  duplicateBlockCount: number
  loopDetected: boolean
  warnings: string[]
  blockCount?: number
}

export interface StructuredPage {
  pageNumber: number
  imageFile: string
  markdown: string
  plainText: string
  blocks: Block[]
  diagnostics: Diagnostics
  provenance?: string
}

export interface StructuredDocument {
  schemaVersion: number
  object: string
  provider: { id: string; name: string }
  title: string
  pageCount: number
  completedPageCount: number
  complete: boolean
  simulation: boolean
  pages: StructuredPage[]
}

export interface PageLifecycle {
  parserID: string
  pageNumber: number
  state: string
  detail?: string
  updatedAt: string
}

export interface Run {
  id: string
  sourcePath: string
  fileName: string
  providerId: string
  providerName: string
  status: 'running' | 'succeeded' | 'failed' | 'canceled' | 'interrupted'
  outputPath?: string
  structuredOutputPath?: string
  errorMessage?: string
  pageCount: number
  completedPageCount?: number
  totalPageCount?: number
  startedAt: string
  completedAt?: string
  progress?: number
  statusMessage?: string
  updatedAt?: string
  cancelRequestedAt?: string
  resumeCount?: number
  eventSequence?: number
  pageLifecycles?: PageLifecycle[]
}

export interface Availability {
  state: 'ready' | 'setupRequired' | 'unavailable'
  message: string
}

export interface InstallStatus {
  phase: 'idle' | 'venv' | 'runtime' | 'model' | 'verify' | 'done' | 'error'
  message: string
  logTail?: string[]
  startedAt?: string
  done: boolean
}

export interface ProviderStatus {
  id: string
  name: string
  summary: string
  setupNote?: string
  availability: Availability
}

export interface OllamaModel {
  name: string
  supportsVision: boolean
}

export interface NativeLine {
  text: string
  x: number
  y: number
  width: number
  height: number
}

export interface CurrentDocument {
  path: string
  fileName: string
  pageCount: number
}

export interface RunOutput {
  markdown: string
  structured?: StructuredDocument
}

export interface PresidioStatus {
  availability: Availability
  running: boolean
  managed: boolean
  ollamaSupported: boolean
}

export interface RedactionBox {
  id: string
  page: number
  x: number
  y: number
  w: number
  h: number
  type: string
  text: string
  score: number
  source: 'presidio' | 'presidio+ollama' | string
  blockId: string
}

export interface RedactionDetection {
  schemaVersion: number
  object: 'pii_redaction_candidates'
  runId: string
  createdAt: string
  ollamaModel?: string
  boxes: RedactionBox[]
  stats: {
    total: number
    byType: Record<string, number>
    bySource: Record<string, number>
  }
}
