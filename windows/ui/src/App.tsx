import { useCallback, useEffect, useMemo, useRef, useState } from 'react'
import { api, fetchPdfBytes } from './api'
import type {
  CurrentDocument,
  InstallStatus,
  OllamaModel,
  PresidioStatus,
  ProviderStatus,
  RedactionDetection,
  Run,
  RunOutput,
} from './types'
import type { PdfDocument } from './pdf'
import { movePageHistory as stepPageHistory, pushPageHistory } from './document-model'
import {
  annotationsEqual,
  clearEditorDraft,
  commitEditorHistory,
  redoEditorHistory,
  readEditorDraft,
  undoEditorHistory,
  writeAnnotationsToPdf,
  writeEditorDraft,
  type AnnotationTool,
  type EditorAnnotation,
  type EditorDraft,
  type ViewMode,
} from './editor'
import {
  NATIVE_TEXT_MIN_CHARS,
  extractNativeLines,
  loadPdf,
  renderPagePngBase64,
  rasterizeRedactedPdf,
  visibleCharCount,
} from './pdf'
import { Toolbar } from './components/Toolbar'
import { ExtractPanel } from './components/ExtractPanel'
import { DocumentTabs } from './components/DocumentTabs'
import { DocumentViewer } from './components/DocumentViewer'
import { EditorToolbar } from './components/EditorToolbar'
import { NavigationPanel } from './components/NavigationPanel'

type OutputTab = 'markdown' | 'blocks' | 'redact' | 'json'

interface DocumentSession extends CurrentDocument {
  id: string
  bytes: ArrayBuffer
  pdf: PdfDocument
  page: number
  zoom: number
  viewMode: ViewMode
  annotations: EditorAnnotation[]
  savedAnnotations: EditorAnnotation[]
  undo: EditorAnnotation[][]
  redo: EditorAnnotation[][]
  recoveryDraft: EditorDraft | null
  history: number[]
  historyIndex: number
}

export default function App() {
  const [documents, setDocuments] = useState<DocumentSession[]>([])
  const [activeId, setActiveId] = useState<string | null>(null)
  const [splitId, setSplitId] = useState<string | null>(null)
  const [busyOpen, setBusyOpen] = useState(false)
  const [navigationVisible, setNavigationVisible] = useState(true)
  const [searchQuery, setSearchQuery] = useState('')
  const [editorTool, setEditorTool] = useState<AnnotationTool>('select')
  const [editorColor, setEditorColor] = useState('#f59e0b')
  const [editorOpacity, setEditorOpacity] = useState(0.55)
  const [editorLineWidth, setEditorLineWidth] = useState(2)
  const [editorFontSize, setEditorFontSize] = useState(14)
  const [editorImageDataUrl, setEditorImageDataUrl] = useState<string | null>(null)
  const [selectedAnnotationId, setSelectedAnnotationId] = useState<string | null>(null)

  const activeDocument = useMemo(
    () => documents.find((document) => document.id === activeId) ?? null,
    [activeId, documents],
  )
  const splitDocument = useMemo(
    () => documents.find((document) => document.id === splitId) ?? null,
    [documents, splitId],
  )
  const doc: CurrentDocument | null = activeDocument
    ? { path: activeDocument.path, fileName: activeDocument.fileName, pageCount: activeDocument.pageCount }
    : null
  const pdf = activeDocument?.pdf ?? null
  const page = activeDocument?.page ?? 1
  const zoom = activeDocument?.zoom ?? 1.25

  const patchDocument = useCallback((id: string, update: Partial<DocumentSession> | ((current: DocumentSession) => Partial<DocumentSession>)) => {
    setDocuments((current) => current.map((document) => {
      if (document.id !== id) return document
      return { ...document, ...(typeof update === 'function' ? update(document) : update) }
    }))
  }, [])

  const setPage = useCallback((next: number) => {
    if (!activeId) return
    patchDocument(activeId, (current) => {
      const target = Math.max(1, Math.min(current.pageCount, next))
      if (target === current.page) return {}
      return { page: target, ...pushPageHistory(current, target) }
    })
  }, [activeId, patchDocument])

  const setZoom = useCallback((next: number) => {
    if (activeId) patchDocument(activeId, { zoom: next })
  }, [activeId, patchDocument])

  const [providers, setProviders] = useState<ProviderStatus[]>([])
  const [providerId, setProviderId] = useState('windows-ocr')
  const [ollamaModels, setOllamaModels] = useState<OllamaModel[]>([])
  const [ollamaModel, setOllamaModel] = useState('')
  const [installStatus, setInstallStatus] = useState<InstallStatus | null>(null)
  const [installing, setInstalling] = useState(false)

  const [runs, setRuns] = useState<Run[]>([])
  const [activeRun, setActiveRun] = useState<Run | null>(null)
  const [parsing, setParsing] = useState(false)
  const [progressCompleted, setProgressCompleted] = useState(0)
  const [progressTotal, setProgressTotal] = useState(0)
  const [pageStates, setPageStates] = useState<Record<number, string>>({})

  const [output, setOutput] = useState<RunOutput | null>(null)
  const [tab, setTab] = useState<OutputTab>('markdown')
  const [showBoxes, setShowBoxes] = useState(true)
  const [selectedBlockId, setSelectedBlockId] = useState<string | null>(null)
  const [hoveredBlockId, setHoveredBlockId] = useState<string | null>(null)

  const [presidioStatus, setPresidioStatus] = useState<PresidioStatus | null>(null)
  const [presidioInstallStatus, setPresidioInstallStatus] = useState<InstallStatus | null>(null)
  const [presidioInstalling, setPresidioInstalling] = useState(false)
  const [redactionUseOllama, setRedactionUseOllama] = useState(false)
  const [redactionOllamaModel, setRedactionOllamaModel] = useState('')
  const [redactionDetection, setRedactionDetection] = useState<RedactionDetection | null>(null)
  const [enabledRedactionIds, setEnabledRedactionIds] = useState<Set<string>>(new Set())
  const [selectedRedactionId, setSelectedRedactionId] = useState<string | null>(null)
  const [hoveredRedactionId, setHoveredRedactionId] = useState<string | null>(null)
  const [detectingRedactions, setDetectingRedactions] = useState(false)
  const [savingRedactedPdf, setSavingRedactedPdf] = useState(false)

  const [status, setStatus] = useState('Choose a local parser and extract.')
  const [error, setError] = useState<string | null>(null)

  const cancelRef = useRef(false)
  const pdfRef = useRef<PdfDocument | null>(null)
  pdfRef.current = pdf

  // ---------- data loading ----------

  const refreshRuns = useCallback(async (sourcePath?: string) => {
    try {
      const { runs: list } = await api.listRuns(sourcePath)
      setRuns(list)
      return list
    } catch {
      return []
    }
  }, [])

  const refreshProviders = useCallback(async () => {
    try {
      const { providers: list } = await api.providers()
      setProviders(list)
    } catch (e) {
      setError(e instanceof Error ? e.message : String(e))
    }
  }, [])

  const refreshOllamaModels = useCallback(async () => {
    try {
      const { models, error: modelsError } = await api.ollamaModels()
      setOllamaModels(models)
      if (modelsError) setStatus(modelsError)
      const vision = models.find((m) => m.supportsVision)
      setOllamaModel((current) => current || vision?.name || models[0]?.name || '')
      const textModel = models.find((m) => !m.supportsVision) ?? models[0]
      setRedactionOllamaModel((current) => current || textModel?.name || '')
    } catch {
      setOllamaModels([])
    }
  }, [])

  const refreshPresidioStatus = useCallback(async () => {
    try {
      const { status: nextStatus } = await api.presidioStatus()
      setPresidioStatus(nextStatus)
    } catch (e) {
      setError(e instanceof Error ? e.message : String(e))
    }
  }, [])

  useEffect(() => {
    refreshProviders()
    refreshOllamaModels()
    refreshPresidioStatus()
    api
      .pendingDocument()
      .then(({ path }) => {
        if (path) void openPdfPath(path)
      })
      .catch(() => {})
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [])

  // ---------- managed provider setup ----------

  async function startInstall(targetProviderId: string) {
    setError(null)
    try {
      await api.installProvider(targetProviderId)
      setInstalling(true)
      setStatus('Setting up the managed parser…')
    } catch (e) {
      setError(e instanceof Error ? e.message : String(e))
    }
  }

  useEffect(() => {
    if (!installing) return
    let cancelled = false
    const poll = async () => {
      try {
        const { status } = await api.installStatus(providerId)
        if (cancelled) return
        setInstallStatus(status)
        if (status?.done || status?.phase === 'error') {
          setInstalling(false)
          setStatus(status.message ?? 'Setup finished.')
          await refreshProviders()
        }
      } catch {
        /* keep polling */
      }
    }
    void poll()
    const interval = setInterval(() => void poll(), 2000)
    return () => {
      cancelled = true
      clearInterval(interval)
    }
  }, [installing, providerId, refreshProviders])

  async function startPresidioInstall() {
    setError(null)
    try {
      await api.installPresidio()
      setPresidioInstalling(true)
      setStatus('Setting up Microsoft Presidio locally…')
    } catch (e) {
      setError(e instanceof Error ? e.message : String(e))
    }
  }

  useEffect(() => {
    if (!presidioInstalling) return
    let cancelled = false
    const poll = async () => {
      try {
        const { status: nextStatus } = await api.presidioInstallStatus()
        if (cancelled) return
        setPresidioInstallStatus(nextStatus)
        if (nextStatus?.done || nextStatus?.phase === 'error') {
          setPresidioInstalling(false)
          setStatus(nextStatus.message ?? 'Presidio setup finished.')
          await refreshPresidioStatus()
        }
      } catch {
        /* keep polling */
      }
    }
    void poll()
    const interval = setInterval(() => void poll(), 2000)
    return () => {
      cancelled = true
      clearInterval(interval)
    }
  }, [presidioInstalling, refreshPresidioStatus])

  // ---------- document ----------

  function resetDocumentOutput() {
    setOutput(null)
    setActiveRun(null)
    setSelectedBlockId(null)
    setHoveredBlockId(null)
    setRedactionDetection(null)
    setEnabledRedactionIds(new Set())
    setSelectedRedactionId(null)
    setProgressCompleted(0)
    setProgressTotal(0)
    setPageStates({})
    setSearchQuery('')
    setSelectedAnnotationId(null)
  }

  async function activateDocument(id: string) {
    const target = documents.find((document) => document.id === id)
    if (!target) return
    if (parsing && id !== activeId) {
      setStatus('Finish or cancel the active parse before switching documents.')
      return
    }
    setActiveId(id)
    if (splitId === id) setSplitId(null)
    resetDocumentOutput()
    await api.selectDocument({ path: target.path, fileName: target.fileName, pageCount: target.pageCount })
    const list = await refreshRuns(target.path)
    const latestSucceeded = list.find((run) => run.status === 'succeeded')
    if (latestSucceeded) await viewRun(latestSucceeded, target)
    else setStatus('Reading only. Nothing is parsed until you choose Parse.')
  }

  async function openPdfPath(path: string): Promise<DocumentSession | null> {
    setBusyOpen(true)
    setError(null)
    try {
      const existing = documents.find((document) => document.path.toLocaleLowerCase() === path.toLocaleLowerCase())
      if (existing) {
        await activateDocument(existing.id)
        return existing
      }
      const bytes = await fetchPdfBytes(path)
      const sourceBytes = bytes.slice(0)
      const loaded = await loadPdf(bytes.slice(0))
      const fileName = path.split(/[\\/]/).pop() ?? 'document.pdf'
      const document: CurrentDocument = { path, fileName, pageCount: loaded.numPages }
      await api.selectDocument(document)
      const id = globalThis.crypto?.randomUUID?.() ?? `document-${Date.now()}`
      const session: DocumentSession = {
        ...document,
        id,
        bytes: sourceBytes,
        pdf: loaded,
        page: 1,
        zoom: 1.25,
        viewMode: 'single',
        annotations: [],
        savedAnnotations: [],
        undo: [],
        redo: [],
        recoveryDraft: readEditorDraft(path),
        history: [1],
        historyIndex: 0,
      }
      setDocuments((current) => [...current, session])
      setActiveId(id)
      resetDocumentOutput()
      setStatus('Reading only. Nothing is parsed until you choose Parse.')
      const list = await refreshRuns(path)
      const latestSucceeded = list.find((run) => run.status === 'succeeded')
      if (latestSucceeded) {
        await viewRun(latestSucceeded, document)
      }
      return session
    } catch (e) {
      setError(e instanceof Error ? e.message : String(e))
      return null
    } finally {
      setBusyOpen(false)
    }
  }

  async function openViaDialog() {
    setBusyOpen(true)
    setError(null)
    try {
      const { path } = await api.openDialog()
      if (path) await openPdfPath(path)
    } catch (e) {
      setError(e instanceof Error ? e.message : String(e))
    } finally {
      setBusyOpen(false)
    }
  }

  // ---------- runs ----------

  async function viewRun(run: Run, knownDoc?: CurrentDocument) {
    setError(null)
    const currentPath = knownDoc?.path ?? doc?.path
    if (run.sourcePath !== currentPath) {
      await openPdfPath(run.sourcePath)
    }
    setActiveRun(run)
    setProgressCompleted(run.completedPageCount ?? 0)
    setProgressTotal(run.pageCount)
    const states: Record<number, string> = {}
    for (const lifecycle of run.pageLifecycles ?? []) states[lifecycle.pageNumber] = lifecycle.state
    setPageStates(states)
    if (run.status === 'succeeded') {
      try {
        const runOutput = await api.runOutput(run.id)
        setOutput(runOutput)
        const { detection } = await api.redactions(run.id)
        setRedactionDetection(detection)
        setEnabledRedactionIds(new Set(detection?.boxes.map((box) => box.id) ?? []))
        setStatus(run.statusMessage ?? 'Extraction complete.')
      } catch {
        setOutput(null)
        setRedactionDetection(null)
        setEnabledRedactionIds(new Set())
      }
    } else {
      setOutput(null)
      setStatus(run.statusMessage ?? run.errorMessage ?? `Run ${run.status}.`)
    }
  }

  async function startParse(resumeRun: Run | undefined, targetDoc: CurrentDocument) {
    const pdfDoc = 'pdf' in targetDoc && targetDoc.pdf instanceof Object
      ? targetDoc.pdf as PdfDocument
      : documents.find((document) => document.path === targetDoc.path)?.pdf ?? pdfRef.current
    if (!pdfDoc || parsing) return
    const doc = targetDoc
    setError(null)

    let run: Run
    let completedPages: number[] = []
    let runProviderId = providerId
    try {
      if (resumeRun) {
        const resumed = await api.resumeRun(resumeRun.id)
        run = resumed.run
        completedPages = resumed.completedPages
        runProviderId = run.providerId
        if (runProviderId !== providerId) setProviderId(runProviderId)
      } else {
        const created = await api.createRun({
          providerId,
          sourcePath: doc.path,
          fileName: doc.fileName,
          pageCount: doc.pageCount,
          ollamaModel: providerId === 'ollama' ? ollamaModel : undefined,
        })
        run = created.run
      }
    } catch (e) {
      setError(e instanceof Error ? e.message : String(e))
      return
    }

    setParsing(true)
    cancelRef.current = false
    setActiveRun(run)
    setOutput(null)
    setSelectedBlockId(null)
    setRedactionDetection(null)
    setEnabledRedactionIds(new Set())
    setSelectedRedactionId(null)
    setProgressTotal(run.pageCount)
    setProgressCompleted(completedPages.length)
    const states: Record<number, string> = {}
    for (let p = 1; p <= run.pageCount; p++) {
      states[p] = completedPages.includes(p) ? 'succeeded' : 'idle'
    }
    setPageStates(states)
    setStatus(resumeRun ? 'Resuming from completed pages…' : `Parsing with ${run.providerName}…`)

    const completedSet = new Set(completedPages)
    let failed: string | null = null

    for (let pageNumber = 1; pageNumber <= run.pageCount; pageNumber++) {
      if (cancelRef.current) break
      if (completedSet.has(pageNumber)) continue

      setPageStates((prev) => ({ ...prev, [pageNumber]: 'running' }))
      try {
        const pdfPage = await pdfDoc.getPage(pageNumber)
        let payload: { pageNumber: number; imageBase64?: string; nativeLines?: import('./types').NativeLine[] }
        if (runProviderId === 'windows-ocr') {
          const lines = await extractNativeLines(pdfPage)
          if (visibleCharCount(lines) >= NATIVE_TEXT_MIN_CHARS) {
            payload = { pageNumber, nativeLines: lines }
          } else {
            payload = { pageNumber, imageBase64: await renderPagePngBase64(pdfPage) }
          }
        } else {
          payload = { pageNumber, imageBase64: await renderPagePngBase64(pdfPage) }
        }
        await api.postPage(run.id, payload)
        completedSet.add(pageNumber)
        setPageStates((prev) => ({ ...prev, [pageNumber]: 'succeeded' }))
        setProgressCompleted(completedSet.size)
      } catch (e) {
        const message = e instanceof Error ? e.message : String(e)
        failed = message
        setPageStates((prev) => ({ ...prev, [pageNumber]: 'failed' }))
        break
      }
    }

    if (failed) {
      setError(failed)
      setStatus('Parse failed. Completed pages are kept for resume.')
      try {
        await api.failRun(run.id, failed)
      } catch {
        /* run state best-effort */
      }
    } else if (cancelRef.current) {
      try {
        await api.cancelRun(run.id)
        setStatus('Canceled. Completed pages are kept for resume.')
      } catch {
        /* already terminal */
      }
    } else {
      try {
        const { run: finished } = await api.completeRun(run.id)
        setActiveRun(finished)
        const runOutput = await api.runOutput(finished.id)
        setOutput(runOutput)
        setRedactionDetection(null)
        setEnabledRedactionIds(new Set())
        setStatus(finished.statusMessage ?? 'Extraction complete.')
        setTab('markdown')
      } catch (e) {
        setError(e instanceof Error ? e.message : String(e))
      }
    }

    setParsing(false)
    await refreshRuns(doc.path)
    if (failed || cancelRef.current) {
      try {
        const { run: latest } = await api.getRun(run.id)
        setActiveRun(latest)
      } catch {
        /* keep stale */
      }
    }
  }

  async function cancelParse() {
    cancelRef.current = true
  }

  async function resumeRun(run: Run) {
    if (parsing) return
    const target = doc?.path === run.sourcePath ? doc : await openPdfPath(run.sourcePath)
    if (!target) return
    await startParse(run, target)
  }

  // ---------- output actions ----------

  async function copyOutput() {
    if (!output) return
    const text =
      tab === 'json' ? JSON.stringify(output.structured ?? {}, null, 2) : output.markdown
    try {
      await navigator.clipboard.writeText(text)
      setStatus('Copied to clipboard.')
    } catch {
      setError('Could not copy to the clipboard.')
    }
  }

  async function saveOutputAs(kind: 'markdown' | 'json') {
    if (!activeRun) return
    try {
      const { saved } = await api.saveAs(activeRun.id, kind)
      if (saved) setStatus(`Saved to ${saved}`)
    } catch (e) {
      setError(e instanceof Error ? e.message : String(e))
    }
  }

  async function revealActiveRun() {
    if (!activeRun) return
    try {
      await api.revealRun(activeRun.id)
    } catch (e) {
      setError(e instanceof Error ? e.message : String(e))
    }
  }

  function closeDocument(id: string) {
    const target = documents.find((document) => document.id === id)
    if (!target) return
    if (parsing && id === activeId) {
      setStatus('Finish or cancel the active parse before closing this document.')
      return
    }
    if (!annotationsEqual(target.annotations, target.savedAnnotations) && !window.confirm(`Close ${target.fileName} and discard unsaved edits?`)) return
    const remaining = documents.filter((document) => document.id !== id)
    setDocuments(remaining)
    if (splitId === id) setSplitId(null)
    if (activeId === id) {
      const next = remaining[Math.max(0, documents.findIndex((document) => document.id === id) - 1)] ?? null
      setActiveId(next?.id ?? null)
      resetDocumentOutput()
      if (next) {
        void api.selectDocument({ path: next.path, fileName: next.fileName, pageCount: next.pageCount })
        void refreshRuns(next.path)
      } else {
        setRuns([])
        setStatus('Open a PDF to read, compare, search, or edit it.')
      }
    }
  }

  function updateAnnotations(next: EditorAnnotation[], recordHistory = true) {
    if (!activeDocument) return
    patchDocument(activeDocument.id, (current) => commitEditorHistory(current, next, recordHistory))
    if (annotationsEqual(next, activeDocument.savedAnnotations)) clearEditorDraft(activeDocument.path)
    else writeEditorDraft(activeDocument.path, next)
  }

  function undoEditor() {
    if (!activeDocument) return
    const previous = undoEditorHistory(activeDocument)
    if (!previous) return
    patchDocument(activeDocument.id, previous)
    if (annotationsEqual(previous.annotations, activeDocument.savedAnnotations)) clearEditorDraft(activeDocument.path)
    else writeEditorDraft(activeDocument.path, previous.annotations)
    setSelectedAnnotationId(null)
  }

  function redoEditor() {
    if (!activeDocument) return
    const next = redoEditorHistory(activeDocument)
    if (!next) return
    patchDocument(activeDocument.id, next)
    if (annotationsEqual(next.annotations, activeDocument.savedAnnotations)) clearEditorDraft(activeDocument.path)
    else writeEditorDraft(activeDocument.path, next.annotations)
    setSelectedAnnotationId(null)
  }

  function deleteSelectedAnnotation() {
    if (!activeDocument || !selectedAnnotationId) return
    updateAnnotations(activeDocument.annotations.filter((annotation) => annotation.id !== selectedAnnotationId))
    setSelectedAnnotationId(null)
  }

  async function saveEditedCopy() {
    if (!activeDocument) return
    setError(null)
    setStatus('Writing annotations into a new PDF…')
    try {
      const edited = await writeAnnotationsToPdf(activeDocument.bytes, activeDocument.annotations)
      const { saved } = await api.saveDocumentCopy(activeDocument.fileName, edited)
      if (!saved) {
        setStatus('Save canceled. Your edits are still in the recovery draft.')
        return
      }
      patchDocument(activeDocument.id, { savedAnnotations: activeDocument.annotations, recoveryDraft: null })
      clearEditorDraft(activeDocument.path)
      setStatus(`Saved edited PDF to ${saved}`)
    } catch (e) {
      setError(e instanceof Error ? e.message : String(e))
    }
  }

  function restoreDraft() {
    if (!activeDocument?.recoveryDraft) return
    const recovered = activeDocument.recoveryDraft.annotations
    patchDocument(activeDocument.id, {
      annotations: recovered,
      undo: [activeDocument.annotations],
      redo: [],
      recoveryDraft: null,
    })
    writeEditorDraft(activeDocument.path, recovered)
    setStatus(`Recovered ${recovered.length} unsaved annotation${recovered.length === 1 ? '' : 's'}.`)
  }

  function discardDraft() {
    if (!activeDocument) return
    clearEditorDraft(activeDocument.path)
    patchDocument(activeDocument.id, { recoveryDraft: null })
    setStatus('Recovery draft discarded.')
  }

  function moveHistory(direction: -1 | 1) {
    if (!activeDocument) return
    const next = stepPageHistory(activeDocument, direction)
    if (next.page === undefined) return
    patchDocument(activeDocument.id, { page: next.page, historyIndex: next.historyIndex })
  }

  async function followDestination(destination: unknown, target = activeDocument) {
    if (!target || !destination) return
    try {
      const explicit = typeof destination === 'string' ? await target.pdf.getDestination(destination) : destination
      if (!Array.isArray(explicit) || !explicit[0]) return
      const first = explicit[0]
      const pageIndex = typeof first === 'number' ? first : await target.pdf.getPageIndex(first)
      if (target.id === activeId) setPage(pageIndex + 1)
      else patchDocument(target.id, { page: pageIndex + 1 })
    } catch {
      setStatus('That document link could not be resolved.')
    }
  }

  async function detectPII() {
    if (!activeRun || !output?.structured || detectingRedactions) return
    setError(null)
    setDetectingRedactions(true)
    setTab('redact')
    setStatus(
      redactionUseOllama
        ? `Detecting PII locally with Presidio + ${redactionOllamaModel}…`
        : 'Detecting PII locally with Microsoft Presidio…',
    )
    try {
      const { detection } = await api.detectRedactions(activeRun.id, {
        minScore: 0.5,
        ollamaModel: redactionUseOllama ? redactionOllamaModel : undefined,
      })
      setRedactionDetection(detection)
      setEnabledRedactionIds(new Set(detection.boxes.map((box) => box.id)))
      setSelectedRedactionId(detection.boxes[0]?.id ?? null)
      if (detection.boxes[0]) setPage(detection.boxes[0].page)
      setStatus(`Presidio found ${detection.stats.total} candidate redaction boxes. Review them before export.`)
      await refreshPresidioStatus()
    } catch (e) {
      setError(e instanceof Error ? e.message : String(e))
    } finally {
      setDetectingRedactions(false)
    }
  }

  function toggleRedaction(id: string, enabled: boolean) {
    setEnabledRedactionIds((current) => {
      const next = new Set(current)
      if (enabled) next.add(id)
      else next.delete(id)
      return next
    })
  }

  async function exportRedactedPdf() {
    const pdfDoc = pdfRef.current
    if (!activeRun || !pdfDoc || !redactionDetection || savingRedactedPdf) return
    const approved = redactionDetection.boxes.filter((box) => enabledRedactionIds.has(box.id))
    if (approved.length === 0) return
    setError(null)
    setSavingRedactedPdf(true)
    setStatus('Rasterizing affected pages and removing covered glyphs…')
    try {
      const sourceBytes = await fetchPdfBytes(activeRun.sourcePath)
      const redacted = await rasterizeRedactedPdf(pdfDoc, sourceBytes, approved)
      const { saved } = await api.saveRedactedPdf(activeRun.id, redacted)
      setStatus(saved ? `Saved redacted PDF to ${saved}` : 'Redacted PDF export canceled.')
    } catch (e) {
      setError(e instanceof Error ? e.message : String(e))
    } finally {
      setSavingRedactedPdf(false)
    }
  }

  // ---------- render ----------

  const selectedProvider = providers.find((p) => p.id === providerId)
  const canParse =
    !!doc &&
    !parsing &&
    !!selectedProvider &&
    selectedProvider.availability.state === 'ready' &&
    (providerId !== 'ollama' || !!ollamaModel)

  const dirty = activeDocument ? !annotationsEqual(activeDocument.annotations, activeDocument.savedAnnotations) : false

  useEffect(() => {
    const onKeyDown = (event: KeyboardEvent) => {
      const target = event.target as HTMLElement | null
      if (target?.matches('input, textarea, select, [contenteditable="true"]')) return
      if ((event.ctrlKey || event.metaKey) && event.key.toLocaleLowerCase() === 'z') {
        event.preventDefault()
        if (event.shiftKey) redoEditor()
        else undoEditor()
        return
      }
      if ((event.ctrlKey || event.metaKey) && event.key.toLocaleLowerCase() === 'y') {
        event.preventDefault()
        redoEditor()
        return
      }
      if (event.key === 'Delete' || event.key === 'Backspace') {
        if (selectedAnnotationId) event.preventDefault()
        deleteSelectedAnnotation()
        return
      }
      if (event.altKey && event.key === 'ArrowLeft') {
        event.preventDefault()
        moveHistory(-1)
        return
      }
      if (event.altKey && event.key === 'ArrowRight') {
        event.preventDefault()
        moveHistory(1)
        return
      }
      const shortcut: Record<string, AnnotationTool> = {
        v: 'select', t: 'text', h: 'highlight', u: 'underline', k: 'strikeout', d: 'draw',
        l: 'line', r: 'rectangle', e: 'ellipse', i: 'image',
      }
      const tool = shortcut[event.key.toLocaleLowerCase()]
      if (tool) setEditorTool(tool)
    }
    window.addEventListener('keydown', onKeyDown)
    return () => window.removeEventListener('keydown', onKeyDown)
  })

  return (
    <div className="flex h-full flex-col bg-white text-neutral-900">
      <DocumentTabs
        documents={documents.map((document) => ({
          id: document.id,
          fileName: document.fileName,
          dirty: !annotationsEqual(document.annotations, document.savedAnnotations),
        }))}
        activeId={activeId}
        splitId={splitId}
        onActivate={(id) => void activateDocument(id)}
        onClose={closeDocument}
        onOpen={() => void openViaDialog()}
        onSplitChange={setSplitId}
      />
      <Toolbar
        doc={doc}
        page={page}
        zoom={zoom}
        busyOpen={busyOpen}
        viewMode={activeDocument?.viewMode ?? 'single'}
        navigationVisible={navigationVisible}
        canGoBack={!!activeDocument && activeDocument.historyIndex > 0}
        canGoForward={!!activeDocument && activeDocument.historyIndex < activeDocument.history.length - 1}
        onOpen={() => void openViaDialog()}
        onPageChange={setPage}
        onZoomChange={setZoom}
        onViewModeChange={(viewMode) => activeId && patchDocument(activeId, { viewMode })}
        onToggleNavigation={() => setNavigationVisible((visible) => !visible)}
        onGoBack={() => moveHistory(-1)}
        onGoForward={() => moveHistory(1)}
      />
      {activeDocument && (
        <EditorToolbar
          tool={editorTool}
          color={editorColor}
          opacity={editorOpacity}
          lineWidth={editorLineWidth}
          fontSize={editorFontSize}
          canUndo={activeDocument.undo.length > 0}
          canRedo={activeDocument.redo.length > 0}
          dirty={dirty}
          selected={!!selectedAnnotationId}
          onToolChange={setEditorTool}
          onColorChange={setEditorColor}
          onOpacityChange={setEditorOpacity}
          onLineWidthChange={setEditorLineWidth}
          onFontSizeChange={setEditorFontSize}
          onImageChange={(dataUrl) => {
            setEditorImageDataUrl(dataUrl)
            setEditorTool('image')
          }}
          onUndo={undoEditor}
          onRedo={redoEditor}
          onDelete={deleteSelectedAnnotation}
          onSave={() => void saveEditedCopy()}
        />
      )}
      {activeDocument?.recoveryDraft && (
        <div className="flex items-center gap-3 border-b border-amber-300 bg-amber-50 px-3 py-2 text-xs text-amber-900">
          <span className="flex-1">Unsaved edits from {new Date(activeDocument.recoveryDraft.savedAt).toLocaleString()} are available.</span>
          <button onClick={restoreDraft} className="rounded bg-amber-700 px-2 py-1 font-medium text-white">Restore</button>
          <button onClick={discardDraft} className="rounded border border-amber-400 px-2 py-1">Discard</button>
        </div>
      )}
      <div className="flex min-h-0 flex-1">
        {activeDocument && navigationVisible && (
          <NavigationPanel
            pdf={activeDocument.pdf}
            page={page}
            runs={runs}
            activeRunId={activeRun?.id ?? null}
            parsing={parsing}
            searchQuery={searchQuery}
            onSearchQueryChange={setSearchQuery}
            onPageChange={setPage}
            onDestination={(destination) => void followDestination(destination)}
            onViewRun={(run) => void viewRun(run)}
            onResumeRun={(run) => void resumeRun(run)}
          />
        )}
        {activeDocument ? (
          <div className="flex min-w-0 flex-1">
            <DocumentViewer
              pdf={activeDocument.pdf}
              page={page}
              zoom={zoom}
              viewMode={activeDocument.viewMode}
              searchQuery={searchQuery}
              blocksForPage={(pageNumber) => output?.structured?.pages.find((item) => item.pageNumber === pageNumber)?.blocks ?? []}
              redactionsForPage={(pageNumber) => redactionDetection?.boxes.filter((box) => box.page === pageNumber) ?? []}
              showBoxes={showBoxes && tab !== 'redact'}
              showRedactions={showBoxes && tab === 'redact'}
              enabledRedactionIds={enabledRedactionIds}
              selectedBlockId={selectedBlockId}
              hoveredBlockId={hoveredBlockId}
              selectedRedactionId={selectedRedactionId}
              hoveredRedactionId={hoveredRedactionId}
              annotations={activeDocument.annotations}
              editorTool={editorTool}
              selectedAnnotationId={selectedAnnotationId}
              editorColor={editorColor}
              editorOpacity={editorOpacity}
              editorLineWidth={editorLineWidth}
              editorFontSize={editorFontSize}
              editorImageDataUrl={editorImageDataUrl}
              onPageChange={setPage}
              onBlockHover={setHoveredBlockId}
              onBlockSelect={setSelectedBlockId}
              onRedactionHover={setHoveredRedactionId}
              onRedactionSelect={setSelectedRedactionId}
              onAnnotationAdd={(annotation) => updateAnnotations([...activeDocument.annotations, annotation])}
              onAnnotationUpdate={(annotation) => updateAnnotations(activeDocument.annotations.map((item) => item.id === annotation.id ? annotation : item))}
              onAnnotationSelect={setSelectedAnnotationId}
              onDestination={(destination) => void followDestination(destination)}
            />
            {splitDocument && (
              <div className="flex min-w-0 flex-1 border-l-4 border-neutral-400">
                <DocumentViewer
                  pdf={splitDocument.pdf}
                  page={splitDocument.page}
                  zoom={splitDocument.zoom}
                  viewMode={splitDocument.viewMode}
                  searchQuery=""
                  blocksForPage={() => []}
                  redactionsForPage={() => []}
                  showBoxes={false}
                  showRedactions={false}
                  enabledRedactionIds={new Set()}
                  selectedBlockId={null}
                  hoveredBlockId={null}
                  selectedRedactionId={null}
                  hoveredRedactionId={null}
                  annotations={splitDocument.annotations}
                  editorTool="select"
                  selectedAnnotationId={null}
                  editorColor={editorColor}
                  editorOpacity={editorOpacity}
                  editorLineWidth={editorLineWidth}
                  editorFontSize={editorFontSize}
                  editorImageDataUrl={null}
                  readOnly
                  onPageChange={(next) => patchDocument(splitDocument.id, { page: next })}
                  onBlockHover={() => {}}
                  onBlockSelect={() => {}}
                  onRedactionHover={() => {}}
                  onRedactionSelect={() => {}}
                  onAnnotationAdd={() => {}}
                  onAnnotationUpdate={() => {}}
                  onAnnotationSelect={() => {}}
                  onDestination={(destination) => void followDestination(destination, splitDocument)}
                />
              </div>
            )}
          </div>
        ) : (
          <main className="flex min-w-0 flex-1 items-center justify-center bg-neutral-100 p-8 text-center">
            <div>
              <img src="./brand-mark.png" alt="" className="mx-auto h-16 w-16 opacity-80" />
              <h1 className="mt-4 text-xl font-semibold text-neutral-800">Open a PDF to start</h1>
              <p className="mt-2 max-w-md text-sm text-neutral-500">Read, search, compare, annotate, recover edits, and export a modified copy locally.</p>
              <button onClick={() => void openViaDialog()} className="mt-5 rounded-md bg-brand-700 px-4 py-2 text-sm font-medium text-white">Open PDF</button>
            </div>
          </main>
        )}
        {activeDocument && <ExtractPanel
          providers={providers}
          providerId={providerId}
          onProviderChange={(id) => {
            setProviderId(id)
            if (id === 'ollama') refreshOllamaModels()
          }}
          ollamaModels={ollamaModels}
          ollamaModel={ollamaModel}
          onOllamaModelChange={setOllamaModel}
          onRefreshModels={refreshOllamaModels}
          installStatus={installStatus}
          installing={installing}
          onInstall={() => void startInstall(providerId)}
          canParse={canParse}
          parsing={parsing}
          progressCompleted={progressCompleted}
          progressTotal={progressTotal}
          pageStates={pageStates}
          onParse={() => activeDocument && void startParse(undefined, activeDocument)}
          onCancel={cancelParse}
          activeRun={activeRun}
          output={output}
          tab={tab}
          onTabChange={setTab}
          currentPage={page}
          onGotoPage={setPage}
          selectedBlockId={selectedBlockId}
          hoveredBlockId={hoveredBlockId}
          onBlockHover={setHoveredBlockId}
          onBlockSelect={setSelectedBlockId}
          showBoxes={showBoxes}
          onToggleBoxes={setShowBoxes}
          onCopy={() => void copyOutput()}
          onSaveAs={(kind) => void saveOutputAs(kind)}
          onRevealRun={() => void revealActiveRun()}
          presidioStatus={presidioStatus}
          presidioInstallStatus={presidioInstallStatus}
          presidioInstalling={presidioInstalling}
          onInstallPresidio={() => void startPresidioInstall()}
          redactionUseOllama={redactionUseOllama}
          onRedactionUseOllamaChange={setRedactionUseOllama}
          redactionOllamaModel={redactionOllamaModel}
          onRedactionOllamaModelChange={setRedactionOllamaModel}
          redactionDetection={redactionDetection}
          detectingRedactions={detectingRedactions}
          onDetectRedactions={() => void detectPII()}
          enabledRedactionIds={enabledRedactionIds}
          onToggleRedaction={toggleRedaction}
          selectedRedactionId={selectedRedactionId}
          hoveredRedactionId={hoveredRedactionId}
          onRedactionHover={setHoveredRedactionId}
          onRedactionSelect={setSelectedRedactionId}
          savingRedactedPdf={savingRedactedPdf}
          onExportRedactedPdf={() => void exportRedactedPdf()}
        />}
      </div>
      <footer
        className={`border-t px-3 py-1 text-xs ${
          error ? 'border-red-200 bg-red-50 text-red-700' : 'border-neutral-200 bg-neutral-50 text-neutral-500'
        }`}
      >
        {error ?? status}
      </footer>
    </div>
  )
}
