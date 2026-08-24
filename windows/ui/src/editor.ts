import {
  BlendMode,
  PDFDocument as PdfLibDocument,
  StandardFonts,
  rgb,
} from 'pdf-lib'

export type ViewMode = 'single' | 'continuous' | 'two-page' | 'book' | 'grid'

export type AnnotationTool =
  | 'select'
  | 'text'
  | 'highlight'
  | 'underline'
  | 'strikeout'
  | 'draw'
  | 'line'
  | 'rectangle'
  | 'ellipse'
  | 'image'

export interface EditorPoint {
  x: number
  y: number
}

export interface EditorAnnotation {
  id: string
  page: number
  kind: Exclude<AnnotationTool, 'select'>
  x: number
  y: number
  width: number
  height: number
  color: string
  fillColor?: string
  opacity: number
  lineWidth: number
  fontSize: number
  text?: string
  points?: EditorPoint[]
  imageDataUrl?: string
}

export interface EditorDraft {
  version: 1
  sourcePath: string
  savedAt: string
  annotations: EditorAnnotation[]
}

export interface EditorHistory {
  annotations: EditorAnnotation[]
  undo: EditorAnnotation[][]
  redo: EditorAnnotation[][]
}

export function createAnnotationId(): string {
  return globalThis.crypto?.randomUUID?.() ?? `annotation-${Date.now()}-${Math.random().toString(16).slice(2)}`
}

export function editorDraftKey(sourcePath: string): string {
  let hash = 2166136261
  for (let index = 0; index < sourcePath.length; index++) {
    hash ^= sourcePath.charCodeAt(index)
    hash = Math.imul(hash, 16777619)
  }
  return `okra-editor-draft-v1:${(hash >>> 0).toString(16)}`
}

export function readEditorDraft(sourcePath: string): EditorDraft | null {
  try {
    const raw = localStorage.getItem(editorDraftKey(sourcePath))
    if (!raw) return null
    const draft = JSON.parse(raw) as EditorDraft
    if (draft.version !== 1 || draft.sourcePath !== sourcePath || !Array.isArray(draft.annotations)) return null
    return draft
  } catch {
    return null
  }
}

export function writeEditorDraft(sourcePath: string, annotations: EditorAnnotation[]): void {
  const draft: EditorDraft = {
    version: 1,
    sourcePath,
    savedAt: new Date().toISOString(),
    annotations,
  }
  localStorage.setItem(editorDraftKey(sourcePath), JSON.stringify(draft))
}

export function clearEditorDraft(sourcePath: string): void {
  localStorage.removeItem(editorDraftKey(sourcePath))
}

export function annotationsEqual(left: EditorAnnotation[], right: EditorAnnotation[]): boolean {
  return JSON.stringify(left) === JSON.stringify(right)
}

export function commitEditorHistory(current: EditorHistory, annotations: EditorAnnotation[], record = true): EditorHistory {
  return {
    annotations,
    undo: record ? [...current.undo, current.annotations] : current.undo,
    redo: record ? [] : current.redo,
  }
}

export function undoEditorHistory(current: EditorHistory): EditorHistory | null {
  const annotations = current.undo[current.undo.length - 1]
  if (!annotations) return null
  return {
    annotations,
    undo: current.undo.slice(0, -1),
    redo: [current.annotations, ...current.redo],
  }
}

export function redoEditorHistory(current: EditorHistory): EditorHistory | null {
  const annotations = current.redo[0]
  if (!annotations) return null
  return {
    annotations,
    undo: [...current.undo, current.annotations],
    redo: current.redo.slice(1),
  }
}

export async function writeAnnotationsToPdf(
  originalBytes: ArrayBuffer,
  annotations: EditorAnnotation[],
): Promise<Uint8Array> {
  const document = await PdfLibDocument.load(originalBytes.slice(0))
  const font = await document.embedFont(StandardFonts.Helvetica)
  const pages = document.getPages()
  const imageCache = new Map<string, Awaited<ReturnType<typeof document.embedPng>>>()

  for (const annotation of annotations) {
    const page = pages[annotation.page - 1]
    if (!page) continue
    const { width: pageWidth, height: pageHeight } = page.getSize()
    const x = annotation.x * pageWidth
    const y = pageHeight - (annotation.y + annotation.height) * pageHeight
    const width = annotation.width * pageWidth
    const height = annotation.height * pageHeight
    const color = parseHexColor(annotation.color)
    const fillColor = parseHexColor(annotation.fillColor ?? annotation.color)
    const thickness = Math.max(0.5, annotation.lineWidth * Math.min(pageWidth, pageHeight) * 0.002)

    switch (annotation.kind) {
      case 'text': {
        const size = Math.max(6, annotation.fontSize)
        const lines = wrapText(annotation.text ?? '', Math.max(width, size), size)
        let lineY = pageHeight - annotation.y * pageHeight - size
        for (const line of lines) {
          page.drawText(line, { x, y: lineY, size, font, color, opacity: annotation.opacity })
          lineY -= size * 1.2
          if (lineY < y) break
        }
        break
      }
      case 'highlight':
        page.drawRectangle({
          x,
          y,
          width,
          height,
          color: fillColor,
          opacity: annotation.opacity,
          blendMode: BlendMode.Multiply,
        })
        break
      case 'underline':
        page.drawLine({
          start: { x, y: y + Math.max(1, height * 0.08) },
          end: { x: x + width, y: y + Math.max(1, height * 0.08) },
          color,
          opacity: annotation.opacity,
          thickness,
        })
        break
      case 'strikeout':
        page.drawLine({
          start: { x, y: y + height * 0.5 },
          end: { x: x + width, y: y + height * 0.5 },
          color,
          opacity: annotation.opacity,
          thickness,
        })
        break
      case 'line':
        {
        const start = annotation.points?.[0]
        const end = annotation.points?.[1]
        page.drawLine({
          start: start
            ? { x: start.x * pageWidth, y: pageHeight - start.y * pageHeight }
            : { x, y: pageHeight - annotation.y * pageHeight },
          end: end
            ? { x: end.x * pageWidth, y: pageHeight - end.y * pageHeight }
            : { x: x + width, y },
          color,
          opacity: annotation.opacity,
          thickness,
        })
        break
        }
      case 'rectangle':
        page.drawRectangle({
          x,
          y,
          width,
          height,
          borderColor: color,
          borderWidth: thickness,
          color: annotation.fillColor ? fillColor : undefined,
          opacity: annotation.fillColor ? annotation.opacity * 0.35 : undefined,
          borderOpacity: annotation.opacity,
        })
        break
      case 'ellipse':
        page.drawEllipse({
          x: x + width / 2,
          y: y + height / 2,
          xScale: width / 2,
          yScale: height / 2,
          borderColor: color,
          borderWidth: thickness,
          color: annotation.fillColor ? fillColor : undefined,
          opacity: annotation.fillColor ? annotation.opacity * 0.35 : undefined,
          borderOpacity: annotation.opacity,
        })
        break
      case 'draw': {
        const points = annotation.points ?? []
        for (let index = 1; index < points.length; index++) {
          const previous = points[index - 1]
          const current = points[index]
          page.drawLine({
            start: { x: previous.x * pageWidth, y: pageHeight - previous.y * pageHeight },
            end: { x: current.x * pageWidth, y: pageHeight - current.y * pageHeight },
            color,
            opacity: annotation.opacity,
            thickness,
          })
        }
        break
      }
      case 'image': {
        if (!annotation.imageDataUrl) break
        let embedded = imageCache.get(annotation.imageDataUrl)
        if (!embedded) {
          const bytes = dataUrlBytes(annotation.imageDataUrl)
          embedded = annotation.imageDataUrl.startsWith('data:image/jpeg')
            ? await document.embedJpg(bytes)
            : await document.embedPng(bytes)
          imageCache.set(annotation.imageDataUrl, embedded)
        }
        page.drawImage(embedded, { x, y, width, height, opacity: annotation.opacity })
        break
      }
    }
  }

  return document.save({ useObjectStreams: true })
}

function parseHexColor(value: string) {
  const normalized = value.replace('#', '')
  const full = normalized.length === 3 ? normalized.split('').map((part) => part + part).join('') : normalized
  const parsed = Number.parseInt(full, 16)
  if (!Number.isFinite(parsed)) return rgb(0, 0, 0)
  return rgb(((parsed >> 16) & 255) / 255, ((parsed >> 8) & 255) / 255, (parsed & 255) / 255)
}

function dataUrlBytes(dataUrl: string): Uint8Array {
  const encoded = dataUrl.split(',', 2)[1] ?? ''
  const binary = atob(encoded)
  return Uint8Array.from(binary, (character) => character.charCodeAt(0))
}

function wrapText(value: string, maxWidth: number, fontSize: number): string[] {
  const approximateCharacters = Math.max(1, Math.floor(maxWidth / (fontSize * 0.55)))
  const lines: string[] = []
  for (const paragraph of value.split(/\r?\n/)) {
    const words = paragraph.split(/\s+/)
    let current = ''
    for (const word of words) {
      if (!word) continue
      const candidate = current ? `${current} ${word}` : word
      if (candidate.length > approximateCharacters && current) {
        lines.push(current)
        current = word
      } else {
        current = candidate
      }
    }
    lines.push(current)
  }
  return lines.length > 0 ? lines : ['']
}
