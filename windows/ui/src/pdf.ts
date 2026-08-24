import * as pdfjs from 'pdfjs-dist'
import { PDFDocument as PdfLibDocument } from 'pdf-lib'
import workerUrl from 'pdfjs-dist/build/pdf.worker.min.mjs?url'
import type { NativeLine, RedactionBox } from './types'

pdfjs.GlobalWorkerOptions.workerSrc = workerUrl

export type PdfDocument = pdfjs.PDFDocumentProxy
export type PdfPage = pdfjs.PDFPageProxy

export async function loadPdf(data: ArrayBuffer): Promise<PdfDocument> {
  return pdfjs.getDocument({ data }).promise
}

// Renders a page into a canvas at the given CSS scale, using the device pixel
// ratio for crispness. Returns the CSS-pixel size of the rendered page.
export async function renderPageToCanvas(
  page: PdfPage,
  canvas: HTMLCanvasElement,
  cssScale: number,
): Promise<{ width: number; height: number }> {
  const dpr = Math.min(window.devicePixelRatio || 1, 2)
  const viewport = page.getViewport({ scale: cssScale * dpr })
  const context = canvas.getContext('2d')
  if (!context) throw new Error('no 2d context')
  canvas.width = Math.floor(viewport.width)
  canvas.height = Math.floor(viewport.height)
  canvas.style.width = `${Math.floor(viewport.width / dpr)}px`
  canvas.style.height = `${Math.floor(viewport.height / dpr)}px`
  await page.render({ canvas, canvasContext: context, viewport }).promise
  return { width: viewport.width / dpr, height: viewport.height / dpr }
}

// Renders a page to a PNG (base64, no data: prefix) sized for OCR: capped at
// maxDim on the long edge so Windows.Media.Ocr accepts it (limit ~2600px).
export async function renderPagePngBase64(page: PdfPage, maxDim = 2000): Promise<string> {
  const base = page.getViewport({ scale: 1 })
  const scale = Math.min(2, maxDim / Math.max(base.width, base.height))
  const viewport = page.getViewport({ scale: Math.max(scale, 0.5) })
  const canvas = document.createElement('canvas')
  canvas.width = Math.floor(viewport.width)
  canvas.height = Math.floor(viewport.height)
  const context = canvas.getContext('2d')
  if (!context) throw new Error('no 2d context')
  await page.render({ canvas, canvasContext: context, viewport }).promise
  const dataUrl = canvas.toDataURL('image/png')
  return dataUrl.slice('data:image/png;base64,'.length)
}

interface LineAccumulator {
  x: number
  y: number
  width: number
  height: number
  parts: { x: number; text: string }[]
}

// Extracts embedded text lines with normalized top-left bounding boxes from
// the PDF.js text layer (the equivalent of PDFKit selections on macOS).
export async function extractNativeLines(page: PdfPage): Promise<NativeLine[]> {
  const viewport = page.getViewport({ scale: 1 })
  const viewBox = viewport.viewBox as number[] // [x1, y1, x2, y2] user space
  const pageWidth = viewBox[2] - viewBox[0]
  const pageHeight = viewBox[3] - viewBox[1]
  if (pageWidth <= 0 || pageHeight <= 0) return []

  const content = await page.getTextContent()
  const items: { text: string; x: number; y: number; width: number; height: number }[] = []
  for (const item of content.items) {
    if (!('str' in item)) continue
    const text = item.str
    if (!text || !text.trim()) continue
    const x = item.transform[4] as number
    const y = item.transform[5] as number
    const width = item.width as number
    const height = (item.height as number) || Math.abs(item.transform[3] as number) || 10
    // PDF user space is bottom-left origin; the text matrix origin sits on the
    // baseline, so the line top is (viewBox top - baseline y - line height).
    const nx = (x - viewBox[0]) / pageWidth
    const ny = (viewBox[3] - y - height) / pageHeight
    items.push({
      text,
      x: nx,
      y: ny,
      width: width / pageWidth,
      height: height / pageHeight,
    })
  }
  items.sort((a, b) => (Math.abs(a.y - b.y) > 0.0001 ? a.y - b.y : a.x - b.x))

  const lines: LineAccumulator[] = []
  for (const item of items) {
    const last = lines[lines.length - 1]
    const tolerance = Math.max(item.height, last?.height ?? 0) * 0.5
    if (last && Math.abs(item.y - last.y) <= tolerance) {
      const right = Math.max(last.x + last.width, item.x + item.width)
      const bottom = Math.max(last.y + last.height, item.y + item.height)
      last.x = Math.min(last.x, item.x)
      last.y = Math.min(last.y, item.y)
      last.width = right - last.x
      last.height = bottom - last.y
      last.parts.push({ x: item.x, text: item.text })
    } else {
      lines.push({ x: item.x, y: item.y, width: item.width, height: item.height, parts: [{ x: item.x, text: item.text }] })
    }
  }

  return lines.map((line) => {
    line.parts.sort((a, b) => a.x - b.x)
    let text = ''
    for (const part of line.parts) {
      if (text && !text.endsWith(' ') && !part.text.startsWith(' ')) text += ' '
      text += part.text
    }
    return { text: text.trim(), x: line.x, y: line.y, width: line.width, height: line.height }
  })
}

// Counts non-whitespace characters, mirroring the native-text quality gate.
const invisibleNativeTextCharacter =
  /[\p{White_Space}\p{Default_Ignorable_Code_Point}\p{Control}]/u

export function visibleCharCount(lines: NativeLine[]): number {
  let count = 0
  for (const line of lines) {
    for (const ch of line.text) {
      if (!invisibleNativeTextCharacter.test(ch)) count++
    }
  }
  return count
}

export const NATIVE_TEXT_MIN_CHARS = 24

// Creates a new PDF without mutating the source. Pages with approved
// redactions are rasterized before black boxes are drawn, which removes the
// underlying glyphs instead of leaving selectable text under an overlay.
// Unaffected pages are copied from the original PDF without rasterization.
export async function rasterizeRedactedPdf(
  pdf: PdfDocument,
  originalBytes: ArrayBuffer,
  redactions: RedactionBox[],
): Promise<Uint8Array> {
  if (redactions.length === 0) throw new Error('Choose at least one redaction box.')
  const source = await PdfLibDocument.load(originalBytes.slice(0))
  const output = await PdfLibDocument.create()
  const byPage = new Map<number, RedactionBox[]>()
  for (const box of redactions) {
    const pageBoxes = byPage.get(box.page) ?? []
    pageBoxes.push(box)
    byPage.set(box.page, pageBoxes)
  }

  for (let pageNumber = 1; pageNumber <= pdf.numPages; pageNumber++) {
    const pageBoxes = byPage.get(pageNumber) ?? []
    if (pageBoxes.length === 0) {
      const [copied] = await output.copyPages(source, [pageNumber - 1])
      output.addPage(copied)
      continue
    }

    const page = await pdf.getPage(pageNumber)
    const baseViewport = page.getViewport({ scale: 1 })
    const renderViewport = page.getViewport({ scale: 2 })
    const canvas = document.createElement('canvas')
    canvas.width = Math.ceil(renderViewport.width)
    canvas.height = Math.ceil(renderViewport.height)
    const context = canvas.getContext('2d')
    if (!context) throw new Error('Could not prepare the redaction canvas.')
    await page.render({ canvas, canvasContext: context, viewport: renderViewport }).promise

    context.fillStyle = '#000000'
    for (const box of pageBoxes) {
      // Two output pixels of padding prevent antialiased glyph edges leaking.
      const x = Math.max(0, box.x * canvas.width - 2)
      const y = Math.max(0, box.y * canvas.height - 2)
      const width = Math.min(canvas.width - x, box.w * canvas.width + 4)
      const height = Math.min(canvas.height - y, box.h * canvas.height + 4)
      context.fillRect(x, y, width, height)
    }

    const png = await canvasToPngBytes(canvas)
    const embedded = await output.embedPng(png)
    const outPage = output.addPage([baseViewport.width, baseViewport.height])
    outPage.drawImage(embedded, {
      x: 0,
      y: 0,
      width: baseViewport.width,
      height: baseViewport.height,
    })
  }
  return output.save({ useObjectStreams: true })
}

function canvasToPngBytes(canvas: HTMLCanvasElement): Promise<Uint8Array> {
  return new Promise((resolve, reject) => {
    canvas.toBlob((blob) => {
      if (!blob) {
        reject(new Error('Could not render a redacted PDF page.'))
        return
      }
      blob.arrayBuffer().then((buffer) => resolve(new Uint8Array(buffer)), reject)
    }, 'image/png')
  })
}
