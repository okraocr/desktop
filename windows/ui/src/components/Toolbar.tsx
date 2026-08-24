import type { CurrentDocument } from '../types'
import type { ViewMode } from '../editor'

interface Props {
  doc: CurrentDocument | null
  page: number
  zoom: number
  busyOpen: boolean
  viewMode: ViewMode
  navigationVisible: boolean
  canGoBack: boolean
  canGoForward: boolean
  onOpen: () => void
  onPageChange: (page: number) => void
  onZoomChange: (zoom: number) => void
  onViewModeChange: (mode: ViewMode) => void
  onToggleNavigation: () => void
  onGoBack: () => void
  onGoForward: () => void
}

export function Toolbar(props: Props) {
  const { doc, page, zoom, busyOpen, onOpen, onPageChange, onZoomChange } = props
  const pageCount = doc?.pageCount ?? 0
  return (
    <header className="flex items-center gap-3 border-b border-neutral-200 bg-white px-3 py-2">
      <button
        onClick={onOpen}
        disabled={busyOpen}
        className="rounded-md bg-brand-700 px-3 py-1.5 text-sm font-medium text-white hover:bg-brand-800 disabled:opacity-50"
      >
        {busyOpen ? 'Opening…' : 'Open PDF'}
      </button>
      <div className="min-w-0 flex-1">
        <div className="truncate text-sm font-medium text-neutral-800">
          {doc ? doc.fileName : 'okraPDF'}
        </div>
        <div className="truncate text-xs text-neutral-500">
          {doc ? doc.path : 'Read and parse PDFs privately on your PC'}
        </div>
      </div>
      {doc && (
        <div className="flex items-center gap-1 text-sm text-neutral-700">
          <button
            className={`rounded px-2 py-1 text-xs hover:bg-neutral-100 ${props.navigationVisible ? 'bg-neutral-100 text-brand-700' : ''}`}
            onClick={props.onToggleNavigation}
            title="Toggle navigation panel"
          >
            Navigate
          </button>
          <button className="rounded px-1.5 py-1 hover:bg-neutral-100 disabled:opacity-40" disabled={!props.canGoBack} onClick={props.onGoBack} title="Previous location">↶</button>
          <button className="rounded px-1.5 py-1 hover:bg-neutral-100 disabled:opacity-40" disabled={!props.canGoForward} onClick={props.onGoForward} title="Next location">↷</button>
          <button
            className="rounded px-2 py-1 hover:bg-neutral-100 disabled:opacity-40"
            disabled={page <= 1}
            onClick={() => onPageChange(page - 1)}
            aria-label="Previous page"
          >
            ‹
          </button>
          <input
            className="w-10 rounded border border-neutral-300 px-1 py-0.5 text-center text-xs"
            value={page}
            onChange={(e) => {
              const next = Number(e.target.value)
              if (Number.isInteger(next) && next >= 1 && next <= pageCount) onPageChange(next)
            }}
          />
          <span className="text-xs text-neutral-500">/ {pageCount}</span>
          <button
            className="rounded px-2 py-1 hover:bg-neutral-100 disabled:opacity-40"
            disabled={page >= pageCount}
            onClick={() => onPageChange(page + 1)}
            aria-label="Next page"
          >
            ›
          </button>
          <span className="mx-1 h-4 w-px bg-neutral-200" />
          <button
            className="rounded px-2 py-1 text-xs hover:bg-neutral-100"
            onClick={() => onZoomChange(Math.max(0.5, zoom - 0.25))}
          >
            −
          </button>
          <button
            className="w-12 rounded px-1 py-1 text-center text-xs hover:bg-neutral-100"
            onClick={() => onZoomChange(1.25)}
            title="Reset zoom"
          >
            {Math.round(zoom * 100)}%
          </button>
          <button
            className="rounded px-2 py-1 text-xs hover:bg-neutral-100"
            onClick={() => onZoomChange(Math.min(3, zoom + 0.25))}
          >
            +
          </button>
          <select
            value={props.viewMode}
            onChange={(event) => props.onViewModeChange(event.target.value as ViewMode)}
            className="ml-1 rounded border border-neutral-300 bg-white px-1.5 py-1 text-xs"
            title="Page layout"
          >
            <option value="single">Single page</option>
            <option value="continuous">Continuous</option>
            <option value="two-page">Two page</option>
            <option value="book">Book</option>
            <option value="grid">Grid</option>
          </select>
        </div>
      )}
      <div className="flex items-center gap-2">
        <img src="./brand-mark.png" alt="okraPDF" className="h-6 w-6" />
        <span className="text-sm font-semibold text-brand-800">okraPDF</span>
      </div>
    </header>
  )
}
