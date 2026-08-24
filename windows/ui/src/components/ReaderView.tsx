import { useEffect, useRef } from 'react'
import type { Block, RedactionBox } from '../types'
import type { PdfDocument } from '../pdf'
import { renderPageToCanvas } from '../pdf'
import { BoxOverlay } from './BoxOverlay'
import { RedactionOverlay } from './RedactionOverlay'

interface Props {
  pdf: PdfDocument | null
  page: number
  zoom: number
  blocks: Block[]
  showBoxes: boolean
  selectedBlockId: string | null
  hoveredBlockId: string | null
  onBlockHover: (id: string | null) => void
  onBlockSelect: (id: string) => void
  redactions: RedactionBox[]
  showRedactions: boolean
  enabledRedactionIds: Set<string>
  selectedRedactionId: string | null
  hoveredRedactionId: string | null
  onRedactionHover: (id: string | null) => void
  onRedactionSelect: (id: string) => void
  onOpen: () => void
}

export function ReaderView({
  pdf,
  page,
  zoom,
  blocks,
  showBoxes,
  selectedBlockId,
  hoveredBlockId,
  onBlockHover,
  onBlockSelect,
  redactions,
  showRedactions,
  enabledRedactionIds,
  selectedRedactionId,
  hoveredRedactionId,
  onRedactionHover,
  onRedactionSelect,
  onOpen,
}: Props) {
  const canvasRef = useRef<HTMLCanvasElement>(null)

  useEffect(() => {
    let cancelled = false
    if (pdf && canvasRef.current) {
      pdf
        .getPage(page)
        .then((pdfPage) => {
          if (!cancelled && canvasRef.current) {
            return renderPageToCanvas(pdfPage, canvasRef.current, zoom)
          }
        })
        .catch(() => {})
    }
    return () => {
      cancelled = true
    }
  }, [pdf, page, zoom])

  if (!pdf) {
    return (
      <main className="flex flex-1 items-center justify-center bg-neutral-200">
        <button
          onClick={onOpen}
          className="flex h-56 w-96 flex-col items-center justify-center gap-3 rounded-xl border-2 border-dashed border-neutral-400 bg-white/60 text-neutral-600 transition-colors hover:border-brand-600 hover:text-brand-700"
        >
          <img src="./brand-mark.png" alt="okraPDF" className="h-16 w-16" />
          <span className="text-sm font-medium">Open a PDF to read it in place</span>
          <span className="text-xs text-neutral-500">Nothing is uploaded or parsed until you choose Parse.</span>
        </button>
      </main>
    )
  }

  return (
    <main className="thin-scroll flex-1 overflow-auto bg-neutral-200 p-6">
      <div className="mx-auto w-fit">
        <div className="relative bg-white shadow-lg">
          <canvas ref={canvasRef} className="block" />
          {showBoxes && (
            <BoxOverlay
              blocks={blocks}
              selectedId={selectedBlockId}
              hoveredId={hoveredBlockId}
              onHover={onBlockHover}
              onSelect={onBlockSelect}
            />
          )}
          {showRedactions && (
            <RedactionOverlay
              boxes={redactions}
              enabledIds={enabledRedactionIds}
              selectedId={selectedRedactionId}
              hoveredId={hoveredRedactionId}
              onHover={onRedactionHover}
              onSelect={onRedactionSelect}
            />
          )}
        </div>
      </div>
    </main>
  )
}
