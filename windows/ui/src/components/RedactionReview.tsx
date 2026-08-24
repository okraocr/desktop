import { useEffect, useRef } from 'react'
import type {
  InstallStatus,
  OllamaModel,
  PresidioStatus,
  RedactionDetection,
} from '../types'

interface Props {
  presidioStatus: PresidioStatus | null
  installStatus: InstallStatus | null
  installing: boolean
  onInstall: () => void
  ollamaModels: OllamaModel[]
  useOllama: boolean
  onUseOllamaChange: (enabled: boolean) => void
  ollamaModel: string
  onOllamaModelChange: (model: string) => void
  onRefreshModels: () => void
  hasPositionedBlocks: boolean
  detection: RedactionDetection | null
  detecting: boolean
  onDetect: () => void
  enabledIds: Set<string>
  onToggle: (id: string, enabled: boolean) => void
  selectedId: string | null
  hoveredId: string | null
  onHover: (id: string | null) => void
  onSelect: (id: string) => void
  onGotoPage: (page: number) => void
  saving: boolean
  onExport: () => void
}

export function RedactionReview(props: Props) {
  const {
    presidioStatus,
    installStatus,
    installing,
    onInstall,
    ollamaModels,
    useOllama,
    onUseOllamaChange,
    ollamaModel,
    onOllamaModelChange,
    onRefreshModels,
    hasPositionedBlocks,
    detection,
    detecting,
    onDetect,
    enabledIds,
    onToggle,
    selectedId,
    hoveredId,
    onHover,
    onSelect,
    onGotoPage,
    saving,
    onExport,
  } = props
  const selectedRef = useRef<HTMLDivElement>(null)

  useEffect(() => {
    selectedRef.current?.scrollIntoView({ block: 'nearest' })
  }, [selectedId])

  const availability = presidioStatus?.availability
  const canDetect =
    hasPositionedBlocks &&
    availability?.state === 'ready' &&
    !detecting &&
    (!useOllama || !!ollamaModel)
  const approvedCount = detection?.boxes.filter((box) => enabledIds.has(box.id)).length ?? 0

  return (
    <div className="space-y-3">
      <div className="rounded-md border border-neutral-200 bg-neutral-50 p-2 text-xs text-neutral-600">
        Presidio flags PII in local extraction blocks. Review every candidate before export; the source PDF is never changed.
      </div>

      {availability?.state === 'setupRequired' && (
        <div className="rounded-md border border-amber-200 bg-amber-50 p-2">
          <div className="text-xs font-medium text-amber-900">Microsoft Presidio setup</div>
          <div className="mt-1 text-xs text-neutral-600">{availability.message}</div>
          {installing && installStatus ? (
            <div className="mt-2">
              <div className="text-xs text-amber-800">{installStatus.message}</div>
              <div className="mt-1 h-1.5 overflow-hidden rounded-full bg-amber-100">
                <div className="h-full w-full animate-pulse rounded-full bg-amber-500" />
              </div>
              {installStatus.logTail && installStatus.logTail.length > 0 && (
                <pre className="mt-1 max-h-20 overflow-y-auto whitespace-pre-wrap font-mono text-[10px] text-neutral-500">
                  {installStatus.logTail.join('\n')}
                </pre>
              )}
            </div>
          ) : (
            <button
              type="button"
              onClick={onInstall}
              className="mt-2 w-full rounded-md bg-amber-600 px-3 py-1.5 text-sm font-medium text-white hover:bg-amber-700"
            >
              {installStatus?.phase === 'error' ? 'Retry setup' : 'Set up locally'}
            </button>
          )}
        </div>
      )}

      {availability?.state === 'unavailable' && (
        <div className="rounded-md border border-red-200 bg-red-50 p-2 text-xs text-red-700">
          {availability.message}
        </div>
      )}

      {availability?.state === 'ready' && (
        <div className="rounded-md border border-brand-200 bg-brand-50 p-2 text-xs text-brand-800">
          Presidio {presidioStatus?.running ? 'is running on loopback.' : 'is ready locally.'}
        </div>
      )}

      {presidioStatus?.ollamaSupported && (
        <div className="rounded-md border border-neutral-200 p-2">
          <label className="flex items-start gap-2 text-xs text-neutral-700">
            <input
              type="checkbox"
              checked={useOllama}
              onChange={(event) => onUseOllamaChange(event.target.checked)}
            />
            <span>
              Add Presidio’s Ollama recognizer
              <span className="block text-[10px] text-neutral-500">Experimental; slower, but can improve names and contextual PII.</span>
            </span>
          </label>
          {useOllama && (
            <div className="mt-2 flex gap-1">
              <select
                value={ollamaModel}
                onChange={(event) => onOllamaModelChange(event.target.value)}
                className="min-w-0 flex-1 rounded-md border border-neutral-300 px-2 py-1.5 text-xs"
              >
                <option value="">Choose a local text model…</option>
                {ollamaModels.map((model) => (
                  <option key={model.name} value={model.name}>{model.name}</option>
                ))}
              </select>
              <button
                type="button"
                onClick={onRefreshModels}
                title="Refresh Ollama models"
                className="rounded-md border border-neutral-300 px-2 text-xs hover:bg-neutral-50"
              >
                ⟳
              </button>
            </div>
          )}
        </div>
      )}

      {!hasPositionedBlocks && (
        <div className="rounded-md border border-amber-200 bg-amber-50 p-2 text-xs text-amber-800">
          This run has no positioned blocks. Parse with Windows OCR or Chandra before detecting redaction boxes.
        </div>
      )}

      <button
        type="button"
        onClick={onDetect}
        disabled={!canDetect}
        className="w-full rounded-md bg-brand-700 px-3 py-1.5 text-sm font-medium text-white hover:bg-brand-800 disabled:opacity-50"
      >
        {detecting ? 'Detecting PII…' : detection ? 'Detect again' : 'Detect PII'}
      </button>

      {detection && (
        <>
          <div className="flex items-center justify-between text-xs text-neutral-500">
            <span>{detection.stats.total} candidates</span>
            <span>{approvedCount} approved</span>
          </div>
          <div className="space-y-1">
            {detection.boxes.length === 0 && (
              <div className="rounded-md border border-neutral-200 p-3 text-center text-xs text-neutral-400">
                Presidio found no PII above the confidence threshold.
              </div>
            )}
            {detection.boxes.map((box) => {
              const active = enabledIds.has(box.id)
              return (
                <div
                  key={box.id}
                  ref={box.id === selectedId ? selectedRef : undefined}
                  onMouseEnter={() => onHover(box.id)}
                  onMouseLeave={() => onHover(null)}
                  className={`rounded-md border p-2 text-xs ${
                    box.id === selectedId || box.id === hoveredId
                      ? 'border-amber-400 bg-amber-50'
                      : active
                        ? 'border-neutral-300 bg-white'
                        : 'border-neutral-200 bg-neutral-50 opacity-60'
                  }`}
                >
                  <div className="flex items-start gap-2">
                    <input
                      type="checkbox"
                      checked={active}
                      onChange={(event) => onToggle(box.id, event.target.checked)}
                      aria-label={`Approve ${box.type} redaction`}
                    />
                    <button
                      type="button"
                      onClick={() => {
                        onSelect(box.id)
                        onGotoPage(box.page)
                      }}
                      className="min-w-0 flex-1 text-left"
                    >
                      <div className="flex justify-between text-[10px] font-medium uppercase tracking-wide text-neutral-500">
                        <span>{box.type}</span>
                        <span>p. {box.page} · {Math.round(box.score * 100)}%</span>
                      </div>
                      <div className="mt-0.5 truncate text-neutral-800">{box.text}</div>
                      <div className="mt-0.5 text-[10px] text-neutral-400">{box.source}</div>
                    </button>
                  </div>
                </div>
              )
            })}
          </div>
          <div className="rounded-md border border-neutral-200 bg-neutral-50 p-2 text-[10px] leading-relaxed text-neutral-500">
            Export rasterizes each affected page before drawing approved black boxes. This removes hidden text but turns affected pages into images.
          </div>
          <button
            type="button"
            onClick={onExport}
            disabled={approvedCount === 0 || saving}
            className="w-full rounded-md bg-neutral-900 px-3 py-1.5 text-sm font-medium text-white hover:bg-black disabled:opacity-50"
          >
            {saving ? 'Building redacted PDF…' : 'Export redacted PDF…'}
          </button>
        </>
      )}
    </div>
  )
}
