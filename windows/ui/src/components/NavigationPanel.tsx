import { useEffect, useMemo, useRef, useState, type ReactNode } from 'react'
import type { PdfDocument } from '../pdf'
import type { Run } from '../types'
import { searchDocument } from '../document-model'

type NavigationTab = 'pages' | 'outline' | 'search' | 'runs'

interface OutlineItem {
  title: string
  dest?: unknown
  items?: OutlineItem[]
}

interface Props {
  pdf: PdfDocument
  page: number
  runs: Run[]
  activeRunId: string | null
  parsing: boolean
  searchQuery: string
  onSearchQueryChange: (query: string) => void
  onPageChange: (page: number) => void
  onDestination: (destination: unknown) => void
  onViewRun: (run: Run) => void
  onResumeRun: (run: Run) => void
}

export function NavigationPanel(props: Props) {
  const [tab, setTab] = useState<NavigationTab>('pages')
  const [outline, setOutline] = useState<OutlineItem[] | null>(null)
  const [pageText, setPageText] = useState<string[]>([])
  const [indexing, setIndexing] = useState(false)

  useEffect(() => {
    let cancelled = false
    void props.pdf.getOutline()
      .then((value) => {
        if (!cancelled) setOutline(value as OutlineItem[] | null)
      })
      .catch(() => {
        if (!cancelled) setOutline(null)
      })
    return () => { cancelled = true }
  }, [props.pdf])

  useEffect(() => {
    setPageText([])
    setIndexing(false)
  }, [props.pdf])

  useEffect(() => {
    if (tab !== 'search' || pageText.length === props.pdf.numPages) return
    let cancelled = false
    setIndexing(true)
    void (async () => {
      try {
        const text: string[] = []
        for (let pageNumber = 1; pageNumber <= props.pdf.numPages; pageNumber++) {
          const page = await props.pdf.getPage(pageNumber)
          const content = await page.getTextContent()
          text.push(content.items.flatMap((item) => ('str' in item ? [item.str] : [])).join(' '))
          if (cancelled) return
        }
        if (!cancelled) setPageText(text)
      } finally {
        if (!cancelled) setIndexing(false)
      }
    })()
    return () => { cancelled = true }
  }, [pageText.length, props.pdf, tab])

  const results = useMemo(() => searchDocument(pageText, props.searchQuery), [pageText, props.searchQuery])
  return (
    <aside className="flex w-60 shrink-0 flex-col border-r border-neutral-200 bg-neutral-50">
      <div className="grid grid-cols-4 border-b border-neutral-200">
        {(['pages', 'outline', 'search', 'runs'] as NavigationTab[]).map((name) => (
          <button
            key={name}
            onClick={() => setTab(name)}
            className={`px-1 py-2 text-[10px] font-semibold uppercase ${tab === name ? 'border-b-2 border-brand-600 bg-white text-brand-700' : 'text-neutral-500 hover:bg-white'}`}
          >
            {name}
          </button>
        ))}
      </div>
      <div className="thin-scroll min-h-0 flex-1 overflow-y-auto p-2">
        {tab === 'pages' && (
          <div className="grid grid-cols-2 gap-2">
            {Array.from({ length: props.pdf.numPages }, (_, index) => index + 1).map((pageNumber) => (
              <Thumbnail key={pageNumber} pdf={props.pdf} page={pageNumber} selected={pageNumber === props.page} onClick={() => props.onPageChange(pageNumber)} />
            ))}
          </div>
        )}
        {tab === 'outline' && (
          outline?.length
            ? <OutlineList items={outline} depth={0} onDestination={props.onDestination} />
            : <Empty>No document outline.</Empty>
        )}
        {tab === 'search' && (
          <div>
            <input
              autoFocus
              value={props.searchQuery}
              onChange={(event) => props.onSearchQueryChange(event.target.value)}
              placeholder="Search this PDF"
              className="w-full rounded border border-neutral-300 bg-white px-2 py-1.5 text-xs"
            />
            <div className="mt-2 text-[10px] text-neutral-400">
              {indexing ? 'Indexing document…' : props.searchQuery ? `${results.reduce((sum, result) => sum + result.count, 0)} matches` : 'Type to search all pages.'}
            </div>
            <div className="mt-1 space-y-1">
              {results.map((result) => (
                <button key={result.page} onClick={() => props.onPageChange(result.page)} className="w-full rounded border border-neutral-200 bg-white p-2 text-left hover:border-brand-300">
                  <div className="text-[10px] font-semibold text-brand-700">Page {result.page} · {result.count}</div>
                  <div className="mt-0.5 line-clamp-3 text-[11px] text-neutral-600">{result.snippet}</div>
                </button>
              ))}
            </div>
          </div>
        )}
        {tab === 'runs' && (
          <RunList runs={props.runs} activeRunId={props.activeRunId} parsing={props.parsing} onViewRun={props.onViewRun} onResumeRun={props.onResumeRun} />
        )}
      </div>
    </aside>
  )
}

function Thumbnail({ pdf, page, selected, onClick }: { pdf: PdfDocument; page: number; selected: boolean; onClick: () => void }) {
  const canvas = useRef<HTMLCanvasElement>(null)
  useEffect(() => {
    let cancelled = false
    void (async () => {
      const pdfPage = await pdf.getPage(page)
      if (cancelled || !canvas.current) return
      const base = pdfPage.getViewport({ scale: 1 })
      const viewport = pdfPage.getViewport({ scale: 104 / base.width })
      const context = canvas.current.getContext('2d')
      if (!context) return
      canvas.current.width = Math.ceil(viewport.width)
      canvas.current.height = Math.ceil(viewport.height)
      await pdfPage.render({ canvas: canvas.current, canvasContext: context, viewport }).promise
    })()
    return () => { cancelled = true }
  }, [page, pdf])
  return (
    <button onClick={onClick} className={`rounded border bg-white p-1 text-center ${selected ? 'border-brand-600 ring-1 ring-brand-500' : 'border-neutral-200 hover:border-neutral-400'}`}>
      <canvas ref={canvas} className="mx-auto max-w-full" />
      <span className="text-[10px] text-neutral-500">{page}</span>
    </button>
  )
}

function OutlineList({ items, depth, onDestination }: { items: OutlineItem[]; depth: number; onDestination: (destination: unknown) => void }) {
  return (
    <ul className="space-y-0.5">
      {items.map((item, index) => (
        <li key={`${depth}-${index}-${item.title}`}>
          <button onClick={() => item.dest && onDestination(item.dest)} className="w-full truncate rounded px-2 py-1 text-left text-xs text-neutral-700 hover:bg-brand-50" style={{ paddingLeft: `${8 + depth * 12}px` }} title={item.title}>
            {item.title || '(untitled)'}
          </button>
          {item.items && item.items.length > 0 && <OutlineList items={item.items} depth={depth + 1} onDestination={onDestination} />}
        </li>
      ))}
    </ul>
  )
}

const RESUMABLE = new Set(['canceled', 'failed', 'interrupted'])

function RunList({ runs, activeRunId, parsing, onViewRun, onResumeRun }: { runs: Run[]; activeRunId: string | null; parsing: boolean; onViewRun: (run: Run) => void; onResumeRun: (run: Run) => void }) {
  if (runs.length === 0) return <Empty>No extraction runs yet.</Empty>
  return (
    <ul className="space-y-1">
      {runs.map((run) => (
        <li key={run.id} className={`rounded border bg-white p-2 ${run.id === activeRunId ? 'border-brand-500' : 'border-neutral-200'}`}>
          <button onClick={() => onViewRun(run)} className="w-full text-left">
            <div className="text-xs font-medium text-neutral-800">{run.providerName}</div>
            <div className="text-[10px] text-neutral-500">{run.status} · {run.completedPageCount ?? 0}/{run.pageCount}</div>
          </button>
          {RESUMABLE.has(run.status) && !parsing && <button onClick={() => onResumeRun(run)} className="mt-1 text-[10px] text-brand-700 hover:underline">Resume</button>}
        </li>
      ))}
    </ul>
  )
}

function Empty({ children }: { children: ReactNode }) {
  return <div className="mt-6 text-center text-xs text-neutral-400">{children}</div>
}
