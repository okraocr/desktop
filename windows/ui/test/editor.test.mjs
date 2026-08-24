import assert from 'node:assert/strict'
import test from 'node:test'
import { PDFDocument } from 'pdf-lib'
import {
  annotationsEqual,
  clearEditorDraft,
  commitEditorHistory,
  redoEditorHistory,
  readEditorDraft,
  undoEditorHistory,
  writeAnnotationsToPdf,
  writeEditorDraft,
} from '../src/editor.ts'

test('writes every P0 annotation kind into a valid PDF copy', async () => {
  const source = await PDFDocument.create()
  source.addPage([612, 792])
  const sourceBytes = await source.save()
  const original = sourceBytes.buffer.slice(sourceBytes.byteOffset, sourceBytes.byteOffset + sourceBytes.byteLength)
  const common = {
    page: 1,
    color: '#166534',
    opacity: 0.75,
    lineWidth: 2,
    fontSize: 14,
  }
  const annotations = [
    { ...common, id: 'text', kind: 'text', x: 0.08, y: 0.08, width: 0.35, height: 0.08, text: 'Local editor smoke' },
    { ...common, id: 'highlight', kind: 'highlight', x: 0.08, y: 0.18, width: 0.35, height: 0.04, fillColor: '#fde047' },
    { ...common, id: 'underline', kind: 'underline', x: 0.08, y: 0.25, width: 0.35, height: 0.04 },
    { ...common, id: 'strikeout', kind: 'strikeout', x: 0.08, y: 0.32, width: 0.35, height: 0.04 },
    { ...common, id: 'line', kind: 'line', x: 0.08, y: 0.4, width: 0.25, height: 0.08, points: [{ x: 0.33, y: 0.4 }, { x: 0.08, y: 0.48 }] },
    { ...common, id: 'rectangle', kind: 'rectangle', x: 0.08, y: 0.5, width: 0.22, height: 0.1 },
    { ...common, id: 'ellipse', kind: 'ellipse', x: 0.35, y: 0.5, width: 0.18, height: 0.1 },
    {
      ...common,
      id: 'draw',
      kind: 'draw',
      x: 0.08,
      y: 0.65,
      width: 0.3,
      height: 0.1,
      points: [{ x: 0.08, y: 0.7 }, { x: 0.18, y: 0.66 }, { x: 0.38, y: 0.73 }],
    },
    {
      ...common,
      id: 'image',
      kind: 'image',
      x: 0.62,
      y: 0.1,
      width: 0.12,
      height: 0.12,
      imageDataUrl: 'data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=',
    },
  ]

  const edited = await writeAnnotationsToPdf(original, annotations)
  assert.equal(new TextDecoder().decode(edited.slice(0, 5)), '%PDF-')
  assert.ok(edited.byteLength > sourceBytes.byteLength)
  const reopened = await PDFDocument.load(edited)
  assert.equal(reopened.getPageCount(), 1)
})

test('round-trips and clears a per-document recovery draft', () => {
  const values = new Map()
  globalThis.localStorage = {
    getItem: (key) => values.get(key) ?? null,
    setItem: (key, value) => values.set(key, String(value)),
    removeItem: (key) => values.delete(key),
    clear: () => values.clear(),
    key: (index) => [...values.keys()][index] ?? null,
    get length() { return values.size },
  }
  const path = 'C:\\docs\\draft.pdf'
  const annotations = [{
    id: 'recovery-text', page: 1, kind: 'text', x: 0.1, y: 0.1, width: 0.2, height: 0.1,
    color: '#000000', opacity: 1, lineWidth: 1, fontSize: 12, text: 'Recovered',
  }]
  writeEditorDraft(path, annotations)
  const recovered = readEditorDraft(path)
  assert.ok(recovered)
  assert.equal(recovered.sourcePath, path)
  assert.ok(annotationsEqual(recovered.annotations, annotations))
  clearEditorDraft(path)
  assert.equal(readEditorDraft(path), null)
})

test('keeps undo and redo history isolated in the supplied document state', () => {
  const first = [{
    id: 'first', page: 1, kind: 'text', x: 0.1, y: 0.1, width: 0.2, height: 0.1,
    color: '#000000', opacity: 1, lineWidth: 1, fontSize: 12, text: 'First',
  }]
  const second = [{ ...first[0], id: 'second', text: 'Second' }]
  let state = { annotations: [], undo: [], redo: [] }
  state = commitEditorHistory(state, first)
  state = commitEditorHistory(state, second)
  const undone = undoEditorHistory(state)
  assert.ok(undone)
  assert.ok(annotationsEqual(undone.annotations, first))
  const redone = redoEditorHistory(undone)
  assert.ok(redone)
  assert.ok(annotationsEqual(redone.annotations, second))
})
