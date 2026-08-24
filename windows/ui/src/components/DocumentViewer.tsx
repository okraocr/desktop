import { useEffect, useMemo, useRef, useState } from 'react'
import * as pdfjs from 'pdfjs-dist'
import type { Block, RedactionBox } from '../types'
import type { AnnotationTool, EditorAnnotation, ViewMode } from '../editor'
import type { PdfDocument, PdfPage } from '../pdf'
import { pagesForMode } from '../document-model'
import { BoxOverlay } from './BoxOverlay'
import { EditorOverlay } from './EditorOverlay'
import { RedactionOverlay } from './RedactionOverlay'

interface Props {
  pdf: PdfDocument
  page: number
  zoom: number
  viewMode: ViewMode
  searchQuery: string
  blocksForPage: (page: number) => Block[]
  redactionsForPage: (page: number) => RedactionBox[]
  showBoxes: boolean
  showRedactions: boolean
  enabledRedactionIds: Set<string>
  selectedBlockId: string | null
  hoveredBlockId: string | null
  selectedRedactionId: string | null
  hoveredRedactionId: string | null
  annotations: EditorAnnotation[]
  editorTool: AnnotationTool
  selectedAnnotationId: string | null
  editorColor: string
  editorOpacity: number
  editorLineWidth: number
  editorFontSize: number
  editorImageDataUrl: string | null
  readOnly?: boolean
  onPageChange: (page: number) => void
  onBlockHover: (id: string | null) => void
  onBlockSelect: (id: string) => void
  onRedactionHover: (id: string | null) => void
  onRedactionSelect: (id: string) => void
  onAnnotationAdd: (annotation: EditorAnnotation) => void
  onAnnotationUpdate: (annotation: EditorAnnotation) => void
  onAnnotationSelect: (id: string | null) => void
  onDestination: (destination: unknown) => void
}

export function DocumentViewer(props: Props) {
  const scroll = useRef<HTMLDivElement>(null)
  const pageElements = useRef(new Map<number, HTMLDivElement>())
  const pages = useMemo(() => pagesForMode(props.viewMode, props.page, props.pdf.numPages), [props.viewMode, props.page, props.pdf.numPages])
  const effectiveZoom = props.viewMode === 'grid' ? Math.min(props.zoom, 0.48) : props.zoom

  useEffect(() => {
    if (props.viewMode === 'single' || props.viewMode === 'two-page' || props.viewMode === 'book') return
    pageElements.current.get(props.page)?.scrollIntoView({ block: 'center' })
  }, [props.page, props.viewMode])

  return (
    <main ref={scroll} className="thin-scroll min-w-0 flex-1 overflow-auto bg-neutral-200 p-5">
      <div
        className={
          props.viewMode === 'grid'
            ? 'mx-auto grid max-w-[1600px] grid-cols-[repeat(auto-fit,minmax(180px,1fr))] items-start gap-4'
            : props.viewMode === 'two-page' || props.viewMode === 'book'
              ? 'mx-auto flex w-fit items-start justify-center gap-4'
              : 'mx-auto flex w-fit flex-col items-center gap-5'
        }
      >
        {pages.map((pageNumber) => (
          <div
            key={pageNumber}
            ref={(element) => {
              if (element) pageElements.current.set(pageNumber, element)
              else pageElements.current.delete(pageNumber)
            }}
            className={`relative ${pageNumber === props.page ? 'ring-2 ring-brand-500 ring-offset-2' : ''}`}
            onMouseDown={() => props.onPageChange(pageNumber)}
          >
            <PdfPageSurface
              pdf={props.pdf}
              pageNumber={pageNumber}
              zoom={effectiveZoom}
              searchQuery={props.searchQuery}
              blocks={props.blocksForPage(pageNumber)}
              redactions={props.redactionsForPage(pageNumber)}
              showBoxes={props.showBoxes}
              showRedactions={props.showRedactions}
              enabledRedactionIds={props.enabledRedactionIds}
              selectedBlockId={props.selectedBlockId}
              hoveredBlockId={props.hoveredBlockId}
              selectedRedactionId={props.selectedRedactionId}
              hoveredRedactionId={props.hoveredRedactionId}
              annotations={props.annotations}
              editorTool={props.readOnly ? 'select' : props.editorTool}
              selectedAnnotationId={props.selectedAnnotationId}
              editorColor={props.editorColor}
              editorOpacity={props.editorOpacity}
              editorLineWidth={props.editorLineWidth}
              editorFontSize={props.editorFontSize}
              editorImageDataUrl={props.editorImageDataUrl}
              readOnly={props.readOnly}
              onBlockHover={props.onBlockHover}
              onBlockSelect={props.onBlockSelect}
              onRedactionHover={props.onRedactionHover}
              onRedactionSelect={props.onRedactionSelect}
              onAnnotationAdd={props.onAnnotationAdd}
              onAnnotationUpdate={props.onAnnotationUpdate}
              onAnnotationSelect={props.onAnnotationSelect}
              onDestination={props.onDestination}
            />
            <div className="pointer-events-none absolute -bottom-5 left-0 right-0 text-center text-[10px] text-neutral-500">{pageNumber}</div>
          </div>
        ))}
      </div>
    </main>
  )
}

interface SurfaceProps {
  pdf: PdfDocument
  pageNumber: number
  zoom: number
  searchQuery: string
  blocks: Block[]
  redactions: RedactionBox[]
  showBoxes: boolean
  showRedactions: boolean
  enabledRedactionIds: Set<string>
  selectedBlockId: string | null
  hoveredBlockId: string | null
  selectedRedactionId: string | null
  hoveredRedactionId: string | null
  annotations: EditorAnnotation[]
  editorTool: AnnotationTool
  selectedAnnotationId: string | null
  editorColor: string
  editorOpacity: number
  editorLineWidth: number
  editorFontSize: number
  editorImageDataUrl: string | null
  readOnly?: boolean
  onBlockHover: (id: string | null) => void
  onBlockSelect: (id: string) => void
  onRedactionHover: (id: string | null) => void
  onRedactionSelect: (id: string) => void
  onAnnotationAdd: (annotation: EditorAnnotation) => void
  onAnnotationUpdate: (annotation: EditorAnnotation) => void
  onAnnotationSelect: (id: string | null) => void
  onDestination: (destination: unknown) => void
}

interface TextItemView {
  id: string
  text: string
  left: number
  top: number
  width: number
  height: number
  angle: number
}

interface LinkView {
  id: string
  left: number
  top: number
  width: number
  height: number
  url?: string
  destination?: unknown
}

function PdfPageSurface(props: SurfaceProps) {
  const canvas = useRef<HTMLCanvasElement>(null)
  const renderTask = useRef<ReturnType<PdfPage['render']> | null>(null)
  const [size, setSize] = useState({ width: 612, height: 792 })
  const [textItems, setTextItems] = useState<TextItemView[]>([])
  const [links, setLinks] = useState<LinkView[]>([])

  useEffect(() => {
    let cancelled = false
    void (async () => {
      const page = await props.pdf.getPage(props.pageNumber)
      if (cancelled || !canvas.current) return
      const dpr = Math.min(window.devicePixelRatio || 1, 2)
      const cssViewport = page.getViewport({ scale: props.zoom })
      const renderViewport = page.getViewport({ scale: props.zoom * dpr })
      const context = canvas.current.getContext('2d')
      if (!context) return
      canvas.current.width = Math.ceil(renderViewport.width)
      canvas.current.height = Math.ceil(renderViewport.height)
      canvas.current.style.width = `${cssViewport.width}px`
      canvas.current.style.height = `${cssViewport.height}px`
      setSize({ width: cssViewport.width, height: cssViewport.height })
      renderTask.current?.cancel()
      renderTask.current = page.render({ canvas: canvas.current, canvasContext: context, viewport: renderViewport })
      try {
        await renderTask.current.promise
      } catch (error) {
        if (!(error instanceof Error) || error.name !== 'RenderingCancelledException') throw error
      }
      if (cancelled) return
      const [content, annotations] = await Promise.all([page.getTextContent(), page.getAnnotations({ intent: 'display' })])
      if (cancelled) return
      setTextItems(textViews(content.items, cssViewport))
      setLinks(linkViews(annotations, cssViewport))
    })()
    return () => {
      cancelled = true
      renderTask.current?.cancel()
    }
  }, [props.pdf, props.pageNumber, props.zoom])

  const query = props.searchQuery.trim().toLocaleLowerCase()
  return (
    <div className="relative overflow-hidden bg-white shadow-lg" style={{ width: size.width, height: size.height }}>
      <canvas ref={canvas} className="block" />
      <div className={`absolute inset-0 overflow-hidden ${props.editorTool === 'select' ? 'select-text' : 'pointer-events-none select-none'}`}>
        {textItems.map((item) => (
          <span
            key={item.id}
            className="absolute origin-top-left whitespace-pre text-transparent"
            style={{
              left: item.left,
              top: item.top,
              width: item.width,
              height: item.height,
              fontSize: item.height,
              lineHeight: 1,
              transform: `rotate(${item.angle}rad)`,
              background: query && item.text.toLocaleLowerCase().includes(query) ? 'rgba(250, 204, 21, 0.45)' : undefined,
            }}
          >
            {item.text}
          </span>
        ))}
      </div>
      <div className="absolute inset-0 pointer-events-none">
        {links.map((link) => (
          <button
            key={link.id}
            aria-label="PDF link"
            className="pointer-events-auto absolute cursor-pointer border-0 bg-transparent hover:bg-sky-300/20"
            style={{ left: link.left, top: link.top, width: link.width, height: link.height }}
            onClick={(event) => {
              event.stopPropagation()
              if (link.url) window.open(link.url, '_blank', 'noopener,noreferrer')
              else if (link.destination) props.onDestination(link.destination)
            }}
          />
        ))}
      </div>
      {props.showBoxes && (
        <BoxOverlay blocks={props.blocks} selectedId={props.selectedBlockId} hoveredId={props.hoveredBlockId} onHover={props.onBlockHover} onSelect={props.onBlockSelect} />
      )}
      {props.showRedactions && (
        <RedactionOverlay boxes={props.redactions} enabledIds={props.enabledRedactionIds} selectedId={props.selectedRedactionId} hoveredId={props.hoveredRedactionId} onHover={props.onRedactionHover} onSelect={props.onRedactionSelect} />
      )}
      <EditorOverlay
          page={props.pageNumber}
          tool={props.readOnly ? 'select' : props.editorTool}
          annotations={props.annotations}
          selectedId={props.selectedAnnotationId}
          color={props.editorColor}
          opacity={props.editorOpacity}
          lineWidth={props.editorLineWidth}
          fontSize={props.editorFontSize}
          imageDataUrl={props.editorImageDataUrl}
          onAdd={props.onAnnotationAdd}
          onUpdate={props.onAnnotationUpdate}
          onSelect={props.onAnnotationSelect}
        />
    </div>
  )
}

function textViews(items: Awaited<ReturnType<PdfPage['getTextContent']>>['items'], viewport: ReturnType<PdfPage['getViewport']>): TextItemView[] {
  const views: TextItemView[] = []
  for (const [index, raw] of items.entries()) {
    if (!('str' in raw) || !raw.str) continue
    const transform = pdfjs.Util.transform(viewport.transform, raw.transform)
    const angle = Math.atan2(transform[1], transform[0])
    const height = Math.max(1, Math.hypot(transform[2], transform[3]))
    views.push({
      id: `${index}-${raw.str}`,
      text: raw.str,
      left: transform[4],
      top: transform[5] - height,
      width: Math.max(1, raw.width * viewport.scale),
      height,
      angle,
    })
  }
  return views
}

function linkViews(annotations: Awaited<ReturnType<PdfPage['getAnnotations']>>, viewport: ReturnType<PdfPage['getViewport']>): LinkView[] {
  return annotations.flatMap((raw, index) => {
    const annotation = raw as typeof raw & { annotationType?: number; subtype?: string; rect?: number[]; url?: string; unsafeUrl?: string; dest?: unknown }
    if (annotation.annotationType !== pdfjs.AnnotationType.LINK && annotation.subtype !== 'Link') return []
    if (!annotation.rect) return []
    const first = viewport.convertToViewportPoint(annotation.rect[0], annotation.rect[1])
    const second = viewport.convertToViewportPoint(annotation.rect[2], annotation.rect[3])
    const converted = [first[0], first[1], second[0], second[1]]
    const left = Math.min(converted[0], converted[2])
    const top = Math.min(converted[1], converted[3])
    return [{
      id: String((annotation as { id?: string }).id ?? index),
      left,
      top,
      width: Math.abs(converted[2] - converted[0]),
      height: Math.abs(converted[3] - converted[1]),
      url: annotation.url ?? annotation.unsafeUrl,
      destination: annotation.dest,
    }]
  })
}
