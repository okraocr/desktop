import { useEffect, useRef } from 'react'
import type {
  Block,
  InstallStatus,
  OllamaModel,
  PresidioStatus,
  ProviderStatus,
  RedactionDetection,
  Run,
  RunOutput,
} from '../types'
import { RedactionReview } from './RedactionReview'

type OutputTab = 'markdown' | 'blocks' | 'redact' | 'json'

interface Props {
  providers: ProviderStatus[]
  providerId: string
  onProviderChange: (id: string) => void
  ollamaModels: OllamaModel[]
  ollamaModel: string
  onOllamaModelChange: (name: string) => void
  onRefreshModels: () => void
  installStatus: InstallStatus | null
  installing: boolean
  onInstall: () => void
  canParse: boolean
  parsing: boolean
  progressCompleted: number
  progressTotal: number
  pageStates: Record<number, string>
  onParse: () => void
  onCancel: () => void
  activeRun: Run | null
  output: RunOutput | null
  tab: OutputTab
  onTabChange: (tab: OutputTab) => void
  currentPage: number
  onGotoPage: (page: number) => void
  selectedBlockId: string | null
  hoveredBlockId: string | null
  onBlockHover: (id: string | null) => void
  onBlockSelect: (id: string) => void
  showBoxes: boolean
  onToggleBoxes: (show: boolean) => void
  onCopy: () => void
  onSaveAs: (kind: 'markdown' | 'json') => void
  onRevealRun: () => void
  presidioStatus: PresidioStatus | null
  presidioInstallStatus: InstallStatus | null
  presidioInstalling: boolean
  onInstallPresidio: () => void
  redactionUseOllama: boolean
  onRedactionUseOllamaChange: (enabled: boolean) => void
  redactionOllamaModel: string
  onRedactionOllamaModelChange: (model: string) => void
  redactionDetection: RedactionDetection | null
  detectingRedactions: boolean
  onDetectRedactions: () => void
  enabledRedactionIds: Set<string>
  onToggleRedaction: (id: string, enabled: boolean) => void
  selectedRedactionId: string | null
  hoveredRedactionId: string | null
  onRedactionHover: (id: string | null) => void
  onRedactionSelect: (id: string) => void
  savingRedactedPdf: boolean
  onExportRedactedPdf: () => void
}

const PAGE_STATE_STYLE: Record<string, string> = {
  idle: 'bg-neutral-200 text-neutral-500',
  running: 'bg-sky-100 text-sky-700 animate-pulse',
  succeeded: 'bg-brand-100 text-brand-700',
  failed: 'bg-red-100 text-red-700',
  canceled: 'bg-amber-100 text-amber-700',
}

export function ExtractPanel(props: Props) {
  const {
    providers,
    providerId,
    onProviderChange,
    ollamaModels,
    ollamaModel,
    onOllamaModelChange,
    onRefreshModels,
    installStatus,
    installing,
    onInstall,
    canParse,
    parsing,
    progressCompleted,
    progressTotal,
    pageStates,
    onParse,
    onCancel,
    activeRun,
    output,
    tab,
    onTabChange,
    currentPage,
    onGotoPage,
    selectedBlockId,
    hoveredBlockId,
    onBlockHover,
    onBlockSelect,
    showBoxes,
    onToggleBoxes,
    onCopy,
    onSaveAs,
    onRevealRun,
    presidioStatus,
    presidioInstallStatus,
    presidioInstalling,
    onInstallPresidio,
    redactionUseOllama,
    onRedactionUseOllamaChange,
    redactionOllamaModel,
    onRedactionOllamaModelChange,
    redactionDetection,
    detectingRedactions,
    onDetectRedactions,
    enabledRedactionIds,
    onToggleRedaction,
    selectedRedactionId,
    hoveredRedactionId,
    onRedactionHover,
    onRedactionSelect,
    savingRedactedPdf,
    onExportRedactedPdf,
  } = props

  const selectedProvider = providers.find((p) => p.id === providerId)
  const blocks: Block[] =
    output?.structured?.pages.find((p) => p.pageNumber === currentPage)?.blocks ?? []
  const allBlocks: Block[] = output?.structured?.pages.flatMap((p) => p.blocks) ?? []
  const fraction = progressTotal > 0 ? progressCompleted / progressTotal : 0

  const listRef = useRef<HTMLDivElement>(null)
  useEffect(() => {
    if (!selectedBlockId || !listRef.current) return
    const el = listRef.current.querySelector(`[data-block-id="${CSS.escape(selectedBlockId)}"]`)
    el?.scrollIntoView({ block: 'nearest' })
  }, [selectedBlockId])

  return (
    <aside className="flex w-96 shrink-0 flex-col border-l border-neutral-200 bg-white">
      <div className="border-b border-neutral-200 px-3 py-2">
        <div className="text-xs font-semibold uppercase tracking-wide text-neutral-500">Extract</div>
        <div className="mt-2 flex items-center gap-2">
          <select
            className="min-w-0 flex-1 rounded-md border border-neutral-300 px-2 py-1.5 text-sm"
            value={providerId}
            disabled={parsing}
            onChange={(e) => onProviderChange(e.target.value)}
          >
            {providers.map((provider) => (
              <option key={provider.id} value={provider.id}>
                {provider.name}
              </option>
            ))}
          </select>
          {providerId === 'ollama' && (
            <button
              className="rounded-md border border-neutral-300 px-2 py-1.5 text-xs hover:bg-neutral-50"
              onClick={onRefreshModels}
              title="Refresh Ollama models"
            >
              ⟳
            </button>
          )}
        </div>
        {selectedProvider && (
          <div className="mt-1 text-xs text-neutral-500">{selectedProvider.summary}</div>
        )}
        {selectedProvider && (
          <div
            className={`mt-1 text-xs ${
              selectedProvider.availability.state === 'ready' ? 'text-brand-700' : 'text-amber-700'
            }`}
          >
            {selectedProvider.availability.message}
          </div>
        )}
        {selectedProvider?.availability.state === 'setupRequired' && (
          <div className="mt-2 rounded-md border border-amber-200 bg-amber-50 p-2">
            {selectedProvider.setupNote && (
              <div className="text-xs text-neutral-600">{selectedProvider.setupNote}</div>
            )}
            {installing && installStatus ? (
              <div className="mt-2">
                <div className="text-xs font-medium text-amber-800">
                  {installStatus.message || 'Setting up…'}
                </div>
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
              <>
                {installStatus?.phase === 'error' && (
                  <div className="mt-2 text-xs text-red-700">{installStatus.message}</div>
                )}
                <button
                  onClick={onInstall}
                  disabled={parsing}
                  className="mt-2 w-full rounded-md bg-amber-600 px-3 py-1.5 text-sm font-medium text-white hover:bg-amber-700 disabled:opacity-50"
                >
                  {installStatus?.phase === 'error' ? 'Retry setup' : 'Set up'}
                </button>
              </>
            )}
          </div>
        )}
        {providerId === 'ollama' && (
          <select
            className="mt-2 w-full rounded-md border border-neutral-300 px-2 py-1.5 text-sm"
            value={ollamaModel}
            disabled={parsing}
            onChange={(e) => onOllamaModelChange(e.target.value)}
          >
            <option value="">Choose an Ollama model…</option>
            {ollamaModels.map((model) => (
              <option key={model.name} value={model.name}>
                {model.name}
                {model.supportsVision ? ' (vision)' : ''}
              </option>
            ))}
          </select>
        )}
        <div className="mt-3 flex items-center gap-2">
          {parsing ? (
            <button
              onClick={onCancel}
              className="flex-1 rounded-md bg-amber-600 px-3 py-1.5 text-sm font-medium text-white hover:bg-amber-700"
            >
              Cancel
            </button>
          ) : (
            <button
              onClick={onParse}
              disabled={!canParse}
              className="flex-1 rounded-md bg-brand-700 px-3 py-1.5 text-sm font-medium text-white hover:bg-brand-800 disabled:opacity-50"
            >
              Parse
            </button>
          )}
        </div>
        {(parsing || progressCompleted > 0) && progressTotal > 0 && (
          <div className="mt-2">
            <div className="flex justify-between text-xs text-neutral-500">
              <span>
                {progressCompleted} of {progressTotal} pages
              </span>
              <span>{Math.round(fraction * 100)}%</span>
            </div>
            <div className="mt-1 h-1.5 overflow-hidden rounded-full bg-neutral-200">
              <div
                className="h-full rounded-full bg-brand-600 transition-all"
                style={{ width: `${fraction * 100}%` }}
              />
            </div>
            <div className="mt-2 flex flex-wrap gap-1">
              {Array.from({ length: progressTotal }, (_, i) => i + 1).map((pageNumber) => (
                <button
                  key={pageNumber}
                  onClick={() => onGotoPage(pageNumber)}
                  title={`Page ${pageNumber}: ${pageStates[pageNumber] ?? 'idle'}`}
                  className={`h-5 min-w-5 rounded px-1 text-[10px] ${PAGE_STATE_STYLE[pageStates[pageNumber] ?? 'idle']}`}
                >
                  {pageNumber}
                </button>
              ))}
            </div>
          </div>
        )}
      </div>

      <div className="flex min-h-0 flex-1 flex-col">
        <div className="flex items-center gap-1 border-b border-neutral-200 px-2 pt-2">
          {(['markdown', 'blocks', 'redact', 'json'] as OutputTab[]).map((name) => (
            <button
              key={name}
              onClick={() => onTabChange(name)}
              className={`rounded-t-md px-3 py-1.5 text-xs font-medium capitalize ${
                tab === name
                  ? 'border border-b-0 border-neutral-200 bg-white text-brand-800'
                  : 'text-neutral-500 hover:text-neutral-700'
              }`}
            >
              {name === 'json' ? 'JSON' : name}
            </button>
          ))}
          <label className="ml-auto flex items-center gap-1 pb-1 text-xs text-neutral-500">
            <input
              type="checkbox"
              checked={showBoxes}
              onChange={(e) => onToggleBoxes(e.target.checked)}
            />
            Boxes
          </label>
        </div>

        <div ref={listRef} className="thin-scroll min-h-0 flex-1 overflow-y-auto p-3">
          {!output && (
            <div className="mt-8 text-center text-xs text-neutral-400">
              Extracted output appears here after a run finishes.
            </div>
          )}
          {output && tab === 'markdown' && (
            <pre className="whitespace-pre-wrap font-mono text-xs leading-relaxed text-neutral-800">
              {output.markdown || '(no Markdown output)'}
            </pre>
          )}
          {output && tab === 'json' && (
            <pre className="whitespace-pre-wrap font-mono text-[11px] leading-relaxed text-neutral-700">
              {JSON.stringify(output.structured ?? {}, null, 2)}
            </pre>
          )}
          {output && tab === 'blocks' && (
            <div className="space-y-1">
              {allBlocks.length === 0 && (
                <div className="mt-4 text-center text-xs text-neutral-400">
                  This run produced no positioned blocks (the Ollama parser returns Markdown only).
                </div>
              )}
              {allBlocks.map((block) => (
                <button
                  key={block.id}
                  data-block-id={block.id}
                  onMouseEnter={() => onBlockHover(block.id)}
                  onMouseLeave={() => onBlockHover(null)}
                  onClick={() => {
                    onBlockSelect(block.id)
                    const pageNumber = Number(block.id.split('-')[1])
                    if (Number.isInteger(pageNumber)) onGotoPage(pageNumber)
                  }}
                  className={`w-full rounded-md border px-2 py-1.5 text-left text-xs ${
                    block.id === selectedBlockId
                      ? 'border-brand-600 bg-brand-50'
                      : block.id === hoveredBlockId
                        ? 'border-amber-400 bg-amber-50'
                        : 'border-neutral-200 hover:border-neutral-300'
                  }`}
                >
                  <div className="flex justify-between text-[10px] uppercase tracking-wide text-neutral-400">
                    <span>{block.sourceType}</span>
                    {block.bbox && (
                      <span>
                        {Math.round(block.bbox.x * 100)}%,{Math.round(block.bbox.y * 100)}%
                      </span>
                    )}
                  </div>
                  <div className="mt-0.5 line-clamp-3 text-neutral-800">{block.text}</div>
                </button>
              ))}
              {blocks.length > 0 && (
                <div className="pt-1 text-center text-[10px] text-neutral-400">
                  {blocks.length} blocks on page {currentPage}
                </div>
              )}
            </div>
          )}
          {output && tab === 'redact' && activeRun && (
            <RedactionReview
              presidioStatus={presidioStatus}
              installStatus={presidioInstallStatus}
              installing={presidioInstalling}
              onInstall={onInstallPresidio}
              ollamaModels={ollamaModels}
              useOllama={redactionUseOllama}
              onUseOllamaChange={onRedactionUseOllamaChange}
              ollamaModel={redactionOllamaModel}
              onOllamaModelChange={onRedactionOllamaModelChange}
              onRefreshModels={onRefreshModels}
              hasPositionedBlocks={allBlocks.some((block) => !!block.bbox)}
              detection={redactionDetection}
              detecting={detectingRedactions}
              onDetect={onDetectRedactions}
              enabledIds={enabledRedactionIds}
              onToggle={onToggleRedaction}
              selectedId={selectedRedactionId}
              hoveredId={hoveredRedactionId}
              onHover={onRedactionHover}
              onSelect={onRedactionSelect}
              onGotoPage={onGotoPage}
              saving={savingRedactedPdf}
              onExport={onExportRedactedPdf}
            />
          )}
        </div>

        {output && activeRun && (
          <div className="flex items-center gap-2 border-t border-neutral-200 px-3 py-2">
            {tab !== 'redact' && (
              <>
                <button
                  onClick={onCopy}
                  className="rounded-md border border-neutral-300 px-2 py-1 text-xs hover:bg-neutral-50"
                >
                  Copy
                </button>
                <button
                  onClick={() => onSaveAs(tab === 'json' ? 'json' : 'markdown')}
                  className="rounded-md border border-neutral-300 px-2 py-1 text-xs hover:bg-neutral-50"
                >
                  Save as…
                </button>
              </>
            )}
            <button
              onClick={onRevealRun}
              className="rounded-md border border-neutral-300 px-2 py-1 text-xs hover:bg-neutral-50"
            >
              Reveal
            </button>
            <span className="ml-auto text-[10px] text-neutral-400">
              {activeRun.providerName} · {activeRun.completedPageCount ?? 0}/{activeRun.pageCount} pages
            </span>
          </div>
        )}
      </div>
    </aside>
  )
}
